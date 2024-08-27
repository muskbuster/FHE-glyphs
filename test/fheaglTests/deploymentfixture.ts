import type { FHEglyphs } from "../../types";
import { getSigners } from "../signers";
import { ethers } from "hardhat";
export async function deployFHEglyphsFixture(): Promise<FHEglyphs> {
  const signers = await getSigners();

  const contractFactory = await ethers.getContractFactory("FHEglyphs");
  const contract = await contractFactory.connect(signers.alice).deploy();
  await contract.waitForDeployment();
  return contract as FHEglyphs;
}

