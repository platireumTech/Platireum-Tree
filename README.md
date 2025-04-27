Platireum (TREE) - Asset-Backed Token Contract Documentation
Version: 1.1
Author: [ِMohammad, Ayman]
License: MIT

1. Contract Overview
The AssetBackedToken contract is an ERC-20 token backed by a basket of assets (e.g., commodities, stocks). Each token's value is derived from a weighted average of the underlying assets' prices, fetched via Chainlink oracles.

Key Features
✅ Asset-Backed Token (ABT): Each TREE token is backed by a diversified portfolio.
✅ Dynamic Weight Management: Assets can be added, updated, or removed while maintaining a total weight of 100.
✅ Real-Time Pricing: Uses Chainlink oracles for accurate price feeds.
✅ Gas Optimization: Efficient storage and computation for lower transaction costs.

2. Contract Structure
2.1. Imports & Dependencies
solidity
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";  
import "@openzeppelin/contracts/access/Ownable.sol";  
import "@openzeppelin/contracts/utils/math/SafeMath.sol";  
ERC20: Standard token implementation.

Ownable: Restricts critical functions to the contract owner.

SafeMath: Prevents integer overflows.

2.2. Chainlink Oracle Interface
solidity
interface AggregatorV3Interface {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}
Used to fetch real-time asset prices from Chainlink.

2.3. Asset Struct
solidity
struct Asset {
    string name;               // Asset identifier (e.g., "GOLD")
    uint256 weight;            // Weight in the basket (1-100)
    address priceFeedAddress;  // Chainlink oracle address
    bool isActive;             // Tracks if the asset is active
}
name: Human-readable identifier (e.g., "GOLD").

weight: Determines the asset's influence on the token price.

priceFeedAddress: Chainlink oracle contract address.

isActive: Ensures only active assets contribute to pricing.

2.4. Storage Variables
solidity
mapping(bytes32 => Asset) public assets;  // Tracks all assets by their hash ID  
bytes32[] public assetList;               // List of active asset IDs  
uint256 public totalActiveWeight = 0;     // Sum of all active asset weights  
uint256 public constant TOTAL_WEIGHT = 100;  // Must always sum to 100  
uint256 public constant MAX_SUPPLY = 1_000_000 * 10**18;  // Max token supply  
3. Core Functions
3.1. addAsset() - Add a New Asset
solidity
function addAsset(string memory name, uint256 weight, address priceFeedAddress) public onlyOwner
Checks:
✔ weight must be between 1 and 100.
✔ Total weight must not exceed TOTAL_WEIGHT (100).
✔ Asset must not already exist.

Effects:

Stores the asset in assets mapping.

Updates totalActiveWeight.

Emits AssetAdded event.

3.2. updateAsset() - Modify an Existing Asset
solidity
function updateAsset(bytes32 assetId, uint256 newWeight, address newPriceFeedAddress) public onlyOwner
Checks:
✔ Asset must exist and be active.
✔ New weight must be valid (1-100).
✔ Total weight must remain ≤100 after update.

Effects:

Updates weight and oracle address.

Adjusts totalActiveWeight.

Emits AssetUpdated.

3.3. removeAsset() - Remove an Asset
solidity
function removeAsset(bytes32 assetId) public onlyOwner
Checks:
✔ Asset must exist.
✔ At least one asset must remain.

Effects:

Deactivates the asset.

Removes it from assetList (gas-efficient swap-and-pop).

Updates totalActiveWeight.

Emits AssetRemoved.

3.4. getTokenPrice() - Calculate Token Value
solidity
function getTokenPrice() public view returns (uint256)
Logic:

Fetches latest prices from all active assets via Chainlink.

Computes a weighted average:

(Price₁ × Weight₁ + Price₂ × Weight₂ + ...) / 100
4. Events
Event	Description
AssetAdded	Emitted when a new asset is added.
AssetUpdated	Emitted when an asset's weight or oracle is updated.
AssetRemoved	Emitted when an asset is deactivated.
5. Gas Optimization Techniques
5.1. Efficient Weight Tracking
Uses totalActiveWeight (stored) instead of recalculating weights on every call.

5.2. Optimized Array Removal
Uses swap-and-pop to remove elements from assetList in O(1) time.

6. Deployment & Initialization
The constructor initializes the token with:

Name: "Platireum"

Symbol: "TREE"

Initial Assets:

GOLD (40%)

SILVER (20%)

APPLE (20%)

ALPHABET (20%)

7. Security Considerations
OnlyOwner: Critical functions are restricted.

Input Validation: Ensures weights and prices are valid.

SafeMath: Prevents overflows.

8. Future Improvements
Rebalancing Mechanism: Automatically adjust weights periodically.

Multi-Oracle Support: Fallback price feeds for redundancy.

📌 Attached Files:

AssetBackedToken.sol (Main Contract)

README.md (This Documentation)

🔗 References:

OpenZeppelin Docs

Chainlink Price Feeds

