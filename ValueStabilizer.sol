// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ValueStabilizer is Ownable {
    uint256 public constant MAX_ADJUSTMENT = 0.10e18; // 10% max single adjustment
    uint256 public constant DEVIATION_THRESHOLD = 0.01e18; // 1%

    address public immutable mainToken;
    address public immutable assetManager;
    address public immutable supplyController;

    event SupplyAdjusted(int256 amount);

    constructor(address _mainToken, address _assetManager, address _supplyController) {
        mainToken = _mainToken;
        assetManager = _assetManager;
        supplyController = _supplyController;
    }

    function adjustSupplyBasedOnAssetValue() external {
        require(msg.sender == supplyController, "Only SupplyController can call this");

        uint256 currentAssetValueInGold = IAssetManager(assetManager).calculateAssetValueInGold();
        uint256 totalSupply = IERC20(mainToken).totalSupply();

        // Calculate the target price of the token in terms of our base unit (e.g., 1 token = X base units of gold value)
        uint256 targetPricePerToken = totalSupply > 0 ? currentAssetValueInGold / totalSupply : 0;
        uint256 currentMarketPricePerToken = ISupplyController(supplyController).getCurrentMarketPrice();

        if (targetPricePerToken > 0 && currentMarketPricePerToken > 0) {
            uint256 deviation = _calculateDeviation(currentMarketPricePerToken, targetPricePerToken);

            if (deviation > DEVIATION_THRESHOLD) {
                uint256 supplyChange = _calculateSupplyChange(deviation, totalSupply);
                if (currentMarketPricePerToken > targetPricePerToken) {
                    // Market price is too high, potentially issue more tokens
                    ISupplyController(supplyController).mint(supplyChange);
                    emit SupplyAdjusted(int256(supplyChange));
                } else {
                    // Market price is too low, potentially burn tokens
                    ISupplyController(supplyController).burn(supplyChange);
                    emit SupplyAdjusted(-int256(supplyChange));
                }
            }
        }
    }

    function _calculateDeviation(uint256 currentPrice, uint256 targetPrice) internal pure returns (uint256) {
        return currentPrice > targetPrice
            ? ((currentPrice - targetPrice) * 1e18) / targetPrice
            : ((targetPrice - currentPrice) * 1e18) / targetPrice;
    }

    function _calculateSupplyChange(uint256 deviation, uint256 totalSupply) internal view returns (uint256) {
        uint256 proposedChange = (totalSupply * deviation) / 1e18;
        uint256 maxChange = (totalSupply * MAX_ADJUSTMENT) / 1e18;
        return proposedChange > maxChange ? maxChange : proposedChange;
    }
}

interface IAssetManager {
    function calculateAssetValueInGold() external view returns (uint256);
}

interface ISupplyController {
    function getCurrentMarketPrice() external view returns (uint256);
    function mint(uint256 amount) external;
    function burn(uint256 amount) external;
}
