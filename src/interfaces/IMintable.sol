// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IMintable is IERC721{
    /**
    @dev Allows composable minting contracts to check if minting is active.
    @return bool True if minting is active.
    */
    function isMintingActive() external view returns (bool);

}