// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title Claim
 * @notice ERC20 token with Merkle-claim airdrop.
 *         1. Owner or timelock sets a Merkle root of (index, account, amount).
 *         2. Users claim once with a Merkle proof; token is minted on claim.
 *         3. Double-claims prevented via a boolean map.
 * @dev    Pair this with your off-chain indexer that reads Vault.Contributed events,
 *         sums by address, builds the Merkle tree, and sets the root here.
 */
contract Claim is ERC20, Ownable {
    // ============================= Errors =============================

    /// @dev Claim root already set (single-round).
    error ClaimRootAlreadySet();

    /// @dev Claim already processed for this index.
    error AlreadyClaimed();

    /// @dev Merkle proof fails verification.
    error InvalidProof();

    /// @dev Unauthorized caller (mirrors Ownable's pattern for non-owner/non-timelock).
    error Unauthorized(address caller);

    // ============================= Events =============================

    /// @notice Emitted when the airdrop root is set.
    event ClaimSet(bytes32 indexed merkleRoot);

    /// @notice Emitted when a claim is executed.
    event Claimed(uint256 indexed index, address indexed account, uint256 amount);

    /// @notice Emitted when timelock is updated.
    event TimelockSet(address timelock);

    // ============================= Storage ============================

    /// @notice Merkle root for allocations keccak256(abi.encode(index, account, amount)).
    bytes32 public merkleRoot;

    /// @notice Simple map to check for claimed indexes.
    mapping(uint256 => bool) private _claimed;

    /// @notice Optional address allowed to manage airdrop root alongside the owner.
    address public timelock;

    // ============================ Constructor =========================

    /**
     * @param name_   ERC20 name
     * @param symbol_ ERC20 symbol
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {}

    // ============================ Admin ===============================

    /**
     * @notice Set the Merkle airdrop root. Callable once by owner or timelock.
     * @param root The Merkle root of (index, account, amount) leaves.
     */
    function setClaimMerkle(bytes32 root) external {
        if (msg.sender != owner() && msg.sender != timelock) revert Unauthorized(msg.sender);
        if (merkleRoot != bytes32(0)) revert ClaimRootAlreadySet();
        merkleRoot = root;
        emit ClaimSet(root);
    }

    /**
     * @notice Set or clear the timelock address (owner or current timelock).
     * @param _timelock New timelock address (0 to disable).
     */
    function setTimelock(address _timelock) external {
        if (msg.sender != owner() && msg.sender != timelock) revert Unauthorized(msg.sender);
        timelock = _timelock;
        emit TimelockSet(_timelock);
    }

    // ============================ Claim ===============================

    /**
     * @notice Returns true if `index` has already been claimed.
     */
    function isClaimed(uint256 index) public view returns (bool) {
        return _claimed[index];
    }

    /**
     * @notice Claim tokens with a Merkle proof and mint to `account`.
     * @param index  Index in the Merkle tree (unique per leaf).
     * @param account Claimer address contained in the leaf.
     * @param amount  Token amount contained in the leaf (wei-scale if 1:1 with ETH wei).
     * @param proof   Merkle proof for keccak256(abi.encode(index, account, amount)).
     */
    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata proof) external {
        if (isClaimed(index)) revert AlreadyClaimed();

        bytes32 leaf = keccak256(abi.encode(index, account, amount));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert InvalidProof();

        _claimed[index] = true;
        _mint(account, amount);

        emit Claimed(index, account, amount);
    }

    // =============================================== Token Recovery ==========================================================

    // https://github.com/vittominacori/eth-token-recover/blob/master/contracts/ERC20Recover.sol#L29
    function recoverERC20(address tokenAddress, address tokenReceiver, uint256 tokenAmount) public virtual onlyOwner {
        _recoverERC20(tokenAddress, tokenReceiver, tokenAmount);
    }

    // https://github.com/vittominacori/eth-token-recover/blob/master/contracts/ERC721Recover.sol#L30
    function recoverERC721(address tokenAddress, address tokenReceiver, uint256 tokenId, bytes memory data)
        public
        virtual
        onlyOwner
    {
        _recoverERC721(tokenAddress, tokenReceiver, tokenId, data);
    }

    // https://github.com/vittominacori/eth-token-recover/blob/master/contracts/recover/RecoverERC20.sol#L22
    function _recoverERC20(address tokenAddress, address tokenReceiver, uint256 tokenAmount) internal virtual {
        IERC20(tokenAddress).transfer(tokenReceiver, tokenAmount);
    }

    // https://github.com/vittominacori/eth-token-recover/blob/master/contracts/recover/RecoverERC20.sol#L22
    function _recoverERC721(address tokenAddress, address tokenReceiver, uint256 tokenId, bytes memory data)
        internal
        virtual
    {
        IERC721(tokenAddress).safeTransferFrom(address(this), tokenReceiver, tokenId, data);
    }

    // Make sure the contract reverts if someone tries to send ETH
    receive() external payable {
        revert("nope");
    }
}
