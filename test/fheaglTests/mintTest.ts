import {expect,assert} from "chai";
import {ethers} from "hardhat";
import {createInstances,decrypt64} from "../instance";
import { awaitAllDecryptionResults } from "../asyncDecrypt";
import {getSigners,initSigners} from "../signers";
import {deployFHEglyphsFixture} from "./deploymentfixture";

describe("FHEglyphs mint", function () {
before (async function () {
await initSigners();
this.signers = await getSigners();
}
);
beforeEach (async function () {
const contract = await deployFHEglyphsFixture();
this.contractAddress = await contract.getAddress();
this.fheglyphs = contract;
this.instances = await createInstances(this.signers);
}
);
it("should initiate mint NFT", async function () {  
const transaction = await this.fheglyphs.createGlyph();
await transaction.wait();
console.log("transaction: ",transaction);
await awaitAllDecryptionResults();
const balanceHandle = await this.fheglyphs.balanceOf(this.signers.alice);
 const uri = await this.fheglyphs.tokenURI(1);
 console.log("URI: ",uri);
expect(balanceHandle).to.equal(1);
}
);
// it("should transfer NFT between two users", async function () {
// const transaction = await this.fheglyphs.createGlyph();
// const t1 = await transaction.wait();
// const glyphId = transaction.euint64;
// console.log("transfering token");
// expect(t1?.status).to.eq(1);
// const approve = await this.fheglyphs.approve(this.signers.bob.address,glyphId);
// const transfer = await this.fheglyphs.safeTransferFrom(this.signers.alice.address,this.signers.bob.address,glyphId);
// const balanceHandleAlice = await this.fheglyphs.balanceOf(this.signers.alice);
// const balanceHandleBob = await this.fheglyphs.balanceOf(this.signers.bob);
// expect(balanceHandleAlice).to.equal(0);
// expect(balanceHandleBob).to.equal(1);
// }
// );

}
);
