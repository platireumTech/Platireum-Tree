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
import "@openzeppelin/contracts/utils/Strings.sol";
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

contract Platireum is ERC20, Ownable, Pausable, ReentrancyGuard {
    using Strings for Strings.StringSet;
    using SafeMath for uint256;

    // --- State Variables ---
    struct Asset {
        string symbol;
        address tokenAddress;
        uint256 quantity; // Will be dynamically calculated
        uint256 weightNumerator; // Target weight
        bool isPreciousMetal;
        bytes32 oracleFeedId;
        uint256 lastPriceUpdate;
        uint256 lastKnownPrice;
    }

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

    // External link update events
    event PriceOracleLinkUpdated(address indexed oldLink, address indexed newLink);
    event MintBurnLinkUpdated(address indexed oldLink, address indexed newLink);
    event RebalanceLinkUpdated(address indexed oldLink, address indexed newLink);
    event AssetManagementLinkUpdated(address indexed oldLink, address indexed newLink);
    event PauseUnpauseLinkUpdated(address indexed oldLink, address indexed newLink);
    event WithdrawFundsLinkUpdated(address indexed oldLink, address indexed newLink);

    // --- Modifiers ---
    modifier onlyAuthorized(address _link) {
        require(msg.sender == owner() || (msg.sender == _link && _link != address(0)), "Unauthorized");
        _;
    }

    modifier validAsset(string memory _symbol) {
        require(assetSymbolsSet.contains(_symbol), "Asset does not exist");
        _;
    }

    // --- Constructor ---
    constructor(
        string memory name_, // e.g., "Platireum Token"
        string memory symbol_, // Now changed to "TREE"
        address _goldOracleAddress
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        goldOracleAddress = _goldOracleAddress;
    }

    // --- Rest of the contract remains unchanged ---

    // --- External Link Management Functions (Owner-only to set links) ---
    function setPriceOracleLink(address _newLink) public onlyOwner {
        emit PriceOracleLinkUpdated(priceOracleLink, _newLink);
        priceOracleLink = _newLink;
    }

    function setMintBurnLink(address _newLink) public onlyOwner {
        emit MintBurnLinkUpdated(mintBurnLink, _newLink);
        mintBurnLink = _newLink;
    }

    function setRebalanceLink(address _newLink) public onlyOwner {
        emit RebalanceLinkUpdated(rebalanceLink, _newLink);
        rebalanceLink = _newLink;
    }

    function setAssetManagementLink(address _newLink) public onlyOwner {
        emit AssetManagementLinkUpdated(assetManagementLink, _newLink);
        assetManagementLink = _newLink;
    }

    function setPauseUnpauseLink(address _newLink) public onlyOwner {
        emit PauseUnpauseLinkUpdated(pauseUnpauseLink, _newLink);
        pauseUnpauseLink = _newLink;
    }

    function setWithdrawFundsLink(address _newLink) public onlyOwner {
        emit WithdrawFundsLinkUpdated(withdrawFundsLink, _newLink);
        withdrawFundsLink = _newLink;
    }


    // --- Improved Asset Management with History Tracking ---

    function addAsset(
        string memory _symbol,
        address _tokenAddress,
        // Removed _quantity from parameter as it will be dynamic/calculated
        uint256 _weightNumerator, // Target weight
        bool _isPreciousMetal,
        bytes32 _oracleFeedId
    ) external onlyAuthorized(assetManagementLink) {
        require(bytes(_symbol).length > 0, "Invalid symbol");
        require(!assetSymbolsSet.contains(_symbol), "Asset exists");
        require(_weightNumerator <= WEIGHT_DENOMINATOR, "Weight exceeds 100%");

        // Ensure gold is always present if it's the base
        if (_isGold(_symbol)) {
            require(_tokenAddress == address(0), "Gold token address must be zero"); // Gold is typically not an ERC20 in this context
            goldOracleAddress = goldOracleAddress == address(0) ? address(this) : goldOracleAddress; // Set default gold oracle if not set
        }

        assets[_symbol] = Asset({
            symbol: _symbol,
            tokenAddress: _tokenAddress,
            quantity: 0, // Initial quantity is 0, will be set by rebalance
            weightNumerator: _weightNumerator,
            isPreciousMetal: _isPreciousMetal,
            oracleFeedId: _oracleFeedId,
            lastPriceUpdate: 0,
            lastKnownPrice: 0
        });

        assetSymbolsSet.add(_symbol);

        _recordAssetChange(_symbol); // Record change in history

        _enforcePreciousMetalRule(); // Enforce rules after adding asset
        emit AssetUpdated(_symbol, _tokenAddress, 0, _weightNumerator, _isPreciousMetal);
    }

    function removeAsset(string memory _symbol)
        external
        onlyAuthorized(assetManagementLink)
        validAsset(_symbol)
    {
        require(!_isGold(_symbol), "Cannot remove gold");

        // Record the state before removal
        Asset storage asset = assets[_symbol];
        _recordAssetChange(_symbol); // Record before deleting

        delete assets[_symbol];
        assetSymbolsSet.remove(_symbol);

        _enforcePreciousMetalRule(); // Re-check after removal
        emit AssetRemoved(_symbol);
    }

    function setAssetWeight(string memory _symbol, uint256 _newWeight)
        external
        onlyAuthorized(assetManagementLink)
        validAsset(_symbol)
    {
        if (assetManagementLink != address(0)) {
            require(IAssetManager(assetManagementLink).validateAssetWeight(_symbol, _newWeight), "Invalid weight by link");
        }
        require(_newWeight <= WEIGHT_DENOMINATOR, "Weight exceeds 100%");
        
        assets[_symbol].weightNumerator = _newWeight;

        _recordAssetChange(_symbol); // Record change in history

        _enforcePreciousMetalRule(); // Enforce rules after setting weight
        emit AssetUpdated(
            _symbol,
            assets[_symbol].tokenAddress,
            assets[_symbol].quantity, // Current quantity (will be updated by rebalance)
            _newWeight,
            assets[_symbol].isPreciousMetal
        );
    }

    // Removed setAssetQuantity as it's now dynamically managed by rebalance


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
        return result;
    }

    // --- Price Oracle Handling ---
    function _getAssetPriceInUSD(bytes32 _oracleFeedId, string memory _assetSymbol) internal returns (uint256 price) {
        int256 oraclePrice;
        uint256 oracleTimestamp;

        // 1. Priority to External Price Oracle Link
        if (priceOracleLink != address(0)) {
            try IPriceOracle(priceOracleLink).getLatestPrice(_oracleFeedId) returns (int256 externalPrice, uint256 externalTimestamp) {
                if (externalPrice > 0 && IPriceOracle(priceOracleLink).isPriceFeedActive(_oracleFeedId)) {
                    // Update last known price for this asset
                    assets[_assetSymbol].lastPriceUpdate = externalTimestamp;
                    assets[_assetSymbol].lastKnownPrice = uint256(externalPrice);
                    return uint256(externalPrice);
                }
            } catch {} // Fallback if external link call fails or returns 0/negative/inactive
        }

        // 2. Fallback to Chainlink Oracle (if configured and active)
        // This part needs real Chainlink integration, placeholder for now
        // Example: If _oracleFeedId corresponds to a known Chainlink aggregator
        // if (_oracleFeedId == bytes32("XAU/USD_FEED") && goldOracleAddress != address(0)) {
        //     AggregatorV3Interface priceFeed = AggregatorV3Interface(goldOracleAddress);
        //     (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
        //     require(answer > 0, "Chainlink price not available");
        //     // Example freshness check for Chainlink (e.g., within 3 hours)
        //     require(block.timestamp.sub(updatedAt) <= 3 hours, "Chainlink price too old");
        //     assets[_assetSymbol].lastPriceUpdate = updatedAt;
        //     assets[_assetSymbol].lastKnownPrice = uint256(answer);
        //     return uint256(answer);
        // }

        // 3. Fallback to Last Known Price (if recent enough)
        if (assets[_assetSymbol].lastKnownPrice > 0 && block.timestamp.sub(assets[_assetSymbol].lastPriceUpdate) <= 1 days) { // Example: price valid for 1 day
             return assets[_assetSymbol].lastKnownPrice;
        }

        revert("Price feed unavailable or too old");
    }

    // --- Enhanced Rebalancing ---
    function performRebalance() external whenNotPaused nonReentrant {
        uint256 currentTime = block.timestamp;
        bool shouldRebalance = false;

        if (rebalanceLink != address(0)) {
            // Check if external link exists AND is caller
            require(msg.sender == rebalanceLink, "WU: Not authorized via Rebalance Link");
            shouldRebalance = IRebalanceController(rebalanceLink).shouldRebalance(currentTime, lastRebalanceTimestamp);
        } else {
            // Internal automated rebalance logic (if no external link)
            uint256 nextRebalanceTime = lastRebalanceTimestamp + rebalanceInterval;
            shouldRebalance = currentTime >= nextRebalanceTime &&
                             currentTime <= nextRebalanceTime + rebalanceWindow;
            // Allow owner to force rebalance even outside window if no link
            if (!shouldRebalance && msg.sender == owner()) {
                shouldRebalance = true;
            }
        }

        require(shouldRebalance, "Rebalance not allowed at this time");
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
        if (_tokenAddress == address(0)) {
            // Withdraw native ETH
            (bool success, ) = payable(msg.sender).call{value: _amount}("");
            require(success, "WU: ETH withdrawal failed");
        } else {
            // Withdraw ERC20 tokens held by this contract
            ERC20 token = ERC20(_tokenAddress);
            require(token.transfer(msg.sender, _amount), "WU: ERC20 withdrawal failed");
        }
    }

    // Function to get balance of ERC20 assets held by this contract
    // (This is a read-only function, no external link for its operation)
    function getAssetBalance(address _assetTokenAddress) public view returns (uint256) {
        if (_assetTokenAddress == address(0)) {
            return address(this).balance; // Native ETH balance
        } else {
            return ERC20(_assetTokenAddress).balanceOf(address(this));
        }
    }

    // --- Helper Functions ---
    function _isGold(string memory _symbol) internal pure returns (bool) {
        return keccak256(bytes(_symbol)) == keccak256(bytes(GOLD_SYMBOL));
    }

    function _enforcePreciousMetalRule() internal {
        uint256 totalPreciousMetalWeight = 0;
        uint256 totalWeight = 0;

        string[] memory symbols = assetSymbolsSet.values(); // Get all symbols

        for (uint256 i = 0; i < symbols.length; i++) {
            string memory symbol = symbols[i];
            Asset storage asset = assets[symbol];
            totalWeight += asset.weightNumerator;
            if (asset.isPreciousMetal) {
                totalPreciousMetalWeight += asset.weightNumerator;
            }
        }

        // --- NEW REQUIREMENT: Total weight must not exceed 100% (excluding gold compensation) ---
        require(totalWeight <= WEIGHT_DENOMINATOR, "Total configured weight exceeds 100%");

        require(totalPreciousMetalWeight >= MIN_PRECIOUS_METAL_WEIGHT, "Precious metals < 50%");

        // Gold compensation if total configured weight is less than 100%
        if (totalWeight < WEIGHT_DENOMINATOR) {
            uint256 compensation = WEIGHT_DENOMINATOR.sub(totalWeight); // Using SafeMath
            // Ensure Gold asset exists before trying to compensate
            require(assetSymbolsSet.contains(GOLD_SYMBOL), "Gold asset must be added first for compensation");
            assets[GOLD_SYMBOL].weightNumerator = assets[GOLD_SYMBOL].weightNumerator.add(compensation); // Using SafeMath
            emit GoldCompensated(compensation);
        }
    }

    function _executeRebalance() internal {
        // This is the core logic where quantities (assets[_symbol].quantity)
        // are adjusted to meet target weights (assets[_symbol].weightNumerator).
        //
        // Steps:
        // 1. Get total value of 1 Platireum in USD based on current assets' values
        //    (This would likely be a target value, e.g., 1 Platireum = 1000 USD).
        //    Or, calculate current actual value of all assets if token has a reserve.
        // 2. For each asset:
        //    a. Get its current market price via _getAssetPriceInUSD.
        //    b. Calculate the target USD value for this asset based on its weightNumerator:
        //       `targetAssetValue = (totalPlatireumValueInUSD * asset.weightNumerator) / WEIGHT_DENOMINATOR;`
        //    c. Calculate the new quantity needed for this asset:
        //       `newQuantity = (targetAssetValue * 1e18) / assetPriceUSD;` (adjust 1e18 for price decimals)
        //    d. Update `assets[_symbol].quantity = newQuantity;`
        //
        // This function will also need to consider:
        // - Managing the actual underlying assets (buying/selling to match new quantities).
        //   This is typically done off-chain or via DEX integrations which are out of scope for this conceptual contract.
        // - Handling slippage, fees, and minimum trade sizes if integrated with real trading.
        //
        // Placeholder for the actual rebalancing logic.
        // Example:
        // uint256 totalPlatireumValueInUSD = 100 * 1e18; // Example: assuming 1 Platireum aims for 100 USD value
        // string[] memory symbols = assetSymbolsSet.values();
        // for (uint256 i = 0; i < symbols.length; i++) {
        //     string memory symbol = symbols[i];
        //     Asset storage asset = assets[symbol];
        //
        //     uint256 assetPriceUSD = _getAssetPriceInUSD(asset.oracleFeedId, symbol);
        //     require(assetPriceUSD > 0, "WU: Asset price is zero");
        //
        //     uint256 targetAssetValue = totalPlatireumValueInUSD.mul(asset.weightNumerator).div(WEIGHT_DENOMINATOR);
        //     uint256 newQuantity = targetAssetValue.mul(1e18).div(assetPriceUSD); // Adjust 1e18 for oracle decimals if different
        //
        //     asset.quantity = newQuantity; // Update the dynamic quantity
        // }
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
        uint256 nextTime = lastRebalanceTimestamp.add(rebalanceInterval); // Using SafeMath
        return block.timestamp >= nextTime ? 0 : nextTime.sub(block.timestamp); // Using SafeMath
    }

    // --- Public Getters (Read Functions) ---

    // Function to get the value of 1 Platireum in grams of Gold
    // This assumes `quantity` field of Asset struct is updated by rebalance to reflect real composition
    function getPlatireumValueInGold() public view returns (uint256 goldGramsScaled) {
        uint256 totalPlatireumValueInUSD = 0;

        string[] memory symbols = assetSymbolsSet.values();
        for (uint i = 0; i < symbols.length; i++) {
            string memory symbol = symbols[i];
            Asset storage currentAsset = assets[symbol];

            // Use lastKnownPrice for view function to avoid state changes, or get fresh if needed.
            // For a view function, it's safer to use a function that doesn't modify state.
            // If getLatestPrice requires state change, you'd need a separate view function
            // or use `lastKnownPrice` for this getter.
            // For now, let's assume _getAssetPriceInUSD can be called in view context if it just reads.
            // To make it view, _getAssetPriceInUSD would need to be view as well.
            // Let's use `lastKnownPrice` for simplicity in this view function.
            uint256 assetPriceUSD = currentAsset.lastKnownPrice; // Use last known, or implement a view-only price fetcher
            require(assetPriceUSD > 0, "Vestra: Asset price is zero (last known)");


            // This calculation sums the USD value of fixed quantities per 1 Platireum
            // If asset.quantity is updated by rebalance to reflect the target weights,
            // then this will reflect the actual value.
            totalPlatireumValueInUSD = totalPlatireumValueInUSD.add(
                currentAsset.quantity.mul(assetPriceUSD).div(1e18) // Adjust 1e18 for price decimals
            );
        }

        uint256 goldPricePerGramUSD = assets[GOLD_SYMBOL].lastKnownPrice; // Use last known Gold price
        require(goldPricePerGramUSD > 0, "Vestra: Gold price must be greater than zero");

        // Convert total Platireum value from USD to grams of Gold
        goldGramsScaled = (totalPlatireumValueInUSD.mul(1e18)).div(goldPricePerGramUSD); // Adjust scaling as needed

        return goldGramsScaled;
    }

    // New Function to show detailed asset breakdown
    function getAssetDetails() public view returns (
        string[] memory symbols,
        uint256[] memory quantities,
        uint256[] memory targetWeights, // Renamed from currentWeights to clarify they are target
        uint256[] memory currentPricesUSD,
        string[] memory priceSources,
        uint256 preciousMetalTotalWeight,
        uint256 goldCompensationWeight
    ) {
        symbols = assetSymbolsSet.values(); // Use EnumerableSet for symbols
        quantities = new uint256[](symbols.length);
        targetWeights = new uint256[](symbols.length);
        currentPricesUSD = new uint256[](symbols.length);
        priceSources = new string[](symbols.length);
        preciousMetalTotalWeight = 0;
        goldCompensationWeight = 0;

        uint256 totalTargetWeightSum = 0; // To calculate gold compensation

        for (uint i = 0; i < symbols.length; i++) {
            string memory symbol = symbols[i];
            Asset storage currentAsset = assets[symbol];

            // Use lastKnownPrice for view function
            uint256 assetPriceUSD = currentAsset.lastKnownPrice;
            if (assetPriceUSD == 0) {
                 // Try to get a fresh price if not available, but keep it view.
                 // This would typically involve a separate `view` function for external oracle.
                 // For now, if 0, it means no valid last known price.
            }

            symbols[i] = symbol;
            quantities[i] = currentAsset.quantity; // This is the dynamically updated quantity
            targetWeights[i] = currentAsset.weightNumerator; // This is the target weight
            currentPricesUSD[i] = assetPriceUSD;

            string memory source = "N/A";
            if (priceOracleLink != address(0)) {
                source = "External Link";
            } else if (currentAsset.oracleFeedId != bytes32(0)) {
                source = "Chainlink/Default"; // Assuming Chainlink or other default internal oracle
            }
            priceSources[i] = source;

            totalTargetWeightSum = totalTargetWeightSum.add(currentAsset.weightNumerator);

            if (currentAsset.isPreciousMetal) {
                preciousMetalTotalWeight = preciousMetalTotalWeight.add(currentAsset.weightNumerator);
            }
        }

        // Gold compensation for the 100% total weight rule (this value is based on target weights)
        if (totalTargetWeightSum < WEIGHT_DENOMINATOR) {
            goldCompensationWeight = WEIGHT_DENOMINATOR.sub(totalTargetWeightSum);
        }

        return (
            symbols,
            quantities,
            targetWeights,
            currentPricesUSD,
            priceSources,
            preciousMetalTotalWeight,
            goldCompensationWeight
        );
    }
    // --- Fallback function to receive Ether ---
    receive() external payable {}
}
