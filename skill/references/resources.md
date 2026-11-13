# Resources & Reference

## Environment Variables

```bash
# Devnet
SOLANA_RPC_ENDPOINT=https://rpc.magicblock.app/devnet
ROUTER_ENDPOINT=https://devnet-router.magicblock.app/
WS_ROUTER_ENDPOINT=wss://devnet-router.magicblock.app/

# Mainnet
SOLANA_RPC_ENDPOINT=https://rpc.magicblock.app/mainnet
ROUTER_ENDPOINT=https://router.magicblock.app/

# Set this from router getDelegationStatus result.fqdn for the account.
EPHEMERAL_PROVIDER_ENDPOINT=https://devnet-as.magicblock.app/
EPHEMERAL_WS_ENDPOINT=wss://devnet-as.magicblock.app/
```

## Status JSON API

- Source of truth: `https://status.magicblock.app/api/services`
- JSON path: `.environments[network].regions[region].servers[fqdn]`. Status is per server: there is
  no top-level `live_status` or `metrics`.
- Network keys: `mainnet`, `devnet`
- Region keys: `asia`, `europe`, `usa`, `tee`; mainnet also has `asia-tyo` and `southamerica`
- Service IDs: `er`, `rpc_router`, `pricing_oracle`, `vrf_oracle`
- Live state: `<server>.live_status[service]` (`true` = Operational, `false` = Down, missing = N/A)
- Downtime history: `<server>.metrics[service]` minutes per day aligned with the top-level
  `.meta.days` in UTC

Current FQDNs are discoverable from the API. Common entries:

| Network | Region | Status API FQDN                 |
| ------- | ------ | ------------------------------- |
| Mainnet | Asia   | `as.magicblock.app`             |
| Mainnet | Asia (Tokyo) | `as-tyo.magicblock.app`   |
| Mainnet | Europe | `eu.magicblock.app`             |
| Mainnet | South America | `sa.magicblock.app`      |
| Mainnet | USA    | `us.magicblock.app`             |
| Mainnet | TEE    | `mainnet-tee-as.magicblock.app` |
| Devnet  | Asia   | `devnet-as.magicblock.app`      |
| Devnet  | Europe | `devnet-eu.magicblock.app`      |
| Devnet  | USA    | `devnet-us.magicblock.app`      |
| Devnet  | TEE    | `devnet-tee-as.magicblock.app`  |

The router's `getRoutes` and `getDelegationStatus` name the TEE endpoints `mainnet-tee.magicblock.app`
and `devnet-tee.magicblock.app`; the status API keys the same servers as `*-tee-as`. Map a router
`fqdn` to its status entry by region rather than looking the hostname up directly. Checked
2026-11-13.

Example:

```bash
# One server: {"er":true,"rpc_router":true,...}
curl -sS https://status.magicblock.app/api/services \
  | jq '.environments.mainnet.regions.europe.servers["eu.magicblock.app"].live_status'

# Every service reported Down, across all networks, regions, and servers
curl -sS https://status.magicblock.app/api/services | jq -r '
  .environments | to_entries[] | .key as $net | .value.regions | to_entries[]
  | .key as $region | .value.servers | to_entries[] | .key as $fqdn
  | .value.live_status | to_entries[] | select(.value == false)
  | "\($net) \($region) \($fqdn) \(.key) down"'
```

## Version Policy

Keep exact versions only as known-good snapshots, compatibility tables, or
migration examples. Do not treat
versions in this skill as the latest recommendation. Before adding or changing
dependencies, inspect the target repo's `Cargo.toml`, `package.json`,
`rust-toolchain.toml`, lockfiles, and the relevant upstream manifests/docs.

Existing project manifests override this reference. Only change versions when
the user asked for an upgrade/migration or the current repo already establishes
that version line.

## Known-Good Example Snapshot

| Software | Version |
| -------- | ------- |
| Solana   | 3.1.9   |
| Rust     | 1.89.0  |
| Anchor   | 1.0.2 / 0.32.1 (example-dependent) |
| Node     | 24.10.0 |

> Active MagicBlock engine examples use mixed Anchor versions: examples such as
> root `counter/anchor`, `private-counter/anchor`, and
> `gachapon-example/programs/gachapon-example` use 1.0.2. Inspect the target example's `Cargo.toml` and
> preserve its version line unless the task explicitly requests a migration.
> Use `gachapon-example` only as an Anchor-version reference: its VRF callback trusts the hardcoded
> legacy VRF identity, which is unsafe. See [vrf.md](vrf.md) for the `#[vrf_callback]` pattern.

Example provenance checked against `magicblock-engine-examples` `main` (`ad38f9b`) on **2026-11-13**.
Active examples still pin Rust SDK `0.16.2`:

| Exact example path | Rust SDK | TypeScript SDK |
|---|---:|---:|
| `spl-tokens/anchor` | `0.16.2` | root `0.16.2`; app `0.17.2` |
| `magic-actions/anchor` | `0.16.2` | `0.14.3` |
| `binary-prediction/anchor` | `0.16.2` | `0.14.3` |
| `roll-dice/anchor` | `0.16.2` | app `0.14.3` |
| `gasless-starter/anchor` | — | root `0.16.2`; app `0.17.3` |

