## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --broadcast
```

With verification:

```shell
$ forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --broadcast --verify
```

Environment variables:

```shell
PRIVATE_KEY=...                 # deployer key
OWNER_ADDRESS=0x...             # optional override owner
TOKEN_ADDRESS=0x...             # optional override token
CELO_MULTISIG=0x...             # mainnet owner
BASE_MULTISIG=0x...             # mainnet owner
CELOSCAN_KEY=...                # Celo explorer API key
BASESCAN_KEY=...                # Base explorer API key
```

Deployment outputs:

```text
deployments/<chainId>.json
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
