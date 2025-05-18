// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./Interfaces.sol";

contract AssetManager is Ownable {
    struct Asset {
        bytes32 id;
        string symbol;
        uint256 weight; // in basis points (10000 = 100%)
        address priceFeed;
        address tokenAddress;
        bool isActive;
    }

    mapping(bytes32 => Asset) public assets;
    bytes32[] public activeAssetIds;
    uint256 public totalWeight;
    address public immutable reserveToken;
    address public dividendDistributor;

    event AssetAdded(bytes32 indexed assetId, string symbol, uint256 weight);
    event AssetTraded(bytes32 indexed assetId, bool isBuy, uint256 amount);
    event YieldCollected(uint256 amount);

    constructor(address _reserveToken, address _dividendDistributor) {
        reserveToken = _reserveToken;
        dividendDistributor = _dividendDistributor;
    }

    function setDividendDistributor(address _distributor) external onlyOwner {
        dividendDistributor = _distributor;
    }

    function addAsset(
        string memory symbol,
        uint256 weight,
        address priceFeed,
        address tokenAddress
    ) external onlyOwner {
        bytes32 assetId = keccak256(abi.encodePacked(symbol));
        require(!assets[assetId].isActive, "Asset exists");
        
        assets[assetId] = Asset(assetId, symbol, weight, priceFeed, tokenAddress, true);
        activeAssetIds.push(assetId);
        totalWeight += weight;
        
        emit AssetAdded(assetId, symbol, weight);
    }

    function buyAssetsProportionally(uint256 reserveAmount) external onlyOwner {
        require(reserveAmount <= IERC20(reserveToken).balanceOf(address(this)), "Insufficient reserves");
        
        for (uint i = 0; i < activeAssetIds.length; i++) {
            bytes32 assetId = activeAssetIds[i];
            uint256 allocation = reserveAmount * assets[assetId].weight / totalWeight;
            
            _swap(reserveToken, assets[assetId].tokenAddress, allocation);
            emit AssetTraded(assetId, true, allocation);
        }
    }

    function sellAssetsProportionally(uint256 reserveAmount) external onlyOwner {
        for (uint i = 0; i < activeAssetIds.length; i++) {
            bytes32 assetId = activeAssetIds[i];
            uint256 allocation = reserveAmount * assets[assetId].weight / totalWeight;
            
            _swap(assets[assetId].tokenAddress, reserveToken, allocation);
            emit AssetTraded(assetId, false, allocation);
        }
    }

    function collectYield() external onlyOwner {
        uint256 totalYield;
        
        for (uint i = 0; i < activeAssetIds.length; i++) {
            bytes32 assetId = activeAssetIds[i];
            if (assets[assetId].tokenAddress == reserveToken) continue;
            
            uint256 yield = _collectAssetYield(assets[assetId].tokenAddress);
            totalYield += yield;
        }
        
        IERC20(reserveToken).approve(dividendDistributor, totalYield);
        IDividendDistributor(dividendDistributor).depositDividends(totalYield);
        
        emit YieldCollected(totalYield);
    }

    // Internal functions
    function _swap(address from, address to, uint256 amount) private {
        // Actual DEX implementation would go here
        IERC20(from).transfer(msg.sender, amount); // Simulate swap
    }

    function _collectAssetYield(address assetToken) private returns (uint256) {
        // Implementation varies by asset type
        // For stocks: dividend collection logic
        // For commodities: lending yield
        return IERC20(assetToken).balanceOf(address(this)) * 5 / 100; // Simulate 5% yield
    }
}