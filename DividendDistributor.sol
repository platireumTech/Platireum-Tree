// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces.sol";

contract DividendDistributor is Ownable {
    address public immutable mainToken;
    IERC20 public immutable rewardToken; // USDC or other dividend-bearing asset
    
    struct Share {
        uint256 amount;
        uint256 totalExcluded; // Excluded dividends (for fairness)
        uint256 totalRealised;
        uint256 lastClaimTime;
    }

    mapping(address => Share) public shares;
    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public constant DISTRIBUTION_PERIOD = 7 days;
    
    event DividendDeposited(uint256 amount);
    event DividendDistributed(address indexed holder, uint256 amount);
    event AutoDistribution(address indexed holder, uint256 amount);

    constructor(address _mainToken, address _rewardToken) {
        mainToken = _mainToken;
        rewardToken = IERC20(_rewardToken);
    }

    // Called from main token during transfers
    function setShare(address shareholder, uint256 amount) external onlyOwner {
        if (shares[shareholder].amount > 0) {
            _distributeDividend(shareholder, false);
        }

        totalShares = totalShares - shares[shareholder].amount + amount;
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = _getCumulativeDividends(amount);
    }

    // Deposit dividends from asset yields (called by AssetManager)
    function depositDividends(uint256 amount) external onlyOwner {
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        totalDividends += amount;
        emit DividendDeposited(amount);
    }

    // Manual claim by users
    function claimDividend() external {
        _distributeDividend(msg.sender, false);
    }

    // Automatic distribution after 7 days
    function processAutoDistribution(address shareholder) external {
        require(
            block.timestamp - shares[shareholder].lastClaimTime >= DISTRIBUTION_PERIOD,
            "Too early"
        );
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
        shares[shareholder].lastClaimTime = block.timestamp;

        if (isAuto) {
            emit AutoDistribution(shareholder, amount);
        } else {
            emit DividendDistributed(shareholder, amount);
        }
    }

    function _getUnpaidEarnings(address shareholder) internal view returns (uint256) {
        if (shares[shareholder].amount == 0) return 0;
        
        uint256 shareholderTotalDividends = _getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;
        
        return shareholderTotalDividends > shareholderTotalExcluded 
            ? shareholderTotalDividends - shareholderTotalExcluded 
            : 0;
    }

    function _getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return totalDividends * share / totalShares;
    }
}