These are working-example snapshots, not one mutually compatible version recommendation. Because
the examples are on Rust `0.16.2`, they use 0.16 API names (for example
`create_request_scoped_randomness_ix`); the snippets in this skill use the `0.17.3` names. Registry
latest on **2026-11-13**: crates.io `ephemeral-rollups-sdk` `0.17.3` and npm
`@magicblock-labs/ephemeral-rollups-sdk` `0.17.3` (both released 2026-09-24). Rust and TypeScript
snippets in this skill use `0.17.3`. Preserve a target repo's version line unless upgrading it
explicitly.

## Key Program IDs

| Program                  | Address                                        |
| ------------------------ | ---------------------------------------------- |
| Delegation Program       | `DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh` |
| Magic Program            | `Magic11111111111111111111111111111111111111`  |
| Magic Context            | `MagicContext1111111111111111111111111111111`  |
| Session Key Program      | `KeyspM2ssCJbqUhQ4k7sveSiY4WjnYsrXkC8oDbwde5`  |
| Permission Program (PER) | `ACLseoPoyC3cBqoUtkbjZ4aDrkurZW86v19pXz2XQnp1` |
| VRF Program              | `Vrf1RNUjXmQGjmQrQLvJHs9SNkvDJEsRVFPkfSQUwGz`  |
| Ephemeral SPL Token      | `SPLxh1LVZzEkX99H6rqYizhytLWPZVV296zyYDPagv2`  |
| Pricing Oracle           | `PriCems5tHihc6UDXDjzjeawomAwBduWMGAi8ZUjppd`  |
| Hydra (base crank)       | `Hydra17i1feui9deaxu6d1TzSQMRNHeBRkDR1Awy7zea` |
| Hydra (ephemeral crank)  | `eHyd5BU8QffvHi4GnXwxrK4WpS7pM2x9UGKHBWii7mf`  |
| Localnet Validator       | `mAGicPQYBMvcYveUZA5F5UNNwyHvfYh5xkLS2Fr1mev`  |

