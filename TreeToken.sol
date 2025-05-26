// * Important Notice: Terms of Use for Platireum Currency: By receiving this Platireum currency, you irrevocably acknowledge and solemnly pledge your full adherence to the subsequent terms and conditions:
// * 1- Platireum must not be used for fraud or deception.
// * 2- Platireum must not be used for lending or borrowing with interest (usury).
// * 3- Platireum must not be used to buy or sell intoxicants, narcotics, or anything that impairs judgment.
// * 4- Platireum must not be used for criminal activities and money laundering.
// * 5- Platireum must not be used for gambling.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// External interfaces
interface IPriceOracle {
    function getLatestPrice(bytes32 _assetId) external view returns (int256 price, uint256 timestamp);
    function isPriceFeedActive(bytes32 _assetId) external view returns (bool);
}

interface IMintBurnController {
    function canMint(address _to, uint256 _amount) external view returns (bool);
    function canBurn(address _from, uint256 _amount) external view returns (bool);
}

interface IRebalanceController {
    function shouldRebalance(uint256 currentTimestamp, uint256 lastRebalance) external view returns (bool);
    function getNextRebalanceTime(uint256 lastRebalance) external view returns (uint256);
}

interface IAssetManager {
    function canModifyAsset(string memory _symbol) external view returns (bool);
    function validateAssetWeight(string memory _symbol, uint256 _newWeight) external view returns (bool);
}

