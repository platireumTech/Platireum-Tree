// * Important Notice: Terms of Use for Platireum Currency: By receiving this Platireum currency, you irrevocably acknowledge and solemnly pledge your full adherence to the subsequent terms and conditions:
// * 1- Platireum must not be used for fraud or deception.
// * 2- Platireum must not be used for lending or borrowing with interest (usury).
// * 3- Platireum must not be used to buy or sell intoxicants, narcotics, or anything that impairs judgment.
// * 4- Platireum must not be used for criminal activities and money laundering.
// * 5- Platireum must not be used for gambling.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ValueStabilizer.sol";
import "./AssetManager.sol";
import "./SupplyController.sol";

contract Tree is ERC20, Ownable {
    ValueStabilizer public stabilizer;
    AssetManager public assetManager;
    SupplyController public supplyController;

    uint256 public lastPriceCheck;
    uint256 public priceCheckInterval = 1 hours;

    constructor(address[] memory _goldPriceFeeds) ERC20("Platireum", "TREE") {
        assetManager = new AssetManager(_goldPriceFeeds);
        supplyController = new SupplyController(address(this));
        stabilizer = new ValueStabilizer(address(this), address(assetManager), address(supplyController));

        // Initial mint to the owner
        _mint(msg.sender, 100_000 * 10**18);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function getAssetValueInGold() public view returns (uint256) {
        return IAssetManager(assetManager).calculateAssetValueInGold();
    }

    function getCurrentGoldPriceUSD() public view returns (uint256) {
        return IAssetManager(assetManager).getGoldPriceUSD();
    }

    function triggerSupplyAdjustment() external onlyOwner {
        IValueStabilizer(stabilizer).adjustSupplyBasedOnAssetValue();
    }

    function setPriceCheckInterval(uint256 _interval) external onlyOwner {
        priceCheckInterval = _interval;
    }

    function _checkPriceAndAdjust() internal {
        if (block.timestamp >= lastPriceCheck + priceCheckInterval) {
            IValueStabilizer(stabilizer).adjustSupplyBasedOnAssetValue();
            lastPriceCheck = block.timestamp;
        }
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _checkPriceAndAdjust();
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _checkPriceAndAdjust();
        return super.transferFrom(from, to, amount);
    }
}

interface IValueStabilizer {
    function adjustSupplyBasedOnAssetValue() external;
}
