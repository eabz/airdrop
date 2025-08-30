// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Claim} from "src/Claim.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockERC721} from "src/mocks/MockERC721.sol";

contract Claim_Test is Test {
    address owner;
    address claimer1;
    address claimer2;
    address random;

    constructor() {
        owner = address(0x1);
        claimer1 = address(0x2);
        claimer2 = address(0x3);
        random = address(0x6);

        vm.deal(claimer1, 100 ether);
        vm.deal(claimer2, 100 ether);
    }

    // --- utilities ---

    function _deploy() internal returns (Claim claim) {
        vm.startPrank(owner);
        claim = new Claim("TEST", "TEST");
        vm.stopPrank();
    }
}