contract Tree is ERC20, Ownable, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.StringSet;
    using SafeMath for uint256;

    // --- State Variables ---
    struct Asset {
        string symbol;
        address tokenAddress;
        uint256 quantity;
        uint256 weightNumerator;
        bool isPreciousMetal;
        bytes32 oracleFeedId;
        uint256 lastPriceUpdate;
        uint256 lastKnownPrice;
    }

    // Structure to track historical changes of assets
    struct AssetChange {
        string symbol;
        address tokenAddress;
        uint256 quantity;
        uint256 weightNumerator;
        bool isPreciousMetal;
        bytes32 oracleFeedId;
        uint256 timestamp;
    }

    EnumerableSet.StringSet private assetSymbolsSet;
    mapping(string => Asset) public assets;

    // History tracking
    AssetChange[] public assetHistory;

    string public constant GOLD_SYMBOL = "XAU";
    address public goldOracleAddress;
    uint256 public constant WEIGHT_DENOMINATOR = 10000;
    uint256 public constant MIN_PRECIOUS_METAL_WEIGHT = 5000;

    // External contract links
    address public priceOracleLink;
    address public mintBurnLink;
    address public rebalanceLink;
    address public assetManagementLink;
    address public pauseUnpauseLink;
    address public withdrawFundsLink;

    // Rebalancing parameters
    uint256 public lastRebalanceTimestamp;
    uint256 public rebalanceInterval = 24 hours;
    uint256 public rebalanceWindow = 1 hours;

    // Max number of history entries allowed (optional)
    uint256 public maxHistoryEntries = 1000;

    // --- Events ---
    event AssetUpdated(
        string indexed symbol,
        address indexed tokenAddress,
        uint256 quantity,
        uint256 weightNumerator,
        bool isPreciousMetal
    );
    event AssetRemoved(string indexed symbol);
    event RebalancePerformed(uint256 timestamp);
    event GoldCompensated(uint256 percentageAdded);
    event EmergencyRebalanceExecuted(address indexed executor);
    event AssetChanged(string indexed symbol, uint256 timestamp);

    // --- Modifiers ---
    modifier onlyAuthorized(address _link) {
        require(msg.sender == owner() || (msg.sender == _link && _link != address(0)), "Unauthorized");
        _;
    }

    modifier validAsset(string memory _symbol) {
        require(assets[_symbol].weightNumerator > 0, "Asset does not exist");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        address _goldOracleAddress
    ) ERC20(name, symbol) Ownable(msg.sender) {
        goldOracleAddress = _goldOracleAddress;
    }

    // --- Improved Asset Management with History Tracking ---

    function addAsset(
        string memory _symbol,
        address _tokenAddress,
        uint256 _quantity,
        uint256 _weightNumerator,
        bool _isPreciousMetal,
        bytes32 _oracleFeedId
    ) external onlyAuthorized(assetManagementLink) {
        require(bytes(_symbol).length > 0, "Invalid symbol");
        require(!assetSymbolsSet.contains(_symbol), "Asset exists");
        require(_weightNumerator <= WEIGHT_DENOMINATOR, "Weight exceeds 100%");

        assets[_symbol] = Asset({
            symbol: _symbol,
            tokenAddress: _tokenAddress,
            quantity: _quantity,
            weightNumerator: _weightNumerator,
            isPreciousMetal: _isPreciousMetal,
            oracleFeedId: _oracleFeedId,
            lastPriceUpdate: 0,
            lastKnownPrice: 0
        });

        assetSymbolsSet.add(_symbol);

        _recordAssetChange(_symbol); // Record change in history

        _enforcePreciousMetalRule();
        emit AssetUpdated(_symbol, _tokenAddress, _quantity, _weightNumerator, _isPreciousMetal);
    }

    function removeAsset(string memory _symbol)
        external
        onlyAuthorized(assetManagementLink)
        validAsset(_symbol)
    {
        require(!_isGold(_symbol), "Cannot remove gold");

        // Record the state before removal
        Asset storage asset = assets[_symbol];
        assetHistory.push(
            AssetChange({
                symbol: _symbol,
                tokenAddress: asset.tokenAddress,
                quantity: asset.quantity,
                weightNumerator: asset.weightNumerator,
                isPreciousMetal: asset.isPreciousMetal,
                oracleFeedId: asset.oracleFeedId,
                timestamp: block.timestamp
            })
        );

        delete assets[_symbol];
        assetSymbolsSet.remove(_symbol);

        _enforcePreciousMetalRule();
        emit AssetRemoved(_symbol);
    }

    function setAssetWeight(string memory _symbol, uint256 _newWeight)
        external
        onlyAuthorized(assetManagementLink)
        validAsset(_symbol)
    {
        if (assetManagementLink != address(0)) {
            require(IAssetManager(assetManagementLink).validateAssetWeight(_symbol, _newWeight), "Invalid weight");
        }
        require(_newWeight <= WEIGHT_DENOMINATOR, "Weight exceeds 100%");
        assets[_symbol].weightNumerator = _newWeight;

        _recordAssetChange(_symbol); // Record change in history

        _enforcePreciousMetalRule();
        emit AssetUpdated(
            _symbol,
            assets[_symbol].tokenAddress,
            assets[_symbol].quantity,
            _newWeight,
            assets[_symbol].isPreciousMetal
        );
    }

    // --- Helper Function to Record Asset Changes ---
    function _recordAssetChange(string memory _symbol) internal {
        if (assetHistory.length >= maxHistoryEntries) {
            // Remove oldest entry if limit reached
            for (uint i = 1; i < assetHistory.length; i++) {
                assetHistory[i - 1] = assetHistory[i];
            }
            assetHistory.pop();
        }

        Asset storage asset = assets[_symbol];
        assetHistory.push(
            AssetChange({
                symbol: _symbol,
                tokenAddress: asset.tokenAddress,
                quantity: asset.quantity,
                weightNumerator: asset.weightNumerator,
                isPreciousMetal: asset.isPreciousMetal,
                oracleFeedId: asset.oracleFeedId,
                timestamp: block.timestamp
            })
        );

        emit AssetChanged(_symbol, block.timestamp);
    }

    // --- Query Functions for History ---
    function getFullHistory() external view returns (AssetChange[] memory) {
        return assetHistory;
    }

    function getHistoryInRange(uint256 _from, uint256 _to)
        external
        view
        returns (AssetChange[] memory result)
    {
        uint count = 0;
        for (uint i = 0; i < assetHistory.length; i++) {
            if (
                assetHistory[i].timestamp >= _from &&
                assetHistory[i].timestamp <= _to
            ) {
                count++;
            }
        }

        result = new AssetChange[](count);
        uint idx = 0;
        for (uint i = 0; i < assetHistory.length; i++) {
            if (
                assetHistory[i].timestamp >= _from &&
                assetHistory[i].timestamp <= _to
            ) {
                result[idx] = assetHistory[i];
                idx++;
            }
        }
    }

    // --- Price Oracle Handling ---
    function _getAssetPriceInUSD(bytes32 _oracleFeedId) internal returns (uint256 price) {
        if (priceOracleLink != address(0)) {
            try IPriceOracle(priceOracleLink).getLatestPrice(_oracleFeedId) returns (int256 oraclePrice, uint256 timestamp) {
                if (oraclePrice > 0 && IPriceOracle(priceOracleLink).isPriceFeedActive(_oracleFeedId)) {
                    return uint256(oraclePrice);
                }
            } catch {}
        }

        if (_oracleFeedId == bytes32(GOLD_SYMBOL) && goldOracleAddress != address(0)) {
            // Chainlink fallback logic would be added here
            revert("Gold price unavailable");
        }

        revert("Price feed unavailable");
    }

    // --- Enhanced Rebalancing ---
    function performRebalance() external whenNotPaused nonReentrant {
        uint256 currentTime = block.timestamp;
        bool shouldRebalance = false;

        if (rebalanceLink != address(0)) {
            shouldRebalance = IRebalanceController(rebalanceLink).shouldRebalance(currentTime, lastRebalanceTimestamp);
        } else {
            uint256 nextRebalanceTime = lastRebalanceTimestamp + rebalanceInterval;
            shouldRebalance = currentTime >= nextRebalanceTime && 
                              currentTime <= nextRebalanceTime + rebalanceWindow;
        }

        require(shouldRebalance || msg.sender == owner(), "Rebalance not allowed");
        _executeRebalance();
        lastRebalanceTimestamp = currentTime;
        emit RebalancePerformed(currentTime);
    }

    function emergencyRebalance() external onlyOwner whenPaused {
        _executeRebalance();
        emit EmergencyRebalanceExecuted(msg.sender);
    }

    function setRebalanceParameters(uint256 _interval, uint256 _window) external onlyOwner {
        require(_interval >= 1 hours, "Interval too short");
        require(_window <= _interval, "Window too large");
        rebalanceInterval = _interval;
        rebalanceWindow = _window;
    }

    // --- Pause and Withdraw Functions ---
    function pause() external onlyAuthorized(pauseUnpauseLink) {
        _pause();
    }

    function unpause() external onlyAuthorized(pauseUnpauseLink) {
        _unpause();
    }

    function withdrawFunds(address _tokenAddress, uint256 _amount)
        external
        nonReentrant
        onlyAuthorized(withdrawFundsLink)
    {
        // Existing implementation would go here
    }

    // --- Helper Functions ---
    function _isGold(string memory _symbol) internal pure returns (bool) {
        return keccak256(bytes(_symbol)) == keccak256(bytes(GOLD_SYMBOL));
    }

    function _enforcePreciousMetalRule() internal {
        uint256 totalPreciousMetalWeight = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < assetSymbolsSet.length(); i++) {
            string memory symbol = assetSymbolsSet.at(i);
            Asset storage asset = assets[symbol];
            totalWeight += asset.weightNumerator;
            if (asset.isPreciousMetal) {
                totalPreciousMetalWeight += asset.weightNumerator;
            }
        }

        require(totalPreciousMetalWeight >= MIN_PRECIOUS_METAL_WEIGHT, "Precious metals < 50%");

        if (totalWeight < WEIGHT_DENOMINATOR) {
            uint256 compensation = WEIGHT_DENOMINATOR - totalWeight;
            assets[GOLD_SYMBOL].weightNumerator += compensation;
            emit GoldCompensated(compensation);
        }
    }

    function _executeRebalance() internal {
        // Placeholder for rebalancing logic
    }

    // --- Getters ---
    function getAssetSymbols() external view returns (string[] memory) {
        return assetSymbolsSet.values();
    }

    function assetExists(string memory _symbol) external view returns (bool) {
        return assetSymbolsSet.contains(_symbol);
    }

    function timeToNextRebalance() external view returns (uint256) {
        if (rebalanceLink != address(0)) {
            return IRebalanceController(rebalanceLink).getNextRebalanceTime(lastRebalanceTimestamp);
        }
        uint256 nextTime = lastRebalanceTimestamp + rebalanceInterval;
        return block.timestamp >= nextTime ? 0 : nextTime - block.timestamp;
    }
}
