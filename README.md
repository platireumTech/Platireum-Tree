# Platireum-Tree

A Solidity smart contract that creates an asset-backed token compliant with the ERC-20 standard, where the token's price is determined based on the value of a basket of underlying assets (such as gold, silver, stocks...) through a Chainlink oracle.

Importing Standard Contracts:

ERC20 from OpenZeppelin: Provides the basic functionalities for creating an ERC-20 token (like transfers and total supply).
Ownable from OpenZeppelin: Allows restricting certain important functions (like adding and removing assets) to the contract owner only.
SafeMath from OpenZeppelin: Provides safe arithmetic operations to prevent overflow.
AggregatorV3Interface Interface:

A definition for the Chainlink Price Feed contract interface. It allows the smart contract to interact with oracle contracts to fetch the latest asset prices.
Asset Struct:

Represents a single asset backing the token. It includes information such as:
name: The name of the asset (string).
weight: The asset's weight in the asset basket (the sum of all active weights must be 100).
priceFeedAddress: The address of the oracle contract providing the price for this asset.
isActive: The status of the asset (active or inactive).
Asset Management:

assets: A mapping that links a unique asset identifier (bytes32) to its corresponding Asset struct. The identifier is generated using keccak256 on the asset name.
assetList: A dynamic array containing the identifiers (bytes32) of all added assets.
TOTAL_WEIGHT: A constant defining that the sum of the weights of all active assets must equal 100.
MAX_SUPPLY: A constant defining the maximum total supply of the token.
Events:

AssetAdded: Emitted when a new asset is added.
AssetUpdated: Emitted when the information of an existing asset is updated.
AssetRemoved: Emitted when an asset is removed.
constructor Function:

Initializes the contract with the token name ("Platireum") and symbol ("TREE").
Adds four initial assets (Gold, Silver, Apple Stock, Alphabet Stock) with their respective weights and oracle contract addresses (actual addresses are obscured by 0x...).
Asset Management Functions (require owner privileges - onlyOwner):

addAsset: To add a new asset to the asset basket. Requires a unique name, a weight (between 1 and 100), and the oracle contract address. The total weight of all active assets must not exceed 100.
updateAsset: To update the weight or oracle contract address of an existing asset.
removeAsset: To remove an asset from the asset basket. At least one asset must remain active.
Price Retrieval Functions:

getPriceFromOracle: An internal function that calls the specified oracle contract to fetch the latest price of an asset.
getTokenPrice: A public view function that calculates the current value of the token. It iterates through the list of active assets, fetches their prices from the oracles, multiplies each price by the asset's weight, and sums these weighted prices. Finally, it divides the sum by 100 to get the weighted average price.
getTotalWeight Function:

A public view function that calculates the sum of the weights of all currently active assets.
In summary:

This smart contract creates a unique digital token ("TREE") whose value is derived from a diverse portfolio of traditional and digital assets. The influence of each asset on the token's value is determined by its assigned weight. The prices of these assets are reliably sourced from Chainlink Oracle contracts, ensuring that the token's value reflects the market value of the underlying assets. The contract owner has the authority to add, update, and remove assets from this basket, providing flexibility in managing the token's backing.
