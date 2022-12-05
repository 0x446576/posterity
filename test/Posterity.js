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
      expect(await posterity.balanceOf(owner.address)).to.equal(100)

      await expect(posterity.claim(owner.address, proof)).to.be.revertedWith("Posterity::claim: molecule is already alive.")
    
      expect(await posterity.getState(1, owner.address)).to.equal(1)
      expect(await posterity.getLastBalanced(1, owner.address)).to.equal(0)
    });
  });

  describe("Burning", function () {
    it("Should burn all the settler tokens", async function () {
      const { posterity, owner, merkleTree } = await loadFixture(deployLocalSociety);
      let proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)

      await posterity.claim(owner.address, proof)
      expect(await posterity.balanceOf(owner.address)).to.equal(100)
      await posterity.burn(100)
      expect(await posterity.balanceOf(owner.address)).to.equal(0)
    });
  })

  describe("Transfering", function () {
    it("Should transfer full amount of knowledge to another recipient", async function () {
      const { posterity, owner, otherAccount, merkleTree } = await loadFixture(deployLocalSociety);
      let proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)

      await posterity.claim(owner.address, proof)
      expect(await posterity.balanceOf(owner.address)).to.equal(100)
      await posterity.transfer(otherAccount.address, 100)

      expect(await posterity.balanceOf(owner.address)).to.equal(0)
      expect(await posterity.balanceOf(otherAccount.address)).to.equal(100)

      expect(await posterity.getLastBalanced(1, owner.address)).to.not.equal(0)
    });
  });
});
