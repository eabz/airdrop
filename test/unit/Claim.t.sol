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

     // --- recovery (all sent erc20 and erc721 tokens can be recovered by the owner) ---

    function testRecoverERC20ByOwner() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Claim claim = _deploy();

        vm.startPrank(claimer1);
        MockERC20 erc20 = new MockERC20("MockERC20", "MockERC20", 1_000_000 ether);

        assertEq(erc20.balanceOf(address(claimer1)), 1_000_000 ether);

        uint256 amount = 100_000 ether;

        assertEq(erc20.balanceOf(address(claim)), 0);
        erc20.transfer(address(claim), amount);

        assertEq(erc20.balanceOf(address(claim)), amount);

        vm.startPrank(owner);
        claim.recoverERC20(address(erc20), claimer1, amount);

        assertEq(erc20.balanceOf(address(claim)), 0);
        assertEq(erc20.balanceOf(claimer1), 1_000_000 ether);
    }

    function testRecoverERC721ByOwner() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Claim claim = _deploy();

        vm.startPrank(claimer1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        MockERC721 erc721 = new MockERC721("MockERC721", "MockERC721", tokenIds);

        assertEq(erc721.ownerOf(1), address(claimer1));

        erc721.transferFrom(address(claimer1), address(claim), 1);
        assertEq(erc721.ownerOf(1), address(claim));

        vm.startPrank(owner);
        claim.recoverERC721(address(erc721), claimer1, 1, "");

        assertEq(erc721.ownerOf(1), address(claimer1));
    }
}
