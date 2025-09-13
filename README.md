# Airdrop Boilerplate

Airdrop Boilerplate provides a minimal set of smart contracts to run a simple ICO flow:
participants deposit ETH into a vault, and later claim their allocated ERC20 tokens through a Merkle tree–based distribution.

It includes:
- A Vault contract to handle ETH contributions, withdrawals, and lifecycle management.
- A Claim contract that verifies Merkle proofs to securely distribute ERC20 tokens to eligible addresses.
- Example mocks (ERC20 and ERC721) for testing and development.

## Requirements
- [foundry](https://getfoundry.sh/)
- [bun](https://bun.sh/)

## Install dependencies

To install all the forge dependencies run:

```bash
forge install
```

Make sure also install dependencies for testing and utilities:

```bash
bun install
```

## Build

To compile the contracts, simply run:
```bash
forge build
```

## Unit testing
To run the unit testing framework run:
```bash
forge test
```

If you want to check the code coverage you can optionally use:
```bash
forge coverage
```