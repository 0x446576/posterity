const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");

const { MerkleTree } = require("merkletreejs")
const keccak256 = require("keccak256")

describe("Posterity", () => {
  async function deployBadgeAuthority() {
    const [owner, otherAccount] = await ethers.getSigners();

    const BadgeAuthority = await ethers.getContractFactory("BadgeAuthority");
    const badgeAuthority = await BadgeAuthority.deploy();

    return { badgeAuthority, owner, otherAccount };
  }

  async function deployFactory() {
    const [owner, otherAccount] = await ethers.getSigners();

    const Society = await ethers.getContractFactory("Society");
    const society = await Society.deploy();

    return { society, owner, otherAccount };
  }

  async function deployPosterity() {
    const { badgeAuthority } = await loadFixture(deployBadgeAuthority);
    const { society, owner, otherAccount } = await loadFixture(deployFactory);

    let addresses = [owner.address, otherAccount.address]

    let leaves = addresses.map(addr => keccak256(addr))
    let merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true })
    let rootHash = merkleTree.getRoot().toString('hex')

    function bitpackuint32s(uints) {
      let packed = 0n
      for (let i = 0; i < uints.length; i++) {
        packed = packed | (BigInt(uints[i]) << BigInt(32 * i))
      }
      return packed
    }

    const generationConfiguration = bitpackuint32s([1000000000, 86, 1])

    // setup the gradual dutch auction where the planned rate is 20 tokens per week 
    const initialPrice = 1
    const decayConstant = 999999999
    const emissionRate = 500000000

    const snapshot = {
      name: "Local Society",
      symbol: "LS",
      deployer: owner.address,
      authority: badgeAuthority.address,
      initialPrice,
      decayConstant,
      emissionRate,
      generationConfiguration,
      generationMerkleRoot: `0x${rootHash}`,
    }

    const tx = await society.deploySociety(snapshot);
    const receipt = await tx.wait();

    const [event] = receipt.events.filter((e) => e.event === "SocietyBirth");
    const posterity = await ethers.getContractAt("Posterity", event.args.posterity);

    return { posterity, owner, otherAccount, merkleTree, rootHash };
  }

  describe("Deployment", () => {
    it("Should successfully deploy a Badge Authority.", async () => {
      const { badgeAuthority, owner, otherAccount } = await loadFixture(deployBadgeAuthority);
      await badgeAuthority.deployed();

      expect(badgeAuthority.address).to.not.equal(ethers.constants.AddressZero);
    });

    it("Should successfully deploy a Factory.", async () => {
      const { society, owner, otherAccount } = await loadFixture(deployFactory);
      await society.deployed();

      expect(society.address).to.not.equal(ethers.constants.AddressZero);
    });

    it("Should successfully deploy a Society.", async () => {
      const { posterity, owner, otherAccount, rootHash } = await loadFixture(deployPosterity);

      expect(await posterity.name()).to.equal("Local Society");
      expect(await posterity.symbol()).to.equal("LS");
      expect(await posterity.owner()).to.equal(owner.address);
      expect(await posterity.getGenerationCapacity(1)).to.equal(1000000000);
      expect(await posterity.getGenerationDecayRate(1)).to.equal(86);
      expect(await posterity.getGenerationBaseKnowledgeLossRate(1)).to.equal(1);
      expect(await posterity.generationMerkleRoot()).to.equal(`0x${rootHash}`);
    });
  })

  describe("Minting", function () {
    it("Should claim the settler tokens", async function () {
      const { posterity, owner, otherAccount, merkleTree } = await loadFixture(deployPosterity);

      let proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)
      proof[0] = keccak256(proof[0])
      await expect(posterity.claim(owner.address, proof)).to.be.revertedWith("Posterity::claim: Invalid proof of permission to settle.")

      proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)

      await (await posterity.claim(owner.address, proof)).wait()
      expect(await posterity.balanceOf(owner.address)).to.equal(1000000001)

      await expect(posterity.claim(owner.address, proof)).to.be.revertedWith("Posterity::claim: molecule is already alive.")

      expect(await posterity["getState(uint32,address)"](1, owner.address)).to.equal(1)
      expect(await posterity.getLastBalanced(1, owner.address)).to.equal(0)

      proof = merkleTree.getProof(keccak256(otherAccount.address)).map(p => p.data)

      await (await posterity.claim(otherAccount.address, proof)).wait()
      expect(await posterity.balanceOf(otherAccount.address)).to.equal(1000000001)
    });
  });

  describe("Transfering", function () {
    it("Should transfer full amount of knowledge to another recipient", async function () {
      const { posterity, owner, otherAccount, merkleTree } = await loadFixture(deployPosterity);
      let proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)

      await (await posterity.claim(owner.address, proof)).wait()
      expect(await posterity.balanceOf(owner.address)).to.equal(1000000001)
      const decay = await posterity.getKnowledgeDecay(owner.address)
      await (await posterity.transfer(otherAccount.address, 1000000001 -  decay)).wait()
      expect(await posterity["getState(uint32,address)"](1, owner.address)).to.equal(2)

      expect(await posterity.balanceOf(owner.address)).to.equal(0)
      expect(await posterity.balanceOf(otherAccount.address)).to.equal(1000000001 -  decay)
    });

    it("Should transfer full amount of knowledge to another recipient after 100 days", async function () {
      const { posterity, owner, otherAccount, merkleTree } = await loadFixture(deployPosterity);
      let proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)

      await (await posterity.claim(owner.address, proof)).wait()
      expect(await posterity.balanceOf(owner.address)).to.equal(1000000001)

      await ethers.provider.send("evm_increaseTime", [86400 * 100])
      await ethers.provider.send("evm_mine")

      const decay = await posterity.getKnowledgeDecay(owner.address)

      await (await posterity.transfer(otherAccount.address, 1000000001 -  decay)).wait()
      expect(await posterity["getState(uint32,address)"](1, owner.address)).to.equal(2)

      expect(await posterity.balanceOf(owner.address)).to.equal(0)
      expect(await posterity.balanceOf(otherAccount.address)).to.equal(1000000001 -  decay)
    });


    it.only("Should birth new member with single transfer", async function () {
      const { posterity, owner, otherAccount, merkleTree } = await loadFixture(deployPosterity);
      let proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)

      // claim the settler tokens
      await (await posterity.claim(owner.address, proof)).wait()
      expect(await posterity.balanceOf(owner.address)).to.equal(1000000001)
      expect(await posterity["getState(uint32,address)"](1, owner.address)).to.equal(1)

      // loop through 50 days
      for (let i = 0; i < 100; i++) {
        let erosion = await posterity.getKnowledgeErosion(1);
        await ethers.provider.send("evm_increaseTime", [86400])
        await ethers.provider.send("evm_mine")
      }

      await (await posterity.transfer(otherAccount.address, 1)).wait()
      expect(await posterity["getState(uint32,address)"](1, owner.address)).to.equal(1)     

      // pays the cost of the knowledge share
      // let cost = 2
      // expect(await posterity.balanceOf(owner.address)).to.equal(101 - cost)

      // // receives the knowledge share and is spawned with their own capacity
      // expect(await posterity.balanceOf(otherAccount.address)).to.equal(101)
      // expect(await posterity.getLastBalanced(1, owner.address)).to.not.equal(0)
      // expect(await posterity["getState(uint32,address)"](1, owner.address)).to.equal(1)
    })
  });


  //   it("Should handle decay before transfer", async function () {
  //     const { posterity, owner, otherAccount, merkleTree } = await loadFixture(deployLocalSociety);
  //     let proof = merkleTree.getProof(keccak256(owner.address)).map(p => p.data)

  //     // claim the settler tokens
  //     await posterity.claim(owner.address, proof)
  //     expect(await posterity.balanceOf(owner.address)).to.equal(101)

  //     // go 2000 blocks in the future using hardhat
  //     await time.advanceBlockTo(10000000000)
  //     const knowledgeDecay = await posterity.getKnowledgeDecay(owner.address)
  //     expect(knowledgeDecay).to.gt(10000)

  //     await expect(posterity.transfer(otherAccount.address, 101)).to.be.revertedWith("Posterity::_setKnowledge: too much knowledge to transfer.")

  //     // cannot claim as another account and refill the dead account
  //     proof = merkleTree.getProof(keccak256(otherAccount.address)).map(p => p.data)
  //     await posterity.connect(otherAccount).claim(otherAccount.address, proof)
  //     expect(await posterity.balanceOf(otherAccount.address)).to.equal(101)
  //     await expect(posterity.connect(otherAccount).transfer(owner.address, 101)).to.be.revertedWith("Posterity::_knowledgeTransfer: Cannot house knowledge in a carcass.")
  //   })
  // });
});
