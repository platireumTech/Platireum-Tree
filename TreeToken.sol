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
import "./Interfaces.sol";

contract Tree is ERC20, Ownable, IMintable, IBurnable {
    ValueStabilizer public stabilizer;
    AssetManager public assetManager;

    uint256 public lastPriceCheck;
    uint256 public priceCheckInterval = 1 hours;
    uint256 public constant STABILIZATION_FEE = 200; // 2%
    uint256 public constant FEE_DENOMINATOR = 10000;

    mapping(address => bool) public isFeeExempt;

    event FeesProcessed(uint256 stabilizationAmount);

    constructor() ERC20("Platireum", "TREE") {
        // Deploy supporting contracts
        assetManager = new AssetManager(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        stabilizer = new ValueStabilizer(address(this), address(assetManager), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        // Initial mint
        _mint(msg.sender, 100_000 * 10**18);

        // Configure fee exemptions
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        isFeeExempt[address(stabilizer)] = true;
        isFeeExempt[address(assetManager)] = true;
    }

    function mint(address to, uint256 amount) external override onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _processTransaction(_msgSender(), to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _processTransaction(from, to, amount);
        _approve(from, _msgSender(), allowance(from, _msgSender()) - amount);
        return true;
    }

    function _processTransaction(address from, address to, uint256 amount) internal {
        if (isFeeExempt[from] || isFeeExempt[to]) {
            _transfer(from, to, amount);
            return;
        }

        uint256 stabilizationAmount = amount * STABILIZATION_FEE / FEE_DENOMINATOR;
        uint256 transferAmount = amount - stabilizationAmount;

        _transfer(from, to, transferAmount);

        if (stabilizationAmount > 0) {
            _transfer(from, address(stabilizer), stabilizationAmount);
        }

        emit FeesProcessed(stabilizationAmount);
        _checkPriceAndAdjust();
    }

    function _checkPriceAndAdjust() internal {
        if (block.timestamp >= lastPriceCheck + priceCheckInterval) {
            uint256 currentPrice = _getCurrentPrice();
            stabilizer.adjustSupply(currentPrice);
            lastPriceCheck = block.timestamp;
        }
    }

    function _getCurrentPrice() internal view returns (uint256) {
        // In production: Get weighted average from asset manager
        return 1e18; // Placeholder for 1:1 peg
    }
}
