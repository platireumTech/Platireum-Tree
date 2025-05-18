// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMintable {
    function mint(address to, uint256 amount) external;
}

interface IBurnable {
    function burn(uint256 amount) external;
}

interface IAssetManager {
    function buyAssetsProportionally(uint256 reserveAmount) external;
    function sellAssetsProportionally(uint256 reserveAmount) external;
    function getTotalAssetValue() external view returns (uint256);
    function checkLiquidity(uint256 usdAmount) external view returns (bool);
}
