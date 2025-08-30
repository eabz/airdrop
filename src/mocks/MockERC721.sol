// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    constructor(string memory name, string memory symbol, uint256[] memory tokenIds) ERC721(name, symbol) {
        uint256 tokensAmount = tokenIds.length;

        require(tokensAmount <= 10, "Tokens to mint cannot exceed 10 tokens");
        for (uint256 i = 0; i < tokensAmount; i++) {
            _mint(msg.sender, tokenIds[i]);
        }
    }
}
