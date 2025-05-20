// Script to save deployed contract addresses to .env file
const fs = require("fs");
const path = require("path");
require("dotenv").config();

async function main() {
  console.log("Save deployed contract addresses to .env file");

  const henTokenAddress = process.argv[2];
  const henStabilizerAddress = process.argv[3];
  const henStakingAddress = process.argv[4];

  if (!henTokenAddress || !henStabilizerAddress || !henStakingAddress) {
    console.error("Missing contract addresses!");
    console.log(
      "Usage: node scripts/save-addresses.js <HenToken> <HenStabilizer> <HenStaking>"
    );
    process.exit(1);
  }

  // Read current .env file or create if not exists
  const envPath = path.join(__dirname, "../.env");
  let envContent = "";

  try {
    if (fs.existsSync(envPath)) {
      envContent = fs.readFileSync(envPath, "utf8");
    }
  } catch (error) {
    console.log("Creating new .env file");
  }

  // Replace or add contract addresses
  const envLines = envContent.split("\n");
  const newEnvLines = [];
  let hasTokenAddress = false;
  let hasStabilizerAddress = false;
  let hasStakingAddress = false;

  for (const line of envLines) {
    if (line.startsWith("HEN_TOKEN_ADDRESS=")) {
      newEnvLines.push(`HEN_TOKEN_ADDRESS=${henTokenAddress}`);
      hasTokenAddress = true;
    } else if (line.startsWith("HEN_STABILIZER_ADDRESS=")) {
      newEnvLines.push(`HEN_STABILIZER_ADDRESS=${henStabilizerAddress}`);
      hasStabilizerAddress = true;
    } else if (line.startsWith("HEN_STAKING_ADDRESS=")) {
      newEnvLines.push(`HEN_STAKING_ADDRESS=${henStakingAddress}`);
      hasStakingAddress = true;
    } else if (line.trim() !== "") {
      newEnvLines.push(line);
    }
  }

  // Add missing addresses
  if (!hasTokenAddress) {
    newEnvLines.push(`HEN_TOKEN_ADDRESS=${henTokenAddress}`);
  }
  if (!hasStabilizerAddress) {
    newEnvLines.push(`HEN_STABILIZER_ADDRESS=${henStabilizerAddress}`);
  }
  if (!hasStakingAddress) {
    newEnvLines.push(`HEN_STAKING_ADDRESS=${henStakingAddress}`);
  }

  // Write updated .env file
  fs.writeFileSync(envPath, newEnvLines.join("\n") + "\n");
  console.log("Contract addresses saved to .env file successfully!");
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
