// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface INFT {
    /**
    @dev Allows composable minting contracts to check if minting is active.
    @return bool True if minting is active.
    */
    function isMintingActive() external view returns (bool);

    function isMaxSupplyReached() external view returns (bool);

    function mint(address _recipient) external;

    function nextTokenId() external view returns (uint256);
}
