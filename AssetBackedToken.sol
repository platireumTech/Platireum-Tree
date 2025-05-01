// AssetBackedToken.sol
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./AssetManager.sol";
import "./TokenPricer.sol";

contract AssetBackedToken is ERC20, Ownable {
    AssetManager public assetManager;
    TokenPricer public tokenPricer;
    uint256 public constant MAX_SUPPLY = 1000000 * 10**18;

    constructor() ERC20("Platireum", "TREE") {
        assetManager = new AssetManager();
        tokenPricer = new TokenPricer(assetManager);
        // Initial assets are added through AssetManager
        assetManager.addAsset("GOLD", 40, 0x...);
        assetManager.addAsset("SILVER", 20, 0x...);
        assetManager.addAsset("APPLE", 20, 0x...);
        assetManager.addAsset("ALPHABET", 20, 0x...);
    }

    // Expose AssetManager functions via a proxy if needed
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
}
