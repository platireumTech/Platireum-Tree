// Testnet (Sepolia) deployment script
const { execSync } = require("child_process");
require("dotenv").config();

async function main() {
  console.log("Starting Sepolia testnet deployment...");

  // Check if environment variables are set
  if (!process.env.PRIVATE_KEY || !process.env.SEPOLIA_RPC_URL) {
    console.error("Missing required environment variables!");
    console.log(
      "Please set PRIVATE_KEY and SEPOLIA_RPC_URL in your .env file."
    );
    process.exit(1);
  }

  // Deploy to Sepolia testnet
  console.log("Deploying contracts to Sepolia testnet...");
  try {
    execSync("npx hardhat run scripts/deploy.js --network sepolia", {
      stdio: "inherit",
    });
    console.log("Sepolia deployment completed successfully!");

    // Save deployed addresses to .env file
    console.log(
      "Please save the deployed contract addresses to your .env file for verification."
    );
    console.log("Example: HEN_TOKEN_ADDRESS=0x...");
  } catch (error) {
    console.error("Error during Sepolia deployment:", error);
  }
}

// Execute the Sepolia deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
