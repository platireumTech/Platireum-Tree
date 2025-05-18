// * Important Notice: Terms of Use for Platireum Currency: By receiving this Platireum currency, you irrevocably acknowledge and solemnly pledge your full adherence to the subsequent terms and conditions:
// *  1- Platireum must not be used for fraud or deception.
// *  2- Platireum must not be used for lending or borrowing with interest (usury).
// *  3- Platireum must not be used to buy or sell intoxicants, narcotics, or anything that impairs judgment.
// *  4- Platireum must not be used for criminal activities and money laundering.
// *  5- Platireum must not be used for gambling.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ValueStabilizer.sol";
import "./AssetManager.sol";
import "./DividendDistributor.sol";

contract Tree is ERC20, Ownable, IMintable, IBurnable {
    ValueStabilizer public stabilizer;
    AssetManager public assetManager;
    DividendDistributor public dividendDistributor;
    
    uint256 public lastPriceCheck;
    uint256 public priceCheckInterval = 1 hours;
    uint256 public constant DIVIDEND_FEE = 300; // 3%
    uint256 public constant STABILIZATION_FEE = 200; // 2%
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    mapping(address => bool) public isFeeExempt;

    event FeesProcessed(uint256 dividendAmount, uint256 stabilizationAmount);

    constructor() ERC20("Platireum", "TREE") {
        // Deploy supporting contracts
        dividendDistributor = new DividendDistributor(address(this), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        assetManager = new AssetManager(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, address(dividendDistributor));
        stabilizer = new ValueStabilizer(address(this), address(assetManager), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        // Initial mint
        _mint(msg.sender, 100_000 * 10**18);
        
        // Configure fee exemptions
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        isFeeExempt[address(dividendDistributor)] = true;
        isFeeExempt[address(stabilizer)] = true;
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

        uint256 dividendAmount = amount * DIVIDEND_FEE / FEE_DENOMINATOR;
        uint256 stabilizationAmount = amount * STABILIZATION_FEE / FEE_DENOMINATOR;
        uint256 transferAmount = amount - dividendAmount - stabilizationAmount;

        _transfer(from, to, transferAmount);
        
        if (dividendAmount > 0) {
            _transfer(from, address(dividendDistributor), dividendAmount);
            dividendDistributor.setShare(from, balanceOf(from));
            dividendDistributor.setShare(to, balanceOf(to));
        }
        
        if (stabilizationAmount > 0) {
            _transfer(from, address(stabilizer), stabilizationAmount);
        }

        emit FeesProcessed(dividendAmount, stabilizationAmount);
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
