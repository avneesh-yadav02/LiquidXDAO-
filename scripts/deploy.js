const { ethers } = require("hardhat");

async function main() {
  const LiquidXDAO = await ethers.getContractFactory("LiquidXDAO");
  const liquidXDAO = await LiquidXDAO.deploy();

  await liquidXDAO.deployed();

  console.log("LiquidXDAO contract deployed to:", liquidXDAO.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

