// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DividendDistributor is Ownable {
    address public immutable mainToken;
    IERC20 public immutable rewardToken;
    
    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
        uint256 lastClaim;
    }
    
    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public constant DISTRIBUTION_PERIOD = 7 days;
    
    mapping(address => Share) public shares;
    
    event DividendDeposited(uint256 amount);
    event DividendClaimed(address indexed holder, uint256 amount);
    event AutoDistributed(address indexed holder, uint256 amount);

    constructor(address _mainToken, address _rewardToken) {
        mainToken = _mainToken;
        rewardToken = IERC20(_rewardToken);
    }

    // Updates shareholder balance (called from main token)
    function setShare(address shareholder, uint256 amount) external onlyOwner {
        if (shares[shareholder].amount > 0) {
            _distributeDividend(shareholder, false);
        }
        
        totalShares = totalShares - shares[shareholder].amount + amount;
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = _getCumulativeDividends(amount);
    }

    // Deposits dividends into the contract
    function depositDividends(uint256 amount) external {
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        totalDividends += amount;
        emit DividendDeposited(amount);
    }

    // Claims dividends manually
    function claimDividend() external {
        _distributeDividend(msg.sender, false);
    }

    // Processes auto-distribution if eligible
    function processAutoDistribution(address shareholder) external {
        require(_isEligibleForAutoDistribution(shareholder), "Not eligible");
        _distributeDividend(shareholder, true);
    }

    // ================= INTERNAL FUNCTIONS ================= //
    
    function _distributeDividend(address shareholder, bool isAuto) internal {
        uint256 amount = _getUnpaidEarnings(shareholder);
        if (amount == 0) return;
        
        totalDistributed += amount;
        rewardToken.transfer(shareholder, amount);
        
        shares[shareholder].totalRealised += amount;
        shares[shareholder].totalExcluded = _getCumulativeDividends(shares[shareholder].amount);
        shares[shareholder].lastClaim = block.timestamp;
        
        if (isAuto) {
            emit AutoDistributed(shareholder, amount);
        } else {
            emit DividendClaimed(shareholder, amount);
        }
    }
    
    function _isEligibleForAutoDistribution(address shareholder) internal view returns (bool) {
        return shares[shareholder].amount > 0 &&
               block.timestamp - shares[shareholder].lastClaim >= DISTRIBUTION_PERIOD &&
               _getUnpaidEarnings(shareholder) > 0;
    }
    
    function _getUnpaidEarnings(address shareholder) internal view returns (uint256) {
        if (shares[shareholder].amount == 0) return 0;
        
        uint256 totalEarned = _getCumulativeDividends(shares[shareholder].amount);
        uint256 alreadyExcluded = shares[shareholder].totalExcluded;
        
        return totalEarned > alreadyExcluded ? totalEarned - alreadyExcluded : 0;
    }
    
    function _getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return totalDividends * share / totalShares;
    }
}
