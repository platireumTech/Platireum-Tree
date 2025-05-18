// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ValueStabilizer.sol";
import "./AssetManager.sol";

contract TreeToken is ERC20, Ownable, IMintable, IBurnable {
    ValueStabilizer public stabilizer;
    AssetManager public assetManager;
    
    uint256 public lastPriceCheck;
    uint256 public priceCheckInterval = 1 hours;
    uint256 public initialSupply;

    constructor() ERC20("Platireum", "TREE") {
        initialSupply = 100_000 * 1e18; // Initial supply
        _mint(msg.sender, initialSupply);
        
        assetManager = new AssetManager(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        stabilizer = new ValueStabilizer(address(this), address(assetManager), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        
        // Initialize asset basket
        assetManager.addAsset("GOLD", 4000, 0x...goldFeed, 0x...goldToken);
        assetManager.addAsset("SILVER", 2000, 0x...silverFeed, 0x...silverToken);
        assetManager.addAsset("STOCKS", 4000, 0x...stocksFeed, 0x...stocksToken);
    }

    function mint(address to, uint256 amount) external override onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _checkPriceAndAdjust();
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _checkPriceAndAdjust();
        return super.transferFrom(from, to, amount);
    }

    function _checkPriceAndAdjust() internal {
        if (block.timestamp >= lastPriceCheck + priceCheckInterval) {
            uint256 currentPrice = _getCurrentPrice();
            stabilizer.adjustSupply(currentPrice);
            lastPriceCheck = block.timestamp;
        }
    }

    function _getCurrentPrice() internal view returns (uint256) {
        // In production: Get weighted average from all asset prices
        return 1e18; // Placeholder for 1:1 peg
    }
}
