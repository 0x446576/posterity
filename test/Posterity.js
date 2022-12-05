const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const { MerkleTree } = require("merkletreejs")
const keccak256 = require("keccak256")

describe("Posterity", function () {
  async function deployLocalSociety() {
    const name = "Local Society"
    const symbol = "LS"
    const generationCapacity = 100
    const generationDecayRate = 604800
    const generationBaseKnowledgeLossRate = 1

    const [owner, otherAccount] = await ethers.getSigners();

    let addresses = [owner.address, otherAccount.address]

    let leaves = addresses.map(addr => keccak256(addr))
    let merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true })
    let rootHash = merkleTree.getRoot().toString('hex')

    const Posterity = await ethers.getContractFactory("Posterity");
    const posterity = await Posterity.deploy(
      name,
      symbol,
      generationCapacity,
      generationDecayRate,
      generationBaseKnowledgeLossRate,
      `0x${rootHash}`
    );

    return { posterity, owner, otherAccount, merkleTree, rootHash };
  }

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      const { posterity, owner } = await loadFixture(deployLocalSociety);
      expect(await posterity.owner()).to.equal(owner.address);
    });

    it("Should set the right name", async function () {
      const { posterity } = await loadFixture(deployLocalSociety);
      expect(await posterity.name()).to.equal("Local Society");
    });

    it("Should set the right symbol", async function () {
      const { posterity } = await loadFixture(deployLocalSociety);
      expect(await posterity.symbol()).to.equal("LS");
    });

    it("Should set the right generation capacity", async function () {
      const { posterity } = await loadFixture(deployLocalSociety);
      expect(await posterity.getGenerationCapacity(1)).to.equal(100);
    });

    it("Should set the right generation decay rate", async function () {
      const { posterity } = await loadFixture(deployLocalSociety);
      expect(await posterity.getGenerationDecayRate(1)).to.equal(604800);
    });

    it("Should set the right root hash", async function () {
      const { posterity, rootHash } = await loadFixture(deployLocalSociety);
      expect(await posterity.generationMerkleRoot()).to.equal(`0x${rootHash}`);
    });
  });

  describe("Minting", function () {
    it("Should claim the settler tokens", async function () {
      const { posterity, owner, merkleTree } = await loadFixture(deployLocalSociety);

      let proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)
      proof[0] = keccak256(proof[0])
      await expect(posterity.claim(owner.address, proof)).to.be.revertedWith("Posterity::claim: Invalid proof of permission to settle.")

      proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)

      await posterity.claim(owner.address, proof)
      expect(await posterity.balanceOf(owner.address)).to.equal(101)

      await expect(posterity.claim(owner.address, proof)).to.be.revertedWith("Posterity::claim: molecule is already alive.")

      expect(await posterity["getState(uint32,address)"](1, owner.address)).to.equal(1)
      expect(await posterity.getLastBalanced(1, owner.address)).to.equal(0)
    });
  });

  describe("Transfering", function () {
    it("Should transfer full amount of knowledge to another recipient", async function () {
      const { posterity, owner, otherAccount, merkleTree } = await loadFixture(deployLocalSociety);
      let proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)

      await posterity.claim(owner.address, proof)
      expect(await posterity.balanceOf(owner.address)).to.equal(101)
      await posterity.transfer(otherAccount.address, 101)
      expect(await posterity["getState(uint32,address)"](1, owner.address)).to.equal(2)

      expect(await posterity.balanceOf(owner.address)).to.equal(0)
      expect(await posterity.balanceOf(otherAccount.address)).to.equal(101)
    });

    it("Should birth new member with single transfer", async function () {
      const { posterity, owner, otherAccount, merkleTree } = await loadFixture(deployLocalSociety);
      let proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)

      // claim the settler tokens
      await posterity.claim(owner.address, proof)
      expect(await posterity.balanceOf(owner.address)).to.equal(101)
      expect(await posterity["getState(uint32,address)"](1, owner.address)).to.equal(1)
      await posterity.transfer(otherAccount.address, 1)
      expect(await posterity["getState(uint32,address)"](1, owner.address)).to.equal(1)

      // pays the cost of the knowledge share
      let cost = 2
      expect(await posterity.balanceOf(owner.address)).to.equal(101 - cost)

      // receives the knowledge share and is spawned with their own capacity
      expect(await posterity.balanceOf(otherAccount.address)).to.equal(101)
      expect(await posterity.getLastBalanced(1, owner.address)).to.not.equal(0)
      expect(await posterity["getState(uint32,address)"](1, owner.address)).to.equal(1)
    })

    it("Should handle decay before transfer", async function () {
      const { posterity, owner, otherAccount, merkleTree } = await loadFixture(deployLocalSociety);
      let proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)

      // claim the settler tokens
      await posterity.claim(owner.address, proof)
      expect(await posterity.balanceOf(owner.address)).to.equal(101)

      // go 2000 blocks in the future using hardhat
      await time.advanceBlockTo(10000000000)
      const knowledgeDecay = await posterity.getKnowledgeDecay(owner.address)
      expect(knowledgeDecay).to.gt(10000)

      await expect(posterity.transfer(otherAccount.address, 101)).to.be.revertedWith("Posterity::_setKnowledge: too much knowledge to transfer.")

      // cannot claim as another account and refill the dead account
      proof = merkleTree.getProof(keccak256(otherAccount.address)).map(p => p.data)
      await posterity.connect(otherAccount).claim(otherAccount.address, proof)
      expect(await posterity.balanceOf(otherAccount.address)).to.equal(101)
      await expect(posterity.connect(otherAccount).transfer(owner.address, 101)).to.be.revertedWith("Posterity::_knowledgeTransfer: Cannot house knowledge in a carcass.")
    })
  });
});
