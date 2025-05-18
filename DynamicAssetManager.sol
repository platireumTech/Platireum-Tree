// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract DynamicAssetManager is Ownable {
    struct Asset {
        bytes32 id;
        string name;
        uint256 weight; // Basis points (10000 = 100%)
        address priceFeed;
        bool isActive;
    }
    
    mapping(bytes32 => Asset) public assets;
    bytes32[] public activeAssetIds;
    uint256 public totalWeight;
    
    event AssetAdded(bytes32 indexed assetId, string name, uint256 weight);
    event AssetUpdated(bytes32 indexed assetId, uint256 newWeight);
    event AssetRemoved(bytes32 indexed assetId);
    event AssetsRebalanced();

    // Adds a new asset to the basket
    function addAsset(string memory name, uint256 weight, address priceFeed) external onlyOwner {
        require(weight > 0, "Weight must be positive");
        bytes32 assetId = keccak256(abi.encodePacked(name));
        
        require(!assets[assetId].isActive, "Asset already exists");
        assets[assetId] = Asset(assetId, name, weight, priceFeed, true);
        activeAssetIds.push(assetId);
        totalWeight += weight;
        
        emit AssetAdded(assetId, name, weight);
    }

    // Updates an existing asset's weight
    function updateAsset(bytes32 assetId, uint256 newWeight) external onlyOwner {
        require(assets[assetId].isActive, "Asset not found");
        totalWeight = totalWeight - assets[assetId].weight + newWeight;
        assets[assetId].weight = newWeight;
        
        emit AssetUpdated(assetId, newWeight);
    }

    // Rebalances multiple assets at once
    function rebalanceAssets(
        bytes32[] calldata assetIds, 
        uint256[] calldata newWeights
    ) external onlyOwner {
        require(assetIds.length == newWeights.length, "Array length mismatch");
        
        uint256 newTotalWeight;
        for (uint i = 0; i < assetIds.length; i++) {
            require(assets[assetIds[i]].isActive, "Invalid asset");
            assets[assetIds[i]].weight = newWeights[i];
            newTotalWeight += newWeights[i];
        }
        
        totalWeight = newTotalWeight;
        emit AssetsRebalanced();
    }

    // Gets all active assets
    function getActiveAssets() external view returns (Asset[] memory) {
        Asset[] memory result = new Asset[](activeAssetIds.length);
        for (uint i = 0; i < activeAssetIds.length; i++) {
            result[i] = assets[activeAssetIds[i]];
        }
        return result;
    }
}
