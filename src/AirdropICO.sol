// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AirdropICO
 * @notice Minimal ETH ICO vault that:
 *         1) Receives ETH while active and emits a Contributed event per deposit
 *         2) Owner or timelock can explicitly close the ICO to stop further contributions
 *         3) Owner may withdraw the contract balance at any time
 * @dev    Designed to pair with an off-chain indexer that reads Contributed events
 *         and builds a Merkle tree for an airdrop token. Uses custom errors for gas.
 */
contract AirdropICO is Ownable {
    // =============================================== Errors =========================================================

    /// @dev Thrown when endTime <= startTime.
    error BadTimeWindow();

    /// @dev Thrown when contributions are attempted before startTime.
    error IcoNotStarted();

    /// @dev Thrown when contributions are attempted after endTime.
    error IcoEnded();

    /// @dev Thrown when contributions are attempted after an explicit close.
    error IcoClosed();

    /// @dev Thrown when close is attempted more than once.
    error AlreadyClosed();

    /// @dev Thrown when no ETH is available to withdraw.
    error NoFundsToWithdraw();

    /// @dev Thrown when the low-level ETH transfer fails.
    error WithdrawFailed();

    /// @dev Thrown when trying to extend the end time with an invalid value.
    error BadNewEndTime();

    /// @dev Thrown when msg.value == 0 for a contribution.
    error ZeroContribution();

    // ============================================== Events ==========================================================

    /// @notice Emitted for each successful contribution.
    /// @param contributor The address that sent ETH.
    /// @param amount The amount of ETH received (in wei).
    event Contributed(address indexed contributor, uint256 amount);

    /// @notice Emitted when the owner withdraws the full balance.
    /// @param to The recipient of the withdrawal.
    /// @param amount The amount of ETH withdrawn.
    event Withdraw(address indexed to, uint256 amount);

    /// @notice Emitted when the timelock address changes.
    /// @param timelock The new timelock address (may be address(0) to disable).
    event TimelockSet(address timelock);

    /// @notice Emitted when the ICO is explicitly closed by the owner.
    /// @param totalRaised Total ETH raised at the time of closing (in wei).
    event Closed(uint256 totalRaised);

    /// @notice Emitted when the endTime is extended (before closing).
    /// @param newEndTime The new end time (unix seconds).
    event EndTimeExtended(uint64 newEndTime);

    // ============================================== Storage =========================================================

    /**
     * @notice ICO start time (unix seconds, inclusive).
     * @dev    Immutable to reduce gas on reads.
     */
    uint64 public immutable startTime;

    /**
     * @notice ICO end time.
     * @dev    Immutable to reduce gas on reads unless extended (see extendEndTime()).
     *         We keep a mutable mirror to support a one-time extension. Reads prefer `_endTime`.
     */
    uint64 private _endTime;

    /**
     * @notice Whether the ICO has been explicitly closed.
     */
    bool public closed;

    /**
     * @notice Optional address allowed to call {closeIco} in addition to the owner
     *         (e.g., a timelock/governance executor). Zero address disables.
     */
    address public timelock;

    /**
     * @notice Total ETH raised (wei).
     */
    uint256 public totalRaised;

    /**
     * @notice Sum of contributions per address (wei). Useful for UX/reconciliation.
     */
    mapping(address => uint256) public contributions;

    // ============================================== Constructor =====================================================

    /**
     * @param _startTimestamp   ICO start time (unix seconds).
     * @param _endTimestamp     ICO end time (unix seconds). Must be > _startTimestamp.
     */
    constructor(uint64 _startTimestamp, uint64 _endTimestamp) TokenRecover(msg.sender) {
        if (_endTimestamp <= _startTimestamp) revert BadTimeWindow();
        startTime = _startTimestamp;
        _endTime = _endTimestamp;
    }

    // ============================================== Modifiers =======================================================

    /// @dev Reverts before start.
    modifier whenStarted() {
        if (block.timestamp < startTime) revert IcoNotStarted();
        _;
    }

    /// @dev Reverts if explicitly closed.
    modifier whenNotClosed() {
        if (closed) revert IcoClosed();
        _;
    }

    /// @dev Reverts after end time.
    modifier whenNotEnded() {
        if (block.timestamp >= _endTime) revert IcoEnded();
        _;
    }

    // =============================================== Receive / Contribute ==========================================

    /**
     * @notice Receive ETH directly to contribute while the ICO is active.
     */
    receive() external payable {
        _contribute();
    }

    /**
     * @notice Contribute ETH to the ICO while active.
     */
    function contribute() external payable {
        _contribute();
    }

    /// @dev Common contribution path with lifecycle checks.
    function _contribute() internal whenNotClosed whenStarted whenNotEnded {
        if (msg.value == 0) revert ZeroContribution();
        contributions[msg.sender] += msg.value;
        totalRaised += msg.value;
        emit Contributed(msg.sender, msg.value);
    }

    // =============================================== Admin controls =================================================

    /**
     * @notice Set or clear the timelock address that can also close/extend the ICO. Callable by owner or current timelock.
     * @param _timelock New timelock (address(0) to disable).
     */
    function setTimelock(address _timelock) external {
        if (msg.sender != owner() && msg.sender != timelock) {
            revert Ownable.OwnableUnauthorizedAccount(msg.sender);
        }
        timelock = _timelock;
        emit TimelockSet(_timelock);
    }

    /**
     * @notice Explicitly close the ICO to stop further contributions. Can be called once by the owner or timelock.
     */
    function closeIco() external {
        if (msg.sender != owner() && msg.sender != timelock) {
            revert Ownable.OwnableUnauthorizedAccount(msg.sender);
        }
        if (closed) revert AlreadyClosed();
        closed = true;
        emit Closed(totalRaised);
    }

    /**
     * @notice One-time extension of the end time before closing. Callable by owner or timelock.
     * @param newEndTime New end time (must be > current end time and in the future).
     */
    function extendEndTime(uint64 newEndTime) external {
        if (msg.sender != owner() && msg.sender != timelock) {
            revert Ownable.OwnableUnauthorizedAccount(msg.sender);
        }
        if (closed) revert AlreadyClosed();
        if (newEndTime <= _endTime || newEndTime <= block.timestamp) {
            revert BadNewEndTime();
        }
        _endTime = newEndTime;
        emit EndTimeExtended(newEndTime);
    }

    /**
     * @notice Withdraw all ETH.
     * @param to Recipient address for the funds.
     */
    function withdraw(address payable to) external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoFundsToWithdraw();
        (bool ok,) = to.call{value: balance}("");
        if (!ok) revert WithdrawFailed();
        emit Withdraw(to, balance);
    }

    // =============================================== Views ==========================================================

    /**
     * @notice Current end time (may be extended).
     */
    function endTime() external view returns (uint64) {
        return _endTime;
    }

    /**
     * @notice Whether the ICO is currently active (not closed, started, not ended).
     */
    function isActive() external view returns (bool) {
        return !closed && block.timestamp >= startTime && block.timestamp < _endTime;
    }
}
