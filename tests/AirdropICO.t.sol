// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AirdropICO} from "../contracts/AirdropICO.sol";
import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RevertingReceiver {
    // any ETH transfer to this contract reverts
    receive() external payable {
        revert("nope");
    }
}

contract AirdropICO_Test is Test {
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

    function _deploy(
        uint64 start,
        uint64 end
    ) internal returns (AirdropICO ico) {
        vm.startPrank(owner);
        ico = new AirdropICO(start, end);
        vm.stopPrank();
    }

    // --- constructor ---

    function testConstructor() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(currentTimestamp, currentTimestamp + 3600);
        require(ico.startTime() == currentTimestamp, "start mismatch");
        require(ico.endTime() == currentTimestamp + 3600, "end mismatch");
    }

    function testConstructorRevertsBadTimeWindow() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        vm.expectRevert(AirdropICO.BadTimeWindow.selector);

        new AirdropICO(currentTimestamp + 100, currentTimestamp + 50);
    }

    // --- contribute before/after, via function and receive() ---

    function testContributeBeforeStartReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(
            currentTimestamp + 100,
            currentTimestamp + 1000
        );

        vm.expectRevert(AirdropICO.IcoNotStarted.selector);
        address(ico).call{value: 1}(abi.encodeWithSignature("contribute()"));

        vm.expectRevert(AirdropICO.IcoNotStarted.selector);
        address(ico).call{value: 1}("");
    }

    function testContributeZeroReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(
            currentTimestamp + 100,
            currentTimestamp + 1000
        );

        vm.expectRevert(AirdropICO.ZeroContribution.selector);
        address(ico).call{value: 0}(abi.encodeWithSignature("contribute()"));
    }

    function testContributeDuringWindowSuccessAndAccounting() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(contributor1);
        vm.expectEmit(true, true, false, false, address(ico));
        emit AirdropICO.Contributed(contributor1, 1 ether);
        (bool ok1, ) = address(ico).call{value: 1 ether}(
            abi.encodeWithSignature("contribute()")
        );
        assertTrue(ok1);

        vm.expectEmit(true, true, false, false, address(ico));
        emit AirdropICO.Contributed(contributor1, 123);
        (bool ok2, ) = address(ico).call{value: 123}("");
        assertTrue(ok2);

        assertEq(ico.totalRaised(), 1 ether + 123);
        assertEq(ico.contributions(address(contributor1)), 1 ether + 123);
    }

    function testAfterEndReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.expectRevert(AirdropICO.IcoEnded.selector);
        address(ico).call{value: 1}(abi.encodeWithSignature("contribute()"));

        vm.expectRevert(AirdropICO.IcoEnded.selector);
        address(ico).call{value: 1}("");
    }

    // --- close (owner/timelock), and post-close behavior ---

    function testCloseByOwnerAndTimelock() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(random);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                random
            )
        );
        ico.closeIco();

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false, address(ico));
        emit AirdropICO.TimelockSet(timelock1);
        ico.setTimelock(timelock1);

        vm.startPrank(timelock1);
        vm.expectEmit(true, false, false, false, address(ico));
        emit AirdropICO.Closed(0);
        ico.closeIco();
        assertFalse(ico.isActive());

        vm.expectRevert(AirdropICO.AlreadyClosed.selector);
        ico.closeIco();
    }

    function testContributeAfterCloseReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false, address(ico));
        emit AirdropICO.Closed(0);
        ico.closeIco();

        vm.expectRevert(AirdropICO.IcoClosed.selector);
        address(ico).call{value: 1}(abi.encodeWithSignature("contribute()"));

        vm.expectRevert(AirdropICO.IcoClosed.selector);
        address(ico).call{value: 1}("");
    }

    // --- setTimelock (owner or current timelock), and extend (owner/timelock) ---

    function testSetTimelockOwnerAndTimelockPaths() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false, address(ico));
        emit AirdropICO.TimelockSet(timelock1);
        ico.setTimelock(timelock1);
        assertEq(ico.timelock(), timelock1);

        vm.startPrank(timelock1);
        vm.expectEmit(true, false, false, false, address(ico));
        emit AirdropICO.TimelockSet(timelock2);
        ico.setTimelock(timelock2);
        assertEq(ico.timelock(), timelock2);

        vm.startPrank(timelock2);
        vm.expectEmit(true, false, false, false, address(ico));
        emit AirdropICO.TimelockSet(address(0));
        ico.setTimelock(address(0));
        assertEq(ico.timelock(), address(0));
    }

    function testExtendEndTimeOwnerAndTimelockPathsAndGuards() public {
        uint64 currentTimestamp = uint64(block.timestamp) + 10;
        AirdropICO ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        // owner extends
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false, address(ico));
        emit AirdropICO.EndTimeExtended(currentTimestamp + 2000);
        ico.extendEndTime(currentTimestamp + 2000);
        assertEq(ico.endTime(), currentTimestamp + 2000);

        ico.setTimelock(timelock1);
        vm.startPrank(timelock1);
        vm.expectEmit(true, false, false, false, address(ico));
        emit AirdropICO.EndTimeExtended(currentTimestamp + 2500);
        ico.extendEndTime(currentTimestamp + 2500);
        assertEq(ico.endTime(), currentTimestamp + 2500);

        vm.startPrank(owner);
        vm.expectRevert(AirdropICO.BadNewEndTime.selector);
        ico.extendEndTime(currentTimestamp + 2500);

        vm.expectRevert(AirdropICO.BadNewEndTime.selector);
        ico.extendEndTime(currentTimestamp + 2400);

        vm.expectRevert(AirdropICO.BadNewEndTime.selector);
        ico.extendEndTime(currentTimestamp - 10);

        ico.closeIco();
        vm.expectRevert(AirdropICO.AlreadyClosed.selector);
        ico.extendEndTime(currentTimestamp + 3000);
    }

    function testWithdrawFromNotOwner() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(random);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                random
            )
        );
        ico.withdraw(payable(random));
    }

    function testWithdrawNoFundsReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(owner);
        vm.expectRevert(AirdropICO.NoFundsToWithdraw.selector);
        ico.withdraw(payable(owner));
    }

    function testWithdrawTransfersBalanceAndEmits() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(contributor1);
        address(ico).call{value: 1 ether}(
            abi.encodeWithSignature("contribute()")
        );

        vm.startPrank(owner);
        uint256 beforeBalance = address(owner).balance;

        vm.expectEmit(true, false, false, false, address(ico));
        emit AirdropICO.Withdraw(owner, 1 ether);
        address(ico).call(
            abi.encodeWithSignature("withdraw(address)", address(owner))
        );

        uint256 afterBal = address(owner).balance;
        assertGe(afterBal, beforeBalance + 1 ether);
        assertEq(address(ico).balance, 0);
    }

    function testWithdrawFailsWhenReceiverReverts() public {
        uint64 currentTimestamp = uint64(block.timestamp);
        AirdropICO ico = _deploy(currentTimestamp, currentTimestamp + 1000);

        vm.startPrank(contributor1);
        address(ico).call{value: 1 ether}(
            abi.encodeWithSignature("contribute()")
        );

        RevertingReceiver bad = new RevertingReceiver();
        vm.expectRevert(AirdropICO.WithdrawFailed.selector);

        address(ico).call(
            abi.encodeWithSignature("withdraw(address)", address(bad))
        );
    }
}
