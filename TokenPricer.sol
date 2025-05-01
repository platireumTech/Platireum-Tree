// TokenPricer.sol
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface AggregatorV3Interface {
    function latestRoundData() external view returns (/* ... */);
}

contract TokenPricer {
    using SafeMath for uint256;

    AssetManager public assetManager; // Reference to AssetManager

    constructor(AssetManager _assetManager) {
        assetManager = _assetManager;
    }

    function getPriceFromOracle(address priceFeedAddress) internal view returns (uint256) { /* ... */ }

    function getTokenPrice() public view returns (uint256) {
        uint256 weightedPrice = 0;
        bytes32[] memory assetList = assetManager.assetList(); // Get asset list
        for (uint256 i = 0; i < assetList.length; i++) {
            bytes32 assetId = assetList[i];
            AssetManager.Asset memory asset = assetManager.assets(assetId); // Get asset details
            if (asset.isActive) {
                uint256 price = getPriceFromOracle(asset.priceFeedAddress);
                weightedPrice = weightedPrice.add(price.mul(asset.weight));
            }
        }
        return weightedPrice.div(100);
    }
}
