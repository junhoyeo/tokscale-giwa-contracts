# Tokscale contracts on GIWA Sepolia

This repository is the public source and deployment record for the smart-contract
infrastructure Tokscale PoC deployed on **GIWA Sepolia** (`eip155:91342`). Tokscale
is a verified AI gateway: it routes AI requests, accepts x402-shaped payments,
and issues receipts that can become verifiable work history.

## Submission links

| Contract or evidence | GIWA Sepolia explorer (Source Verified) |
| --- | --- |
| Tokscale Test USD (`tUSD`) | [`0x58d5608e89b5c1c3b96481a199756b1a292061a9`](https://sepolia-explorer.giwa.io/address/0x58d5608e89b5c1c3b96481a199756b1a292061a9) |
| tUSD deployer | [`0x016af5632b7d2d3bbd2a6e589b65e828d1a5b125`](https://sepolia-explorer.giwa.io/address/0x016af5632b7d2d3bbd2a6e589b65e828d1a5b125) |
| x402 Upto Permit2 Proxy | [`0x4020A4f3b7b90ccA423B9fabCc0CE57C6C240002`](https://sepolia-explorer.giwa.io/address/0x4020A4f3b7b90ccA423B9fabCc0CE57C6C240002) |
| x402 Exact Permit2 Proxy | [`0x402085c248EeA27D92E8b30b2C58ed07f9E20001`](https://sepolia-explorer.giwa.io/address/0x402085c248EeA27D92E8b30b2C58ed07f9E20001) |
| ERC-6492 UniversalSigValidator | [`0xdAcD51A54883eb67D95FAEb2BBfdC4a9a6BD2a3B`](https://sepolia-explorer.giwa.io/address/0xdAcD51A54883eb67D95FAEb2BBfdC4a9a6BD2a3B) |
| ERC-3009 `exact` settlement, 1.0 tUSD | TX [`0xad1a2f7b...fcb9f8`](https://sepolia-explorer.giwa.io/tx/0xad1a2f7b5aff4033e7779437ec487e8b51eb8170ba1c6c8cc971f6de37fcb9f8) |
| Permit2 `upto` settlement, maximum 1.5 / actual 1.0 tUSD | TX [`0x93bf1e60...cd274`](https://sepolia-explorer.giwa.io/tx/0x93bf1e60ce1fa0559603111f96cfcdd081eab17b71fb406a32f88ca1562cd274) |

## What is deployed

GIWA did not ship an x402 facilitator or the fixed-address contracts its
pinned facilitator requires. Tokscale supplied the missing deployment layer,
then settled both `exact` and `upto` test transactions on public GIWA Sepolia.

| Component | Deployment | Evidence in this repository |
| --- | --- | --- |
| `tUSD` | Tokscale-authored ERC-20 test asset with the EIP-3009 authorization subset | [source](src/TUSD.sol), [deployment record](deployments/giwa-sepolia-tusd-v1.json) |
| `TUSDDeployer` | Tokscale-authored deterministic deployer for `tUSD` | [source](src/TUSDDeployer.sol), [deployment record](deployments/giwa-sepolia-tusd-v1.json) |
| `x402UptoPermit2Proxy` | Canonical x402 fixed-address proxy | [upstream source lock](upstream/x402/SOURCE.lock), [deployment record](deployments/giwa-sepolia-x402-upto-v1.json) |
| `x402ExactPermit2Proxy` | Canonical x402 fixed-address startup prerequisite | [upstream source lock](upstream/x402/SOURCE.lock), [deployment record](deployments/giwa-sepolia-x402-facilitator-prereqs-v1.json) |
| `UniversalSigValidator` | ERC-6492 signature validator required by the pinned facilitator | [Sourcify provenance](upstream/erc6492/PROVENANCE.json), [deployment record](deployments/giwa-sepolia-x402-facilitator-prereqs-v1.json) |

The contracts are deployed at canonical CREATE2 addresses. Each deployment
manifest pins its transaction, block, init-code or upstream provenance, and
observed runtime code hash.

## Public verification status

The GIWA Sepolia Explorer reports all contracts deployed by Tokscale for this
testnet evidence as source-verified:

- [`tUSD` verified contract](https://sepolia-explorer.giwa.io/address/0x58d5608e89b5c1c3b96481a199756b1a292061a9)
- [`TUSDDeployer` verified contract](https://sepolia-explorer.giwa.io/address/0x016af5632b7d2d3bbd2a6e589b65e828d1a5b125)
- [`x402UptoPermit2Proxy` verified contract](https://sepolia-explorer.giwa.io/address/0x4020A4f3b7b90ccA423B9fabCc0CE57C6C240002)
- [`x402ExactPermit2Proxy` verified contract](https://sepolia-explorer.giwa.io/address/0x402085c248EeA27D92E8b30b2C58ed07f9E20001)
- [`UniversalSigValidator` verified contract](https://sepolia-explorer.giwa.io/address/0xdAcD51A54883eb67D95FAEb2BBfdC4a9a6BD2a3B)

The x402 proxies and ERC-6492 validator are upstream components, deployed by
Tokscale only to satisfy the facilitator's fixed-address prerequisites. Their
source is explorer-verified from upstream compilation inputs and is not
represented as Tokscale-authored work.

## Scope and safety

This is public **testnet research infrastructure**.

- `tUSD` is a test token with a permissionless faucet. It is not a stablecoin,
  has no monetary value, and is not authorized for production use.
- The public `exact` and `upto` transactions prove settlement mechanics. They
  are not a publicly available Tokscale payment route.
- No private keys, custody credentials, user funds, or production endpoints are
  contained here.
- The x402 proxies and validator are upstream components deployed to meet the
  pinned facilitator's required-address invariant. Their upstream provenance is
  recorded rather than claimed as original Tokscale source.

## Reproduce the tUSD checks

The `tUSD` contract was compiled with Solidity `0.8.30`, optimizer enabled
with 200 runs, and `evmVersion = prague`.

```sh
forge fmt --check
forge build
forge test
```

To independently check its public deployment, compare the explorer bytecode
at the address above against `runtimeCodeHash` in
[`deployments/giwa-sepolia-tusd-v1.json`](deployments/giwa-sepolia-tusd-v1.json).
That manifest also pins the EIP-712 domain separator and the consumed
ERC-3009 authorization used by the public settlement transaction.

## Repository layout

```text
src/          Tokscale-authored Solidity source
test/         Solidity tests for the tUSD EIP-3009 surface
deployments/  Immutable public GIWA Sepolia deployment records
upstream/     Provenance records for deployed x402 prerequisites
```

## Related documentation

- [Tokscale documentation](https://github.com/junhoyeo/tokscale-giwa-docs)
- [Live evidence and exact public scope](https://github.com/junhoyeo/tokscale-giwa-docs/blob/main/overview/live-evidence.mdx)
- [x402 on GIWA](https://github.com/junhoyeo/tokscale-giwa-docs/blob/main/gateway/x402-payments.mdx)
