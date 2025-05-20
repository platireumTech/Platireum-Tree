// Mainnet deployment script
const { execSync } = require("child_process");
require("dotenv").config();

async function main() {
  console.log("Starting Ethereum mainnet deployment...");

  // Check if environment variables are set
  if (!process.env.PRIVATE_KEY || !process.env.MAINNET_RPC_URL) {
    console.error("Missing required environment variables!");
    console.log(
      "Please set PRIVATE_KEY and MAINNET_RPC_URL in your .env file."
    );
    process.exit(1);
  }

  // Confirm deployment to mainnet
  const readline = require("readline").createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  readline.question(
    "WARNING: You are about to deploy to Ethereum mainnet. This will cost real ETH. Are you sure? (yes/no): ",
    (answer) => {
      readline.close();
      if (answer.toLowerCase() !== "yes") {
        console.log("Deployment cancelled.");
        process.exit(0);
      }

      deployToMainnet();
    }
  );
}

async function deployToMainnet() {
  // Deploy to Ethereum mainnet
  console.log("Deploying contracts to Ethereum mainnet...");
  try {
    execSync("npx hardhat run scripts/deploy.js --network mainnet", {
      stdio: "inherit",
    });
    console.log("Mainnet deployment completed successfully!");

    // Save deployed addresses to .env file
    console.log(
      "Please save the deployed contract addresses to your .env file for verification."
    );
    console.log("Example: HEN_TOKEN_ADDRESS=0x...");
  } catch (error) {
    console.error("Error during mainnet deployment:", error);
  }
}

// Execute the mainnet deployment
main().catch((error) => {
  console.error(error);
  process.exit(1);
});
