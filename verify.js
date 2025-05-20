// Verification script for deployed contracts
const hre = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("Verifying deployed contracts...");

  // Get deployed contract addresses from environment variables
  const henTokenAddress = process.env.HEN_TOKEN_ADDRESS;
  const henStabilizerAddress = process.env.HEN_STABILIZER_ADDRESS;
  const henStakingAddress = process.env.HEN_STAKING_ADDRESS;
  const initialSupply =
    process.env.INITIAL_SUPPLY || "1000000000000000000000000";

  if (!henTokenAddress || !henStabilizerAddress || !henStakingAddress) {
    console.error("Missing contract addresses in environment variables!");
    console.log(
      "Please set HEN_TOKEN_ADDRESS, HEN_STABILIZER_ADDRESS, and HEN_STAKING_ADDRESS."
    );
    process.exit(1);
  }

  try {
    // Verify HenToken
    console.log(`Verifying HenToken at ${henTokenAddress}...`);
    await hre.run("verify:verify", {
      address: henTokenAddress,
      constructorArguments: [initialSupply],
    });
    console.log("HenToken verified successfully!");
  } catch (error) {
    console.error("Error verifying HenToken:", error.message);
  }

  try {
    // Verify HenStabilizer
    console.log(`Verifying HenStabilizer at ${henStabilizerAddress}...`);
    await hre.run("verify:verify", {
      address: henStabilizerAddress,
      constructorArguments: [henTokenAddress],
    });
    console.log("HenStabilizer verified successfully!");
  } catch (error) {
    console.error("Error verifying HenStabilizer:", error.message);
  }

  try {
    // Verify HenStaking
    console.log(`Verifying HenStaking at ${henStakingAddress}...`);
    await hre.run("verify:verify", {
      address: henStakingAddress,
      constructorArguments: [henTokenAddress],
    });
    console.log("HenStaking verified successfully!");
  } catch (error) {
    console.error("Error verifying HenStaking:", error.message);
  }

  console.log("Verification completed!");
}

// Execute the verification
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
