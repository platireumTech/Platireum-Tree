// * Important Notice: Terms of Use for Platireum Currency: By receiving this Platireum currency, you irrevocably acknowledge and solemnly pledge your full adherence to the subsequent terms and conditions:
// *  1- Platireum must not be used for fraud or deception.
// *  2- Platireum must not be used for lending or borrowing with interest (usury).
// *  3- Platireum must not be used to buy or sell intoxicants, narcotics, or anything that impairs judgment.
// *  4- Platireum must not be used for criminal activities and money laundering.
// *  5- Platireum must not be used for gambling.

// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract AssetBackedToken is ERC20, Ownable {
    using SafeMath for uint256;

    // Chainlink Interface for Price Feeds
    interface AggregatorV3Interface {
        function latestRoundData()
            external
            view
            returns (
                uint80 roundId,
                int256 answer,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound
            );
    }

    struct Asset {
        string name;               // Asset Name
        uint256 weight;            // Asset Weight in Cart
        address priceFeedAddress;  // Oracle Contract Address of Asset
        bool isActive;             // Asset Status
    }

    // Asset Management
    mapping(bytes32 => Asset) public assets;
    bytes32[] public assetList;
    
    // متغير لتتبع الوزن الإجمالي النشط
    uint256 public totalActiveWeight = 0;

    // Total weights must equal 100
    uint256 public constant TOTAL_WEIGHT = 100;

    // Maximum Total Supply
    uint256 public constant MAX_SUPPLY = 1000000 * 10**18;

    // Events Tracking Asset Changes
    event AssetAdded(bytes32 indexed assetId, string name, uint256 weight, address priceFeedAddress);
    event AssetUpdated(bytes32 indexed assetId, string name, uint256 weight, address priceFeedAddress);
    event AssetRemoved(bytes32 indexed assetId, string name);

    constructor() ERC20("Platireum", "TREE") {
        // Adding Initial Assets with Oracle Addresses
        addAsset("GOLD", 40, 0x...);   // Oracle Address for Gold
        addAsset("SILVER", 20, 0x...); // Oracle Address for Silver
        addAsset("APPLE", 20, 0x...);  // Oracle Address for Apple Stock
        addAsset("ALPHABET", 20, 0x...); // Oracle Address for Alphabet Stock
    }

    // Add New Asset
    function addAsset(string memory name, uint256 weight, address priceFeedAddress) public onlyOwner {
        require(weight > 0 && weight <= 100, "Weight must be between 1 and 100");
        require(totalActiveWeight.add(weight) <= TOTAL_WEIGHT, "Total weight exceeds 100");

        bytes32 assetId = keccak256(abi.encodePacked(name));
        require(!assets[assetId].isActive, "Asset already exists");

        assets[assetId] = Asset(name, weight, priceFeedAddress, true);
        assetList.push(assetId);
        totalActiveWeight = totalActiveWeight.add(weight);

        emit AssetAdded(assetId, name, weight, priceFeedAddress);
    }

    // Fetch Price from Oracle
    function getPriceFromOracle(address priceFeedAddress) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }

    // Calculate Currency Price
    function getTokenPrice() public view returns (uint256) {
        uint256 weightedPrice = 0;

        for (uint256 i = 0; i < assetList.length; i++) {
            bytes32 assetId = assetList[i];
            if (assets[assetId].isActive) {
                uint256 price = getPriceFromOracle(assets[assetId].priceFeedAddress);
                weightedPrice = weightedPrice.add(price.mul(assets[assetId].weight));
            }
        }

        return weightedPrice.div(100); // Divide the result by 100 to get the weighted average
    }

    // Update Asset
    function updateAsset(bytes32 assetId, uint256 newWeight, address newPriceFeedAddress) public onlyOwner {
        require(assets[assetId].isActive, "Asset does not exist");
        require(newWeight > 0 && newWeight <= 100, "Weight must be between 1 and 100");

        uint256 totalWeightAfterUpdate = totalActiveWeight.sub(assets[assetId].weight).add(newWeight);
        require(totalWeightAfterUpdate <= TOTAL_WEIGHT, "Total weight exceeds 100");

        totalActiveWeight = totalWeightAfterUpdate;
        assets[assetId].weight = newWeight;
        assets[assetId].priceFeedAddress = newPriceFeedAddress;

        emit AssetUpdated(assetId, assets[assetId].name, newWeight, newPriceFeedAddress);
    }

    // Remove Asset - Improved Version
    function removeAsset(bytes32 assetId) public onlyOwner {
        require(assets[assetId].isActive, "Asset does not exist or already inactive");
        require(assetList.length > 1, "Cannot remove the last asset");

        // Update total weight before removing
        totalActiveWeight = totalActiveWeight.sub(assets[assetId].weight);
        
        // Store asset name for event before deactivation
        string memory assetName = assets[assetId].name;
        
        // Deactivate the asset
        assets[assetId].isActive = false;

        // Gas-efficient removal from array
        uint256 lastIndex = assetList.length - 1;
        for (uint256 i = 0; i <= lastIndex; i++) {
            if (assetList[i] == assetId) {
                // If it's not the last element, swap with last element
                if (i < lastIndex) {
                    assetList[i] = assetList[lastIndex];
                }
                // Remove the last element
                assetList.pop();
                break;
            }
        }

        emit AssetRemoved(assetId, assetName);
    }

    // حساب إجمالي الأوزان (الآن يعتمد على المتغير المخزن)
    function getTotalWeight() public view returns (uint256) {
        return totalActiveWeight;
    }
}
