// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vault} from "../src/Vault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {MockERC721} from "src/mocks/MockERC721.sol";

contract RevertingReceiver {
    // any ETH transfer to this contract reverts
    receive() external payable {
        revert("nope");
    }
}

contract Vault_Test is Test {
    address owner;
    address contributor1;
    address contributor2;
    address timelock1;
    address timelock2;
    address random;

    constructor() {
        owner = address(0x1);
        contributor1 = address(0x2);
        contributor2 = address(0x3);
        timelock1 = address(0x4);
        timelock2 = address(0x5);
        random = address(0x6);

        vm.deal(contributor1, 100 ether);
        vm.deal(contributor2, 100 ether);
    }

    // --- utilities ---

    function _deploy(uint64 start, uint64 end) internal returns (Vault ico) {
        vm.startPrank(owner);
        ico = new Vault(start, end);
        vm.stopPrank();
    }

    // --- constructor ---

    function testConstructor() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 3600);
        require(ico.startTime() == currentTimestamp, "start mismatch");
        require(ico.endTime() == currentTimestamp + 3600, "end mismatch");
    }

    function testConstructorRevertsBadTimeWindow() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        vm.expectRevert(Vault.BadTimeWindow.selector);

        new Vault(currentTimestamp + 100, currentTimestamp + 50);
    }

    // --- contribute before/after, via function and receive() ---

    function testContributeBeforeStartReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp + 100, currentTimestamp + 1000);

        vm.expectRevert(Vault.IcoNotStarted.selector);
        (bool ok1,) = address(ico).call{value: 1}(abi.encodeWithSignature("contribute()"));
        assertTrue(ok1);

        vm.expectRevert(Vault.IcoNotStarted.selector);
        (bool ok2,) = address(ico).call{value: 1}("");
        assertTrue(ok2);
    }

    function testContributeZeroReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp + 100, currentTimestamp + 1000);

        vm.expectRevert(Vault.ZeroContribution.selector);
        (bool ok1,) = address(ico).call{value: 0}(abi.encodeWithSignature("contribute()"));
        assertFalse(ok1);
    }

    function testContributeDuringWindowSuccessAndAccounting() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(contributor1);
        vm.expectEmit(true, true, false, false, address(ico));
        emit Vault.Contributed(contributor1, 1 ether);
        (bool ok1,) = address(ico).call{value: 1 ether}(abi.encodeWithSignature("contribute()"));
        assertTrue(ok1);

        vm.expectEmit(true, true, false, false, address(ico));
        emit Vault.Contributed(contributor1, 123);
        (bool ok2,) = address(ico).call{value: 123}("");
        assertTrue(ok2);

        assertEq(ico.totalRaised(), 1 ether + 123);
        assertEq(ico.contributions(address(contributor1)), 1 ether + 123);
    }

    function testAfterEndReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.expectRevert(Vault.IcoEnded.selector);
        (bool ok1,) = address(ico).call{value: 1}(abi.encodeWithSignature("contribute()"));
        assertFalse(ok1);

        vm.expectRevert(Vault.IcoEnded.selector);
        (bool ok2,) = address(ico).call{value: 1}("");
        assertFalse(ok2);
    }

    // --- close (owner/timelock), and post-close behavior ---

    function testCloseByOwnerAndTimelock() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(random);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, random));
        ico.closeIco();

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false, address(ico));
        emit Vault.TimelockSet(timelock1);
        ico.setTimelock(timelock1);

        vm.startPrank(timelock1);
        vm.expectEmit(true, false, false, false, address(ico));
        emit Vault.Closed(0);
        ico.closeIco();
        assertFalse(ico.isActive());

        vm.expectRevert(Vault.AlreadyClosed.selector);
        ico.closeIco();
    }

    function testContributeAfterCloseReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false, address(ico));
        emit Vault.Closed(0);
        ico.closeIco();

        vm.expectRevert(Vault.IcoClosed.selector);
        (bool ok1,) = address(ico).call{value: 1}(abi.encodeWithSignature("contribute()"));
        assertFalse(ok1);

        vm.expectRevert(Vault.IcoClosed.selector);
        (bool ok2,) = address(ico).call{value: 1}("");
        assertFalse(ok2);
    }

    // --- setTimelock (owner or current timelock), and extend (owner/timelock) ---

    function testSetTimelockOwnerAndTimelockPaths() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false, address(ico));
        emit Vault.TimelockSet(timelock1);
        ico.setTimelock(timelock1);
        assertEq(ico.timelock(), timelock1);

        vm.startPrank(timelock1);
        vm.expectEmit(true, false, false, false, address(ico));
        emit Vault.TimelockSet(timelock2);
        ico.setTimelock(timelock2);
        assertEq(ico.timelock(), timelock2);

        vm.startPrank(timelock2);
        vm.expectRevert(Vault.ZeroTimelockAddress.selector);
        ico.setTimelock(address(0));
    }

    function testExtendEndTimeOwnerAndTimelockPathsAndGuards() public {
        uint64 currentTimestamp = uint64(block.timestamp) + 10;
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        // owner extends
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false, address(ico));
        emit Vault.EndTimeExtended(currentTimestamp + 2000);
        ico.extendEndTime(currentTimestamp + 2000);
        assertEq(ico.endTime(), currentTimestamp + 2000);

        ico.setTimelock(timelock1);
        vm.startPrank(timelock1);
        vm.expectEmit(true, false, false, false, address(ico));
        emit Vault.EndTimeExtended(currentTimestamp + 2500);
        ico.extendEndTime(currentTimestamp + 2500);
        assertEq(ico.endTime(), currentTimestamp + 2500);

        vm.startPrank(owner);
        vm.expectRevert(Vault.BadNewEndTime.selector);
        ico.extendEndTime(currentTimestamp + 2500);

        vm.expectRevert(Vault.BadNewEndTime.selector);
        ico.extendEndTime(currentTimestamp + 2400);

        vm.expectRevert(Vault.BadNewEndTime.selector);
        ico.extendEndTime(currentTimestamp - 10);

        ico.closeIco();
        vm.expectRevert(Vault.AlreadyClosed.selector);
        ico.extendEndTime(currentTimestamp + 3000);
    }

    function testWithdrawFromNotOwner() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(random);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, random));
        ico.withdraw(payable(random));
    }

    function testWithdrawNoFundsReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(owner);
        vm.expectRevert(Vault.NoFundsToWithdraw.selector);
        ico.withdraw(payable(owner));
    }

    function testWithdrawTransfersBalanceAndEmits() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(contributor1);
        (bool ok1,) = address(ico).call{value: 1 ether}(abi.encodeWithSignature("contribute()"));
        assertTrue(ok1);

        vm.startPrank(owner);
        uint256 beforeBalance = address(owner).balance;

        vm.expectEmit(true, false, false, false, address(ico));
        emit Vault.Withdraw(owner, 1 ether);
        (bool ok2,) = address(ico).call(abi.encodeWithSignature("withdraw(address)", address(owner)));
        assertTrue(ok2);

        uint256 afterBal = address(owner).balance;
        assertGe(afterBal, beforeBalance + 1 ether);
        assertEq(address(ico).balance, 0);
    }

    function testWithdrawFailsWhenReceiverReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(contributor1);
        (bool ok1,) = address(ico).call{value: 1 ether}(abi.encodeWithSignature("contribute()"));
        assertTrue(ok1);

        RevertingReceiver bad = new RevertingReceiver();
        vm.expectRevert(Vault.WithdrawFailed.selector);

        (bool ok2,) = address(ico).call(abi.encodeWithSignature("withdraw(address)", address(bad)));
        assertFalse(ok2);
    }

    // --- renounce (renounce is only available with a timelock set) ---

    function testRenounceRevertsWithoutTimelock() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(owner);
        vm.expectRevert(Vault.NoTimelockAddressSet.selector);
        ico.renounceOwnership();
    }

    function testRenounceSucceedsAfterSettingTimelock() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(owner);

        ico.setTimelock(timelock1);
        assertEq(ico.timelock(), timelock1);

        ico.renounceOwnership();
        assertEq(ico.owner(), address(0));
    }

    // --- recovery (all sent erc20 and erc721 tokens can be recovered by the owner) ---

    function testRecoverERC20ByOwner() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(contributor1);
        MockERC20 erc20 = new MockERC20("MockERC20", "MockERC20", 1_000_000 ether);

        assertEq(erc20.balanceOf(address(contributor1)), 1_000_000 ether);

        uint256 amount = 100_000 ether;

        assertEq(erc20.balanceOf(address(ico)), 0);
        erc20.transfer(address(ico), amount);

        assertEq(erc20.balanceOf(address(ico)), amount);

        vm.startPrank(owner);
        ico.recoverERC20(address(erc20), contributor1, amount);

        assertEq(erc20.balanceOf(address(ico)), 0);
        assertEq(erc20.balanceOf(contributor1), 1_000_000 ether);
    }

    function testRecoverERC721ByOwner() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        Vault ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(contributor1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        MockERC721 erc721 = new MockERC721("MockERC721", "MockERC721", tokenIds);

        assertEq(erc721.ownerOf(1), address(contributor1));

        erc721.transferFrom(address(contributor1), address(ico), 1);
        assertEq(erc721.ownerOf(1), address(ico));

        vm.startPrank(owner);
        ico.recoverERC721(address(erc721), contributor1, 1, "");

        assertEq(erc721.ownerOf(1), address(contributor1));
    }
}
