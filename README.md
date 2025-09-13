# Airdrop Boilerplate

![Unit and Integration Tests](https://github.com/eabz/airdrop/actions/workflows/test.yml/badge.svg)

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

To install Foundry dependencies:
```bash
forge install
```

To install JavaScript/TypeScript dependencies for testing and utilities:

```bash
bun install
```

## Build

Compile the contracts with:
```bash
forge build
```

## Unit testing
Run the unit tests:

```bash
forge test
```

To check code coverage:
```bash
forge coverage
```

## Integration testing
Integration tests require Bun dependencies and generated TypeChain types.

1. Install dependencies:
```bash
bun install
```

2. Build contracts and generate types:

```bash
bun run build
```

3. Run the integration test:

```bash
bun integration
```