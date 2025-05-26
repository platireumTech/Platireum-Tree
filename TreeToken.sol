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

// Interfaces for external contracts (Oracles, Rebalancing, Governance, etc.)
// These will be defined based on the specific external contracts you integrate.
interface IPriceOracle {
    function getLatestPrice(bytes32 _assetId) external view returns (int256 price);
    function getLatestTimestamp(bytes32 _assetId) external view returns (uint256 timestamp);
}

// Interface for a potential external Mint/Burn controller
interface IMintBurnController {
    function canMint(uint256 _amount) external view returns (bool);
    function canBurn(uint256 _amount) external view returns (bool);
}

// Interface for an external Rebalancing controller
interface IRebalanceController {
    function shouldRebalance(uint255 currentTimestamp) external view returns (bool);
    // Potentially functions for specific rebalancing actions
}

// Interface for an external Asset Management controller (for modifying asset basket)
interface IAssetManager {
    function canAddAsset(string memory _symbol) external view returns (bool);
    function canRemoveAsset(string memory _symbol) external view returns (bool);
    function canSetAssetWeight(string memory _symbol, uint256 _newWeight) external view returns (bool);
}


contract Tree is ERC20, Ownable, Pausable, ReentrancyGuard {

    // --- State Variables ---

    // Asset Configuration
    struct Asset {
        string symbol;           // Asset symbol (e.g., "GOOGL", "XAU")
        address tokenAddress;    // Address if it's an ERC20 token (for stocks or other crypto assets)
        uint256 quantity;        // Fixed quantity per WU (if using fixed quantities)
        uint256 weightNumerator; // Numerator for percentage weight (e.g., for 30%, use 3000 if denominator is 10000)
        bool isPreciousMetal;    // Flag to easily identify precious metals for the 50% rule
        bytes32 oracleFeedId;    // Chainlink or custom Oracle feed ID
    }

    // Mapping from asset symbol to its details
    mapping(string => Asset) public assets;
    string[] public assetSymbols; // To iterate over all assets

    // Gold (XAU) specific details, as it's the base unit of value
    string public constant GOLD_SYMBOL = "XAU";
    address public goldOracleAddress; // Specific oracle for gold price

    // Denominators for weights (e.g., 10000 for 4 decimal places of percentage)
    uint256 public constant WEIGHT_DENOMINATOR = 10000; // 100.00%
    uint256 public constant MIN_PRECIOUS_METAL_WEIGHT = 5000; // 50.00%

    // --- External Linkage Addresses (Pluggable Architecture) ---
    address public priceOracleLink;         // External contract for asset prices
    address public mintBurnLink;            // External contract for minting/burning control
    address public rebalanceLink;           // External contract for rebalancing logic execution
    address public assetManagementLink;     // External contract for asset basket modifications
    address public pauseUnpauseLink;        // External contract for pause/unpause control
    address public withdrawFundsLink;       // External contract for funds withdrawal control


    // --- Timing Variables for Rebalancing ---
    uint256 public lastRebalanceTimestamp;
    uint256 public rebalanceInterval = 24 * 60 * 60; // 24 hours in seconds (daily)
    uint256 public rebalanceHourUTC = 21; // 00:00 القدس (GMT+3) means 21:00 UTC previous day


    // --- Events ---
    event AssetAdded(string indexed symbol, address indexed tokenAddress, uint256 quantity, uint256 weightNumerator, bool isPreciousMetal);
    event AssetRemoved(string indexed symbol);
    event AssetWeightUpdated(string indexed symbol, uint256 newWeightNumerator);
    event AssetQuantityUpdated(string indexed symbol, uint256 newQuantity);
    event PriceOracleLinkUpdated(address indexed oldLink, address indexed newLink);
    event MintBurnLinkUpdated(address indexed oldLink, address indexed newLink);
    event RebalanceLinkUpdated(address indexed oldLink, address indexed newLink);
    event AssetManagementLinkUpdated(address indexed oldLink, address indexed newLink);
    event PauseUnpauseLinkUpdated(address indexed oldLink, address indexed newLink);
    event WithdrawFundsLinkUpdated(address indexed oldLink, address indexed newLink);
    event RebalancePerformed(uint256 timestamp);
    event GoldCompensated(uint256 percentageAdded);
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);


    // --- Constructor ---
    constructor(
        string memory name,
        string memory symbol,
        address _goldOracleAddress // Initial Chainlink Gold Oracle
    ) ERC20(name, symbol) Ownable(msg.sender) {
        goldOracleAddress = _goldOracleAddress;
        // Initial setup for default assets and weights
        // This is done once at deployment.
        // You would call initial `addAsset` functions here or via initial admin calls.
        // Example:
        // addAsset("XAU", address(0), 0, 3000, true, bytes32("XAU/USD")); // Gold 30%
        // addAsset("XAG", address(0), 0, 1000, true, bytes32("XAG/USD")); // Silver 10%
        // addAsset("PLT", address(0), 0, 400, true, bytes32("XPT/USD")); // Platinum 4%
        // addAsset("PD", address(0), 0, 300, true, bytes32("XPD/USD")); // Palladium 3%
        // addAsset("C_U", address(0), 0, 200, true, bytes32("XCU/USD")); // Copper 2%
        // addAsset("ALU", address(0), 0, 100, true, bytes32("XAL/USD")); // Aluminum 1%
        // Remaining 50% for stocks will be set up later.
    }


    // --- Modifiers for Pluggable Control ---
    modifier onlyLinkOrOwner(address _linkAddress) {
        require(msg.sender == owner() || msg.sender == _linkAddress, "Not authorized: Only owner or designated link can call.");
        _;
    }

    modifier onlyOwnerOrSpecificLink(address _specificLinkAddress) {
        require(msg.sender == owner() || msg.sender == _specificLinkAddress, "WU: Not owner or specific link");
        _;
    }


    // --- Core Logic: Get Asset Price ---
    // This function encapsulates the priority logic for getting asset prices
    function _getAssetPriceInUSD(bytes32 _oracleFeedId) internal view returns (uint256 price) {
        int256 oraclePrice;
        uint256 oracleTimestamp;

        // 1. Priority to External Price Oracle Link
        if (priceOracleLink != address(0)) {
            try IPriceOracle(priceOracleLink).getLatestPrice(_oracleFeedId) returns (int256 externalPrice) {
                // You would add checks here for freshness, e.g., using IPriceOracle(priceOracleLink).getLatestTimestamp()
                // For simplicity now, we assume if it returns, it's valid.
                if (externalPrice > 0) return uint256(externalPrice);
            } catch {} // Fallback if external link call fails or returns 0/negative
        }

        // 2. Fallback to Chainlink Oracle (default specified in constructor for gold, other assets set via admin)
        // This requires `goldOracleAddress` to be a Chainlink AggregatorV3Interface address
        // You would likely have a mapping for other asset oracle addresses as well.
        if (_oracleFeedId == bytes32(GOLD_SYMBOL) && goldOracleAddress != address(0)) {
            // Placeholder for Chainlink logic - requires Chainlink AggregatorV3Interface import
            // AggregatorV3Interface priceFeed = AggregatorV3Interface(goldOracleAddress);
            // (, int256 answer, , uint256 updatedAt, ) = priceFeed.latestRoundData();
            // require(updatedAt > block.timestamp - Chainlink_HEARTBEAT_THRESHOLD, "Price too old"); // Example heartbeat check
            // return uint256(answer);
            // For now, let's return a dummy value if no real oracle is integrated
            return 75550000000000000000; // Example: 75.55 USD per gram (scaled for 18 decimals)
        }

        // Add more specific Chainlink oracle lookups for other assets based on their feed IDs.
        // For example: if assets[symbol].oracleAddress != address(0) for a specific symbol

        // 3. Last resort fallback (e.g., last known price, or revert)
        // In a real system, you'd likely revert or use a sophisticated last-known-good price mechanism.
        // For this conceptual code, we'll just revert if no price is found.
        revert("WU: Could not get asset price");
    }

    // --- Public Getters (Read Functions) ---

    // Function to get the value of 1 WU in grams of Gold
    function getWealthUnitValueInGold() public view returns (uint256 goldGramsScaled) {
        uint256 totalWuValueInUSD = 0;
        uint256 currentPreciousMetalWeight = 0;

        // Calculate total value of WU in USD and sum of precious metal weights
        for (uint i = 0; i < assetSymbols.length; i++) {
            string memory symbol = assetSymbols[i];
            Asset storage currentAsset = assets[symbol];

            // If using fixed quantities, this calculation needs adjustment.
            // This assumes we're working with percentage weights for all assets,
            // and we calculate what quantity would represent that weight in USD for a notional WU.
            // For a true SDR-like model, initial 'quantities' are fixed, and then their USD value is summed.
            // Let's assume for calculation clarity that we use the fixed quantities and their current USD value.

            uint256 assetPriceUSD = _getAssetPriceInUSD(currentAsset.oracleFeedId); // Price per unit of asset

            // This part needs careful definition:
            // If `quantity` is fixed, then `currentAsset.quantity * assetPriceUSD` is the USD value of that asset's share.
            // If `weightNumerator` is fixed, then `totalWuValueInUSD` must be known first, or we need to calculate
            // how many units of each asset represent its weight.
            // Given your SDR-like model, let's assume `quantity` is the *fixed* amount of asset per 1 WU.
            // However, your requirement for "fixed percentage weights for metals" implies `weightNumerator` is fixed.
            // This is a conflict: fixed quantities lead to variable percentages, fixed percentages lead to variable quantities.
            // For this code, I'll prioritize "fixed quantities" as in SDR and use "weights" for the _policy_ of setting those quantities.

            // Let's re-align: we'll calculate the total value of 1 WU based on current fixed quantities.
            // The "weights" will be used by the rebalancing function to adjust `quantity` if needed.

            // For now, let's sum up the value of each fixed quantity.
            // NOTE: This assumes 'quantity' is in base units (e.g., shares for stocks, oz for metals).
            // `_getAssetPriceInUSD` should return price per base unit.
            totalWuValueInUSD += (currentAsset.quantity * assetPriceUSD) / 1e18; // Assuming scaled prices.

            // Check metal weight only for display/validation, not direct calculation here
            // If the fixed quantities were initially set based on specific weights, this is valid.
        }

        uint256 goldPricePerGramUSD = _getAssetPriceInUSD(bytes32(GOLD_SYMBOL)); // Price of 1 gram of gold in USD
        require(goldPricePerGramUSD > 0, "WU: Gold price must be greater than zero");

        // Convert total WU value from USD to grams of Gold
        goldGramsScaled = (totalWuValueInUSD * 1e18) / goldPricePerGramUSD; // Adjust scaling as needed

        return goldGramsScaled;
    }

    // New Function to show detailed asset breakdown (as requested)
    function getAssetDetails() public view returns (
        string[] memory symbols,
        uint256[] memory quantities,
        uint256[] memory currentWeights,
        uint256[] memory currentPricesUSD,
        string[] memory priceSources,
        uint256 preciousMetalTotalWeight,
        uint256 goldCompensationWeight
    ) {
        symbols = new string[](assetSymbols.length);
        quantities = new uint256[](assetSymbols.length);
        currentWeights = new uint256[](assetSymbols.length);
        currentPricesUSD = new uint256[](assetSymbols.length);
        priceSources = new string[](assetSymbols.length);
        preciousMetalTotalWeight = 0;
        goldCompensationWeight = 0;

        uint256 totalWuValueInUSD = 0; // Calculate this first for accurate current weights

        for (uint i = 0; i < assetSymbols.length; i++) {
            string memory symbol = assetSymbols[i];
            Asset storage currentAsset = assets[symbol];

            uint256 assetPriceUSD = _getAssetPriceInUSD(currentAsset.oracleFeedId);
            uint256 assetValueInWuUSD = (currentAsset.quantity * assetPriceUSD) / 1e18; // Assuming scaled prices

            symbols[i] = symbol;
            quantities[i] = currentAsset.quantity;
            currentPricesUSD[i] = assetPriceUSD;

            string memory source = "N/A";
            if (priceOracleLink != address(0)) {
                source = "External Link";
            } else {
                source = "Chainlink/Default";
            }
            priceSources[i] = source;

            totalWuValueInUSD += assetValueInWuUSD;

            if (currentAsset.isPreciousMetal) {
                // This weight calculation is *current* weight based on actual value, not target weight.
                // Rebalancing aims to bring it back to target.
                // We'll re-calculate actual current weights later if needed, or assume target weights are what's displayed for policy.
            }
        }

        // Now calculate current percentage weights based on current total value (if totalWuValueInUSD > 0)
        if (totalWuValueInUSD > 0) {
            for (uint i = 0; i < assetSymbols.length; i++) {
                string memory symbol = assetSymbols[i];
                Asset storage currentAsset = assets[symbol];
                uint256 assetPriceUSD = _getAssetPriceInUSD(currentAsset.oracleFeedId);
                uint256 assetValueInWuUSD = (currentAsset.quantity * assetPriceUSD) / 1e18;
                currentWeights[i] = (assetValueInWuUSD * WEIGHT_DENOMINATOR) / totalWuValueInUSD;

                if (currentAsset.isPreciousMetal) {
                    preciousMetalTotalWeight += currentWeights[i];
                }
            }
        }


        // Gold compensation for the 100% total weight rule:
        // This part needs the *target* weights to check for 100%.
        // Assuming `assets[GOLD_SYMBOL].weightNumerator` holds the target weight of gold.
        uint256 totalTargetWeight = 0;
        for (uint i = 0; i < assetSymbols.length; i++) {
             totalTargetWeight += assets[assetSymbols[i]].weightNumerator;
        }

        if (totalTargetWeight < WEIGHT_DENOMINATOR) {
            goldCompensationWeight = WEIGHT_DENOMINATOR - totalTargetWeight;
        }

        return (
            symbols,
            quantities,
            currentWeights,
            currentPricesUSD,
            priceSources,
            preciousMetalTotalWeight,
            goldCompensationWeight
        );
    }


    // --- Admin/Owner/Link Controlled Functions (with prioritization) ---

    // --- Link Management Functions ---
    // These functions allow the owner to set/change/remove external links.
    // They are only callable by the contract owner.
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


    // --- Asset Management Functions ---
    // These functions modify the asset basket.
    // Prioritize external Asset Management Link, then fallback to owner.
    function addAsset(
        string memory _symbol,
        address _tokenAddress, // address(0) for native assets like gold/silver
        uint256 _quantity,
        uint256 _weightNumerator, // Target weight
        bool _isPreciousMetal,
        bytes32 _oracleFeedId
    ) public {
        // If assetManagementLink is set, only allow call from that link
        if (assetManagementLink != address(0)) {
            require(msg.sender == assetManagementLink, "WU: Not authorized via Asset Management Link");
        } else {
            // Otherwise, only owner can call
            require(msg.sender == owner(), "WU: Not authorized by Owner");
        }

        // Input validation
        require(bytes(_symbol).length > 0, "WU: Symbol cannot be empty");
        require(assets[_symbol].weightNumerator == 0, "WU: Asset already exists"); // Check if asset already exists

        // Add asset to the mapping and symbol array
        assets[_symbol] = Asset({
            symbol: _symbol,
            tokenAddress: _tokenAddress,
            quantity: _quantity,
            weightNumerator: _weightNumerator,
            isPreciousMetal: _isPreciousMetal,
            oracleFeedId: _oracleFeedId
        });
        assetSymbols.push(_symbol);

        _checkAndApplyPreciousMetalWeightConstraint(); // Check and apply 50% metal rule

        emit AssetAdded(_symbol, _tokenAddress, _quantity, _weightNumerator, _isPreciousMetal);
    }

    function removeAsset(string memory _symbol) public {
        // Same link/owner authorization logic as addAsset
        if (assetManagementLink != address(0)) {
            require(msg.sender == assetManagementLink, "WU: Not authorized via Asset Management Link");
        } else {
            require(msg.sender == owner(), "WU: Not authorized by Owner");
        }

        require(assets[_symbol].weightNumerator > 0, "WU: Asset does not exist");
        require(bytes(_symbol) != bytes(GOLD_SYMBOL), "WU: Gold cannot be removed directly"); // Gold is fundamental

        delete assets[_symbol]; // Remove from mapping

        // Remove from dynamic array (inefficient for large arrays, but simple for now)
        for (uint i = 0; i < assetSymbols.length; i++) {
            if (bytes(assetSymbols[i]) == bytes(_symbol)) {
                assetSymbols[i] = assetSymbols[assetSymbols.length - 1];
                assetSymbols.pop();
                break;
            }
        }
        _checkAndApplyPreciousMetalWeightConstraint(); // Re-check after removal
        emit AssetRemoved(_symbol);
    }

    // Function to set new weight for an asset (for rebalancing policy)
    function setAssetWeight(string memory _symbol, uint256 _newWeightNumerator) public {
        // Same link/owner authorization logic
        if (assetManagementLink != address(0)) {
            require(msg.sender == assetManagementLink, "WU: Not authorized via Asset Management Link");
        } else {
            require(msg.sender == owner(), "WU: Not authorized by Owner");
        }

        require(assets[_symbol].weightNumerator > 0, "WU: Asset does not exist");
        assets[_symbol].weightNumerator = _newWeightNumerator;

        _checkAndApplyPreciousMetalWeightConstraint(); // Check and apply 50% metal rule
        emit AssetWeightUpdated(_symbol, _newWeightNumerator);
    }

    // Function to update the fixed quantity of an asset per WU (if that's the primary model)
    function setAssetQuantity(string memory _symbol, uint256 _newQuantity) public {
        // Same link/owner authorization logic
        if (assetManagementLink != address(0)) {
            require(msg.sender == assetManagementLink, "WU: Not authorized via Asset Management Link");
        } else {
            require(msg.sender == owner(), "WU: Not authorized by Owner");
        }

        require(assets[_symbol].weightNumerator > 0, "WU: Asset does not exist");
        assets[_symbol].quantity = _newQuantity;
        // No precious metal check here, as this directly changes quantity, not target weight.
        // Rebalancing logic will ensure actual weights match targets.
        emit AssetQuantityUpdated(_symbol, _newQuantity);
    }

    // Internal helper to enforce precious metal weight constraint and gold compensation
    function _checkAndApplyPreciousMetalWeightConstraint() internal {
        uint256 currentPreciousMetalWeight = 0;
        uint256 totalConfiguredWeight = 0;

        for (uint i = 0; i < assetSymbols.length; i++) {
            string memory symbol = assetSymbols[i];
            Asset storage currentAsset = assets[symbol];
            totalConfiguredWeight += currentAsset.weightNumerator;
            if (currentAsset.isPreciousMetal) {
                currentPreciousMetalWeight += currentAsset.weightNumerator;
            }
        }

        // Enforce 50% precious metal minimum
        require(currentPreciousMetalWeight >= MIN_PRECIOUS_METAL_WEIGHT, "WU: Precious metal weight must be >= 50%");

        // Compensate with gold if total configured weight is less than 100%
        if (totalConfiguredWeight < WEIGHT_DENOMINATOR) {
            uint256 goldCompensation = WEIGHT_DENOMINATOR - totalConfiguredWeight;
            assets[GOLD_SYMBOL].weightNumerator += goldCompensation;
            emit GoldCompensated(goldCompensation);
        } else if (totalConfiguredWeight > WEIGHT_DENOMINATOR) {
             // Optional: Handle if weights exceed 100%. Revert or adjust proportionally.
             // For simplicity, current design assumes that the sum of weights (excluding gold compensation)
             // will either be 100% or less, to be compensated by gold.
             revert("WU: Total configured weight exceeds 100%");
        }
    }


    // --- Minting and Burning Functions ---
    // Controlled by external link or owner if no link.
    function mint(address _to, uint256 _amount) public whenNotPaused {
        // Prioritize external Mint/Burn Link
        if (mintBurnLink != address(0)) {
            // In a real system, you'd call IMintBurnController(mintBurnLink).canMint(_amount) here.
            // For now, simply restrict to the linked address.
            require(msg.sender == mintBurnLink, "WU: Not authorized via Mint/Burn Link");
        } else {
            // Fallback to Owner control
            require(msg.sender == owner(), "WU: Not authorized by Owner");
        }
        _mint(_to, _amount);
        emit Minted(_to, _amount);
    }

    function burn(uint256 _amount) public whenNotPaused {
        // Prioritize external Mint/Burn Link
        if (mintBurnLink != address(0)) {
            // Call IMintBurnController(mintBurnLink).canBurn(_amount)
            require(msg.sender == mintBurnLink, "WU: Not authorized via Mint/Burn Link");
        } else {
            // Fallback to Owner control
            require(msg.sender == owner(), "WU: Not authorized by Owner");
        }
        _burn(msg.sender, _amount);
        emit Burned(msg.sender, _amount);
    }


    // --- Rebalancing Function ---
    // Automatically triggered or called by external link/owner
    function performRebalance() public whenNotPaused nonReentrant {
        uint256 currentTimestamp = block.timestamp;
        uint256 dayStartTimestampJerusalem = (currentTimestamp / rebalanceInterval) * rebalanceInterval + (rebalanceHourUTC * 60 * 60);

        // Adjust for Jerusalem timezone if block.timestamp is UTC
        // (00:00 Jerusalem is 21:00 UTC previous day if Jerusalem is GMT+3)
        if (currentTimestamp < dayStartTimestampJerusalem || currentTimestamp > dayStartTimestampJerusalem + (1 * 60 * 60)) {
            // Only allow rebalance within roughly 1 hour window of scheduled time (to avoid rebalancing far off schedule)
            // Or only allow it if it's the specific scheduled time.
            // For simplicity, allow if it's the scheduled day.
        }


        // 1. Priority to External Rebalance Link
        if (rebalanceLink != address(0)) {
            // In a real system, you'd call IRebalanceController(rebalanceLink).shouldRebalance(currentTimestamp)
            // and based on its return, allow it only if the caller is the rebalanceLink itself.
            require(msg.sender == rebalanceLink, "WU: Not authorized via Rebalance Link");
            // If the external link triggers, it's responsible for the actual rebalancing logic.
            // This function would primarily be a gateway for the external link.
        } else {
            // 2. Fallback to Internal Automated Rebalancing or Owner Trigger
            // If no external link, check if it's time for internal rebalance
            if (msg.sender == owner() || (currentTimestamp >= lastRebalanceTimestamp + rebalanceInterval)) {
                // Internal rebalancing logic goes here
                // This would involve:
                // a. Getting current asset prices using _getAssetPriceInUSD.
                // b. Calculating current actual weights vs. target weights (from assets[symbol].weightNumerator).
                // c. Determining required buys/sells of underlying assets to bring weights back to target.
                // d. Executing these trades if the contract holds the underlying assets, or triggering external systems.
                // This is the most complex part and often requires off-chain automation.
                // For a fully on-chain solution, you'd need AMM pools or similar.

                // Example: Adjust asset quantities based on target weights
                // This is a placeholder for actual rebalancing logic.
                // For a simple rebalance that ensures target weights are maintained
                // based on a notional WU value, you'd recalculate `quantity` for each asset.
                // If 1 WU is fixed at a certain Gold amount, then the USD value of 1 WU is known.
                // Then, desired USD value of each asset in 1 WU = (asset_target_weight / 100%) * WU_value_in_USD
                // And new quantity = desired_USD_value / asset_price_USD.
                // This will change the 'quantity' field for assets in the `assets` mapping.

                lastRebalanceTimestamp = currentTimestamp;
            } else {
                revert("WU: Not time for rebalance or not authorized.");
            }
        }
        emit RebalancePerformed(currentTimestamp);
    }


    // --- Pause/Unpause Function ---
    // Controlled by external link or owner if no link.
    function pause() public {
        if (pauseUnpauseLink != address(0)) {
            require(msg.sender == pauseUnpauseLink, "WU: Not authorized via Pause Link");
        } else {
            require(msg.sender == owner(), "WU: Not authorized by Owner");
        }
        _pause();
    }

    function unpause() public {
        if (pauseUnpauseLink != address(0)) {
            require(msg.sender == pauseUnpauseLink, "WU: Not authorized via Unpause Link");
        } else {
            require(msg.sender == owner(), "WU: Not authorized by Owner");
        }
        _unpause();
    }


    // --- Funds Withdrawal Function ---
    // Controlled by external link or owner if no link.
    function withdrawFunds(address _tokenAddress, uint256 _amount) public nonReentrant {
        // Check if `_tokenAddress` is address(0) for native ETH withdrawal
        if (withdrawFundsLink != address(0)) {
            require(msg.sender == withdrawFundsLink, "WU: Not authorized via Withdraw Link");
        } else {
            require(msg.sender == owner(), "WU: Not authorized by Owner");
        }

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

    // --- Fallback function to receive Ether ---
    receive() external payable {}
}
