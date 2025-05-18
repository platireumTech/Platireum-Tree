// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces.sol";

contract ValueStabilizer is Ownable {
    uint256 public constant TARGET_PRICE = 1e18;
    uint256 public constant MAX_ADJUSTMENT = 0.10e18; // 10% max single adjustment
    uint256 public constant DEVIATION_THRESHOLD = 0.01e18; // 1%
    
    address public immutable mainToken;
    address public immutable assetManager;
    address public immutable reserveToken;

    event SupplyAdjusted(int256 amount, uint256 assetValueMoved);

    constructor(address _mainToken, address _assetManager, address _reserveToken) {
        mainToken = _mainToken;
        assetManager = _assetManager;
        reserveToken = _reserveToken;
    }

    function adjustSupply(uint256 currentPrice) external {
        require(msg.sender == owner() || msg.sender == mainToken, "Unauthorized");
        
        uint256 deviation = _calculateDeviation(currentPrice);
        if (deviation < DEVIATION_THRESHOLD) return;

        uint256 supplyChange = _calculateSupplyChange(deviation);
        _executeSupplyAdjustment(supplyChange, currentPrice);
    }

    function _calculateDeviation(uint256 currentPrice) internal pure returns (uint256) {
        return currentPrice > TARGET_PRICE 
            ? ((currentPrice - TARGET_PRICE) * 1e18) / TARGET_PRICE
            : ((TARGET_PRICE - currentPrice) * 1e18) / TARGET_PRICE;
    }

    function _calculateSupplyChange(uint256 deviation) internal view returns (uint256) {
        uint256 tokenSupply = IERC20(mainToken).totalSupply();
        uint256 proposedChange = (tokenSupply * deviation) / 1e18;
        
        // Cap the adjustment
        uint256 maxChange = (tokenSupply * MAX_ADJUSTMENT) / 1e18;
        return proposedChange > maxChange ? maxChange : proposedChange;
    }

    function _executeSupplyAdjustment(uint256 supplyChange, uint256 currentPrice) internal {
        if (currentPrice > TARGET_PRICE) {
            _expandSupply(supplyChange);
        } else {
            _contractSupply(supplyChange);
        }
    }

    function _expandSupply(uint256 mintAmount) internal {
        require(
            IAssetManager(assetManager).checkLiquidity(mintAmount * TARGET_PRICE / 1e18),
            "Insufficient liquidity"
        );
        
        IMintable(mainToken).mint(address(this), mintAmount);
        uint256 reserveAmount = (mintAmount * TARGET_PRICE) / 1e18;
        IAssetManager(assetManager).buyAssetsProportionally(reserveAmount);
        
        emit SupplyAdjusted(int256(mintAmount), reserveAmount);
    }

    function _contractSupply(uint256 burnAmount) internal {
        IBurnable(mainToken).burn(burnAmount);
        uint256 reserveAmount = (burnAmount * TARGET_PRICE) / 1e18;
        IAssetManager(assetManager).sellAssetsProportionally(reserveAmount);
        
        emit SupplyAdjusted(-int256(burnAmount), reserveAmount);
    }
}
