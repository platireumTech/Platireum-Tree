// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract AssetManager is Ownable {
    struct Asset {
        bytes32 id;
        string symbol;
        uint256 weight; // in basis points (10000 = 100%)
        address[] priceFeeds; // Array of Chainlink price feeds for redundancy
        bool isActive;
    }

    mapping(bytes32 => Asset) public assets;
    bytes32[] public activeAssetIds;
    uint256 public totalWeight;
    address[] public goldPriceFeeds; // Array of Chainlink price feeds for Gold/USD

    event AssetAdded(bytes32 indexed assetId, string symbol, uint256 weight, address[] priceFeeds);
    event AssetWeightUpdated(bytes32 indexed assetId, uint256 newWeight);
    event AssetPriceFeedUpdated(bytes32 indexed assetId, address[] newPriceFeeds);

    constructor(address[] memory _goldPriceFeeds) {
        goldPriceFeeds = _goldPriceFeeds;
    }

    function setGoldPriceFeeds(address[] memory _newPriceFeeds) external onlyOwner {
        goldPriceFeeds = _newPriceFeeds;
    }

    function addAsset(
        string memory symbol,
        uint256 weight,
        address[] memory priceFeeds
    ) external onlyOwner {
        bytes32 assetId = keccak256(abi.encodePacked(symbol));
        require(!assets[assetId].isActive, "Asset exists");
        require(priceFeeds.length > 0, "At least one price feed is required");

        assets[assetId] = Asset(assetId, symbol, weight, priceFeeds, true);
        activeAssetIds.push(assetId);
        totalWeight += weight;

        emit AssetAdded(assetId, symbol, weight, priceFeeds);
    }

    function updateAssetWeight(bytes32 assetId, uint256 newWeight) external onlyOwner {
        require(assets[assetId].isActive, "Asset not active");
        totalWeight = totalWeight - assets[assetId].weight + newWeight;
        assets[assetId].weight = newWeight;
        emit AssetWeightUpdated(assetId, newWeight);
    }

    function updateAssetPriceFeeds(bytes32 assetId, address[] memory newPriceFeeds) external onlyOwner {
        require(assets[assetId].isActive, "Asset not active");
        require(newPriceFeeds.length > 0, "At least one price feed is required");
        assets[assetId].priceFeeds = newPriceFeeds;
        emit AssetPriceFeedUpdated(assetId, newPriceFeeds);
    }

    function getAssetPriceUSD(bytes32 assetId) public view returns (uint256) {
        require(assets[assetId].isActive, "Asset not active");
        uint256 totalPrice = 0;
        for (uint i = 0; i < assets[assetId].priceFeeds.length; i++) {
            (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = AggregatorV3Interface(assets[assetId].priceFeeds[i]).latestRoundData();
            if (updatedAt > 0) {
                totalPrice += uint256(price);
            }
        }
        require(totalPrice > 0, "Could not fetch asset price");
        return totalPrice / assets[assetId].priceFeeds.length; // Average price
    }

    function getGoldPriceUSD() public view returns (uint256) {
        uint256 totalPrice = 0;
        uint256 validFeedCount = 0;
        for (uint i = 0; i < goldPriceFeeds.length; i++) {
            (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = AggregatorV3Interface(goldPriceFeeds[i]).latestRoundData();
            if (updatedAt > 0) {
                totalPrice += uint256(price);
                validFeedCount++;
            }
        }
        require(validFeedCount > 0, "Could not fetch gold price");
        return totalPrice / validFeedCount; // Average gold price
    }

    function calculateAssetValueInGold() public view returns (uint256 totalValueInGold) {
        uint256 goldPriceUSD = getGoldPriceUSD();
        require(goldPriceUSD > 0, "Invalid gold price");
        totalValueInGold = 0;
        for (uint i = 0; i < activeAssetIds.length; i++) {
            bytes32 assetId = activeAssetIds[i];
            uint256 assetPriceUSD = getAssetPriceUSD(assetId);
            // Assuming both prices have 8 decimals from Chainlink
            totalValueInGold += (assetPriceUSD * assets[assetId].weight) / goldPriceUSD;
        }
        // Scale totalValueInGold to match the base unit of our token (e.g., 18 decimals)
        totalValueInGold = (totalValueInGold * 10**10) / 100; // Adjusting for 8 decimals in price and 18 in token
    }
}