Prefer the SDK constants over hardcoding these where available:
`ephemeral_rollups_sdk::consts::PERMISSION_PROGRAM_ID`,
`ephemeral_rollups_sdk::consts::ESPL_TOKEN_PROGRAM_ID`,
`ephemeral_rollups_sdk::vrf::consts::VRF_PROGRAM_ID` (and `DEFAULT_QUEUE`,
`DEFAULT_EPHEMERAL_QUEUE`; the `vrf` module needs the SDK's `vrf` feature).

## VRF Oracle Queues

The `oracle_queue` is a state account. Like every Solana account it lives on
Solana, but a delegated queue is directly writable only from inside an
ephemeral rollup, while a non-delegated queue is directly writable on the base
layer. Request randomness from the queue that matches where the transaction
runs. Prefer the `ephemeral_rollups_sdk::vrf::consts` constants over hardcoding
addresses.

| Constant                      | Network              | Queue                              | Address                                        |
| ----------------------------- | -------------------- | ---------------------------------- | ---------------------------------------------- |
| `DEFAULT_QUEUE`               | Mainnet / Devnet     | Base-layer queue                   | `Cuj97ggrhhidhbu39TijNVqE74xvKJ69gDervRUXAxGh` |
| `DEFAULT_EPHEMERAL_QUEUE`     | Mainnet / Devnet     | Delegated queue (ephemeral rollup) | `5hBR571xnXppuCPveTrctfTU7tJLSN94nq7kv7FRK5Tc` |
| `DEFAULT_TEST_QUEUE`          | Localnet             | Base-layer queue                   | `GKE6d7iv8kCBrsxr78W3xVdjGLLLJnxsGiuzrsZCGEvb` |
| `DEFAULT_EPHEMERAL_TEST_QUEUE`| Localnet             | Delegated queue (ephemeral rollup) | `Sc9MJUngNbQXSXGP3F67KvKwVnhaYn6kcioxXNVowYT` |

Mainnet and Devnet share the same default queue addresses — only the cluster
differs. Localnet uses dedicated test queues that the local validator clones
from Devnet.

## Rust Dependencies Snapshot

Rust and TypeScript snapshots verified **2026-11-13** against crates.io and npm (`0.17.3`). Re-check
before calling it latest:

```bash
cargo info ephemeral-rollups-sdk@0.17.3
npm view @magicblock-labs/ephemeral-rollups-sdk@0.17.3 version
git ls-remote --tags \
  https://github.com/magicblock-labs/ephemeral-rollups-sdk.git \
  "refs/tags/v0.17.*"
```

```toml
[dependencies]
anchor-lang = { version = "1.0.2", features = ["init-if-needed"] }
ephemeral-rollups-sdk = { version = "0.17.3", features = ["anchor"] }

# Feature flag picks the Anchor line:
#   "anchor"        → Anchor 1.x
#   "anchor-compat" → Anchor >=0.28,<1.0 (open SDK PR #317 removes it)
# Product features are opt-in:
#   "access-control" → Private Ephemeral Rollups (PER) permissions
#   "spl"            → Ephemeral SPL Token builders and Magic ATA helpers
#   "vrf"            → VRF request/callback API (ephemeral_rollups_sdk::vrf)
#   "crank"          → crank CPIs, including Hydra (ephemeral_rollups_sdk::crank)
# ephemeral-rollups-sdk = { version = "0.17.3", features = ["anchor", "access-control"] }
# ephemeral-rollups-sdk = { version = "0.17.3", features = ["anchor", "vrf"] }
# ephemeral-rollups-sdk = { version = "0.17.3", features = ["anchor", "crank"] }
```

SDK `0.17.3` depends on `magicblock-magic-program-api` `0.10.1` and
`magicblock-delegation-program-api` `3.1.0`, even though crates.io has `1.1.1` and `4.0.1`. Do not
add a direct `magicblock-magic-program-api` dependency for cranks; use the SDK `crank` feature (see
[cranks.md](cranks.md)). Do not read fee values from the SDK's re-exported `dlp_api::consts`; they
are the pre-10x values (see [fees-and-commit-economics.md](fees-and-commit-economics.md)).

For a real repo, keep its existing compatible version line unless doing an
explicit migration.

## NPM Dependencies Snapshot

```json
{
  "dependencies": {
    "@coral-xyz/anchor": "0.32.1",
    "@magicblock-labs/ephemeral-rollups-sdk": "0.17.3"
  }
}
```

`@magicblock-labs/ephemeral-rollups-kit` is the same SDK for `@solana/kit` codebases, released at
the same version. See [typescript-setup.md](typescript-setup.md) before choosing it.

Additional product/tool snapshots verified **2026-11-13**; re-check before installation:

| Package | Snapshot | Context |
|---|---:|---|
| `@magicblock-labs/ephemeral-validator` | `1.1.1` | Local validator/stack binaries (matches public ERs) |
| `@magicblock-labs/magicsvm` | `0.2.1` | Fast in-process ER lifecycle tests; see [local-development.md](local-development.md) |
| `hydra-api` (crate) | `0.2.1` | Hydra crank API, re-exported by the SDK `crank` feature |
| `@magicblock-labs/gum-sdk` | `^3.0.10` | Session Keys client in the current binary-prediction example |
| Rust `session-keys` | `=3.1.1` | Session token validation in the current binary-prediction example |

> The TypeScript `@coral-xyz/anchor` client stays on **0.32.1** even when the
> on-chain program is built with Anchor 1.0.2 — the IDL/client are compatible,
> so do not bump the npm Anchor package to 1.x.

## Documentation Links

- [MagicBlock Documentation](https://docs.magicblock.gg/)
- [Router getDelegationStatus](https://docs.magicblock.gg/pages/ephemeral-rollups-ers/api-reference/er/getDelegationStatus)
- [MagicBlock Status API](https://status.magicblock.app/api/services)
- [MagicBlock Engine Examples](https://github.com/magicblock-labs/magicblock-engine-examples)
- [PER access-control guide — Ephemeral Permission lifecycle](https://docs.magicblock.gg/pages/private-ephemeral-rollups-pers/how-to-guide/access-control#ephemeral-permission)
- [Anchor private-counter example](https://github.com/magicblock-labs/magicblock-engine-examples/tree/main/private-counter/anchor)
- [Ephemeral SPL Token](https://github.com/magicblock-labs/ephemeral-spl-token)
- [Pricing Oracle](https://github.com/magicblock-labs/real-time-pricing-oracle)
- [Pricing Oracle guide](https://docs.magicblock.gg/pages/tools/oracle/introduction)
- [Session Keys guide](https://docs.magicblock.gg/pages/tools/session-keys/introduction)
- [Ephemeral Accounts guide](https://docs.magicblock.gg/pages/ephemeral-rollups-ers/introduction/ephemeral-accounts)
- [Local development guide](https://docs.magicblock.gg/pages/ephemeral-rollups-ers/how-to-guide/local-development)
- [MagicBlock Validator](https://github.com/magicblock-labs/magicblock-validator)
- [Hydra (permissionless crank)](https://github.com/magicblock-labs/hydra)
- [Solana VRF](https://github.com/magicblock-labs/solana-vrf) and [VRF guide](https://docs.magicblock.gg/pages/verifiable-randomness-functions-vrfs/introduction/solana-vrf)
- [magicsvm (npm)](https://www.npmjs.com/package/@magicblock-labs/magicsvm)
- [Ephemeral Rollups SDK (Rust)](https://crates.io/crates/ephemeral-rollups-sdk)
- [Ephemeral Rollups SDK source](https://github.com/magicblock-labs/ephemeral-rollups-sdk) — use the tag matching your pinned version
- [NPM Package](https://www.npmjs.com/package/@magicblock-labs/ephemeral-rollups-sdk)
- [Private Payments API Reference](https://payments.magicblock.app/reference)
- [Private Payments live OpenAPI document](https://payments.magicblock.app/doc) — mutable hosted
  contract; re-fetch before implementation rather than treating this skill's dated field tables as live
