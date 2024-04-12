# TenderSwap - Unified Liquidity for Staked Assets 🌊 [![Open in Gitpod][gitpod-badge]][gitpod] [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![License: MIT][license-badge]][license]

[gitpod]: https://gitpod.io/#https://github.com/Tenderize/tenderswap
[gitpod-badge]: https://img.shields.io/badge/Gitpod-Open%20in%20Gitpod-FFB45B?logo=gitpod
[gha]: https://github.com/Tenderize/tenderswap/actions
[gha-badge]: https://github.com/Tenderize/tenderswap/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

## Overview

For an overview of the mechanics and implemented mathematics in TenderSwap, check following sources:

- [White Paper](https://whitepaper.tenderize.me/core-architecture/tenderswap)
- [Yellow Paper](https://whitepaper.tenderize.me/tenderswap/yellow-paper)

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
forge clean
```

### Compile

Compile the contracts:

```sh
forge build
```

### Coverage

Get a test coverage report:

```sh
forge coverage
```

### Deploy

Deployments and upgrades can through the `SwapFactory` contract for indexing purposes on the Tenderize Subgraph.

TenderSwap can also be deployed standlone following the same pattern as the `SwapFactory` contract.

### Format

Format the contracts:

```sh
forge fmt
```

or

```sh
yarn lint:sol
```

Format other files:

```sh
yarn prettier:write
```

### Gas Usage

Get a gas report:

```sh
forge test --gas-report
```

### Lint

Lint the contracts:

```sh
pnpm lint
```

### Test

Run the tests:

```sh
forge test
```

## Notes

1. Foundry uses [git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) to manage dependencies. For
   detailed instructions on working with dependencies, please refer to the
   [guide](https://book.getfoundry.sh/projects/dependencies.html) in the book
2. You don't have to create a `.env` file, but filling in the environment variables may be useful when debugging and
   testing against a fork.

## Related Efforts

- [abigger87/femplate](https://github.com/abigger87/femplate)
- [cleanunicorn/ethereum-smartcontract-template](https://github.com/cleanunicorn/ethereum-smartcontract-template)
- [foundry-rs/forge-template](https://github.com/foundry-rs/forge-template)
- [FrankieIsLost/forge-template](https://github.com/FrankieIsLost/forge-template)

## License

This project is licensed under MIT.
