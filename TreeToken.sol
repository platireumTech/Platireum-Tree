// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./DynamicAssetManager.sol";
import "./ValueStabilizer.sol";
import "./DividendDistributor.sol";

contract Tree is ERC20, Ownable {
    DynamicAssetManager public assetManager;
    ValueStabilizer public valueStabilizer;
    DividendDistributor public dividendDistributor;
    
    uint256 public constant MAX_SUPPLY = 1e9 * 1e18; // 1 billion
    uint256 public constant DIVIDEND_FEE = 300; // 3%
    uint256 public constant STABILIZATION_FEE = 200; // 2%
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    mapping(address => bool) public isFeeExempt;
    
    event AssetAdded(string name, uint256 weight);
    event FeesDistributed(uint256 dividendAmount, uint256 stabilizationAmount);

    constructor() ERC20("Platireum", "TREE") {
        assetManager = new DynamicAssetManager();
        dividendDistributor = new DividendDistributor(address(this), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        valueStabilizer = new ValueStabilizer(address(this), address(assetManager), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        
        // Initial mint
        _mint(msg.sender, MAX_SUPPLY / 10);
        
        // Fee exemptions
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        isFeeExempt[address(dividendDistributor)] = true;
        isFeeExempt[address(valueStabilizer)] = true;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transferWithFees(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transferWithFees(sender, recipient, amount);
        _approve(sender, _msgSender(), allowance(sender, _msgSender()) - amount);
        return true;
    }

    function addAsset(string calldata name, uint256 weight, address priceFeed) external onlyOwner {
        assetManager.addAsset(name, weight, priceFeed);
        valueStabilizer.updateReserveRequirements();
        emit AssetAdded(name, weight);
    }

    // ================= INTERNAL FUNCTIONS ================= //
    
    function _transferWithFees(address sender, address recipient, uint256 amount) internal {
        if (isFeeExempt[sender] || isFeeExempt[recipient]) {
            _transfer(sender, recipient, amount);
            return;
        }
        
        uint256 dividendAmount = amount * DIVIDEND_FEE / FEE_DENOMINATOR;
        uint256 stabilizationAmount = amount * STABILIZATION_FEE / FEE_DENOMINATOR;
        uint256 transferAmount = amount - dividendAmount - stabilizationAmount;
        
        _transfer(sender, recipient, transferAmount);
        
        if (dividendAmount > 0) {
            _transfer(sender, address(dividendDistributor), dividendAmount);
            dividendDistributor.setShare(sender, balanceOf(sender));
            dividendDistributor.setShare(recipient, balanceOf(recipient));
        }
        
        if (stabilizationAmount > 0) {
            _transfer(sender, address(valueStabilizer), stabilizationAmount);
        }
        
        emit FeesDistributed(dividendAmount, stabilizationAmount);
    }
}
