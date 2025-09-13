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
    address claimer3;
    address claimer4;
    address claimer5;

    address random;
    address timelock1;
    address timelock2;

    bytes32 merkleRoot = bytes32(0x0926f535d0437dda9267fd9446f3f2a6f4d63b43412043bd309e59b7243aa854);
    bytes32 zeroMerkleRoot = bytes32(0);

    bytes32[] proof1 = [
        bytes32(0xd897d35b701a0b62f88681a2e51ef34b80085f6fb22f419e5585cc065fb5bcab),
        bytes32(0x43d03da1e2b57c76c45248e01e639a9f2d63b5ecf303ee0ca721a61ee03d8c63)
    ];

    bytes32[] proof2 = [
        bytes32(0xca7934deff796907c9ee335ce9020810e46629ceca06843d5f3c34ef83f6d0de),
        bytes32(0x491a028eeff279fd1275c464e6bc1b6859cc871ac4687cf0db23d402af4cc903)
    ];

    bytes32[] proof3 = [
        bytes32(0x8c07fe1aa4170a91ab7a0ae15a50423a84797ecee4c931c8c1ef8bb325e1a3c4),
        bytes32(0x43d03da1e2b57c76c45248e01e639a9f2d63b5ecf303ee0ca721a61ee03d8c63)
    ];

    bytes32[] proof4 = [
        bytes32(0x7c4b7c20632b423848307f50c72f941bff088dd859f787e050b26d56d4edef87),
        bytes32(0xe821671238e75016d0f0e63266a9f2f3e9c74c4e1711c0716950d50a977bcdfc),
        bytes32(0x491a028eeff279fd1275c464e6bc1b6859cc871ac4687cf0db23d402af4cc903)
    ];

    bytes32[] proof5 = [
        bytes32(0x52fde9620166090d16073b89092702f9d9ded0e2350a680cad51cd3cd64d6075),
        bytes32(0xe821671238e75016d0f0e63266a9f2f3e9c74c4e1711c0716950d50a977bcdfc),
        bytes32(0x491a028eeff279fd1275c464e6bc1b6859cc871ac4687cf0db23d402af4cc903)
    ];

    uint256 amount1 = 5000000000000000000;
    uint256 amount2 = 2500000000000000000;
    uint256 amount3 = 3000000000000000000;
    uint256 amount4 = 5000000000000000000;
    uint256 amount5 = 10000000000000000000;

    constructor() {
        owner = address(0x1);
        claimer1 = address(0x2);
        claimer2 = address(0x3);
        claimer3 = address(0x4);
        claimer4 = address(0x5);
        claimer5 = address(0x6);

        random = address(0x7);

        timelock1 = address(0x8);
        timelock2 = address(0x9);

        vm.deal(claimer1, 100 ether);
        vm.deal(claimer2, 100 ether);
    }

    // --- utilities ---

    function _deploy() internal returns (Claim claim) {
        vm.startPrank(owner);
        claim = new Claim("TEST", "TEST");
        vm.stopPrank();
    }

    // --- setTimelock (owner or current timelock), and extend (owner/timelock) ---

    function testSetTimelockNotOwner() public {
        Claim claim = _deploy();

        vm.startPrank(random);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, random));
        claim.setTimelock(timelock1);
    }

    function testSetTimelockOwnerAndTimelockPaths() public {
        Claim claim = _deploy();

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false, address(claim));
        emit Claim.TimelockSet(timelock1);
        claim.setTimelock(timelock1);
        assertEq(claim.timelock(), timelock1);

        vm.startPrank(timelock1);
        vm.expectEmit(true, false, false, false, address(claim));
        emit Claim.TimelockSet(timelock2);
        claim.setTimelock(timelock2);
        assertEq(claim.timelock(), timelock2);

        vm.startPrank(timelock2);
        vm.expectRevert(Claim.ZeroTimelockAddress.selector);
        claim.setTimelock(address(0));
    }

    // --- setMerkleRoot (owner sets merkle root) ---

    function testSetOwnerSetMerkleRoot() public {
        Claim claim = _deploy();

        vm.startPrank(owner);
        vm.expectRevert(Claim.ZeroMerkleRoot.selector);
        claim.setClaimMerkle(zeroMerkleRoot);

        vm.expectEmit(true, false, false, false, address(claim));
        emit Claim.ClaimSet(merkleRoot);
        claim.setClaimMerkle(merkleRoot);
        assertEq(claim.merkleRoot(), merkleRoot);

        vm.expectRevert(Claim.ClaimRootAlreadySet.selector);
        claim.setClaimMerkle(merkleRoot);
    }

    // --- setMerkleRoot (timelock sets merkle root) ---
    function testSetTimelockSetMerkleRoot() public {
        Claim claim = _deploy();

        vm.startPrank(owner);
        claim.setTimelock(timelock1);
        assertEq(claim.timelock(), timelock1);

        vm.startPrank(timelock1);
        claim.setClaimMerkle(merkleRoot);
        assertEq(claim.merkleRoot(), merkleRoot);
    }

    // --- claim ---
    function testClaim() public {
        Claim claim = _deploy();

        vm.startPrank(owner);
        claim.setClaimMerkle(merkleRoot);

        vm.startPrank(claimer1);

        vm.expectEmit(true, false, false, false, address(claim));
        emit Claim.Claimed(claimer1, amount1);
        claim.claim(claimer1, amount1, proof1);

        uint256 balance1 = claim.balanceOf(claimer1);
        assertEq(balance1, amount1);

        vm.expectRevert(Claim.AlreadyClaimed.selector);
        claim.claim(claimer1, amount1, proof1);

        claim.claim(claimer2, amount2, proof2);
        claim.claim(claimer3, amount3, proof3);
        claim.claim(claimer4, amount4, proof4);
        claim.claim(claimer5, amount5, proof5);

        uint256 balance2 = claim.balanceOf(claimer2);
        assertEq(balance2, amount2);

        uint256 balance3 = claim.balanceOf(claimer3);
        assertEq(balance3, amount3);

        uint256 balance4 = claim.balanceOf(claimer4);
        assertEq(balance4, amount4);

        uint256 balance5 = claim.balanceOf(claimer5);
        assertEq(balance5, amount5);
    }

    // --- recovery (all sent erc20 and erc721 tokens can be recovered by the owner) ---

    function testRecoverERC20ByOwner() public {
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
