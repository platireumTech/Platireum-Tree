// Local deployment script
const { ethers } = require("hardhat");
const { execSync } = require("child_process");

async function main() {
  console.log("Starting local deployment...");

  // Use Hardhat's built-in node
  console.log("Starting Hardhat node in the background...");
  const hardhatNode = require("child_process").spawn(
    "npx",
    ["hardhat", "node"],
    {
      detached: true,
      stdio: "ignore",
    }
  );
  hardhatNode.unref();

  // Wait for node to start
  console.log("Waiting for Hardhat node to start...");
  await new Promise((resolve) => setTimeout(resolve, 5000));

  // Deploy to local network
  console.log("Deploying contracts to local network...");
  try {
    execSync("npx hardhat run scripts/deploy.js --network localhost", {
      stdio: "inherit",
    });
    console.log("Local deployment completed successfully!");
  } catch (error) {
    console.error("Error during local deployment:", error);
  }
}

// Execute the local deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
