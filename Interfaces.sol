// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAssetManager {
    function calculateAssetValueInGold() external view returns (uint256);
    function getGoldPriceUSD() external view returns (uint256);
}

interface IValueStabilizer {
    function adjustSupplyBasedOnAssetValue() external;
}

interface ISupplyController {
    function getCurrentMarketPrice() external view returns (uint256);
    function mint(uint256 amount) external;
    function burn(uint256 amount) external;
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

interface IBurnable {
    function burn(address from, uint256 amount) external;
}
