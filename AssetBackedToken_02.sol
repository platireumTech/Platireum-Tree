// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

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
    string name;
    uint256 weight;
    address priceFeedAddress;
    bool isActive;
}

contract AssetManager is Ownable {
    using SafeMath for uint256;

    mapping(bytes32 => Asset) public assets;
    bytes32[] public assetList;
    uint256 public totalActiveWeight = 0;
    uint256 public constant TOTAL_WEIGHT = 100;

    event AssetAdded(bytes32 indexed assetId, string name, uint256 weight, address priceFeedAddress);
    event AssetUpdated(bytes32 indexed assetId, string name, uint256 weight, address priceFeedAddress);
    event AssetRemoved(bytes32 indexed assetId, string name);

    constructor() Ownable(msg.sender) {
    }

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

    function removeAsset(bytes32 assetId) public onlyOwner {
        require(assets[assetId].isActive, "Asset does not exist or already inactive");
        require(assetList.length > 1, "Cannot remove the last asset");
        totalActiveWeight = totalActiveWeight.sub(assets[assetId].weight);
        string memory assetName = assets[assetId].name;
        assets[assetId].isActive = false;
        uint256 lastIndex = assetList.length - 1;
        for (uint256 i = 0; i <= lastIndex; i++) {
            if (assetList[i] == assetId) {
                if (i < lastIndex) {
                    assetList[i] = assetList[lastIndex];
                }
                assetList.pop();
                break;
            }
        }
        emit AssetRemoved(assetId, assetName);
    }

    function getTotalWeight() public view returns (uint256) {
        return totalActiveWeight;
    }
}

contract TokenPricer {
    using SafeMath for uint256;

    AssetManager public assetManager;

    constructor(AssetManager _assetManager) {
        assetManager = _assetManager;
    }

    function getPriceFromOracle(address priceFeedAddress) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }

    function getTokenPrice() public view returns (uint256) {
        uint256 weightedPrice = 0;
        bytes32[] memory assetList = assetManager.assetList();
        for (uint256 i = 0; i < assetList.length; i++) {
            bytes32 assetId = assetList[i];
            AssetManager.Asset memory asset = assetManager.assets(assetId);
            if (asset.isActive) {
                uint256 price = getPriceFromOracle(asset.priceFeedAddress);
                weightedPrice = weightedPrice.add(price.mul(asset.weight));
            }
        }
        return weightedPrice.div(100);
    }
}

contract AssetBackedToken is ERC20, Ownable {
    AssetManager public assetManager;
    TokenPricer public tokenPricer;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {
        assetManager = new AssetManager();
        tokenPricer = new TokenPricer(assetManager);
        assetManager.addAsset("GOLD", 40, 0x...);
        assetManager.addAsset("SILVER", 20, 0x...);
        assetManager.addAsset("APPLE", 20, 0x...);
        assetManager.addAsset("ALPHABET", 20, 0x...);
    }

    function addAsset(string memory name, uint256 weight, address priceFeedAddress) public onlyOwner {
        assetManager.addAsset(name, weight, priceFeedAddress);
    }

    function updateAsset(bytes32 assetId, uint256 newWeight, address newPriceFeedAddress) public onlyOwner {
        assetManager.updateAsset(assetId, newWeight, newPriceFeedAddress);
    }

    function removeAsset(bytes32 assetId) public onlyOwner {
        assetManager.removeAsset(assetId);
    }

    function getTokenPrice() public view returns (uint256) {
        return tokenPricer.getTokenPrice();
    }

    function getTotalWeight() public view returns (uint256) {
        return assetManager.getTotalWeight();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
