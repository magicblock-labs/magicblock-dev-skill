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
- JSON path: `.environments[network].regions[region].servers[fqdn]`
- Network keys: `mainnet`, `devnet`
- Region keys: `asia`, `europe`, `usa`, `tee`
- Service IDs: `er`, `rpc_router`, `pricing_oracle`, `vrf_oracle`
- Live state: `.live_status[service]` (`true` = Operational, `false` = Down, missing = N/A)
- Downtime history: `.metrics[service]` minutes per day aligned with `.meta.days` in UTC

Current FQDNs are discoverable from the API. Common entries:

| Network | Region | Status API FQDN                 |
| ------- | ------ | ------------------------------- |
| Mainnet | Asia   | `as.magicblock.app`             |
| Mainnet | Europe | `eu.magicblock.app`             |
| Mainnet | USA    | `us.magicblock.app`             |
| Mainnet | TEE    | `mainnet-tee-as.magicblock.app` |
| Devnet  | Asia   | `devnet-as.magicblock.app`      |
| Devnet  | Europe | `devnet-eu.magicblock.app`      |
| Devnet  | USA    | `devnet-us.magicblock.app`      |
| Devnet  | TEE    | `devnet-tee-as.magicblock.app`  |

Example:

```bash
curl -sS https://status.magicblock.app/api/services \
  | jq '.environments.mainnet.regions.asia.servers["as.magicblock.app"].live_status'
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
| Anchor   | 1.0.2   |
| Node     | 24.10.0 |

> Snapshot from the active MagicBlock engine examples. Active examples target
> **Anchor 1.0.2**. Anchor 0.32.1 programs are kept
> under `00-LEGACY_EXAMPLES/` in the engine examples repo for projects still
> on the old line — see the feature-flag note below.

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
| Localnet Validator       | `mAGicPQYBMvcYveUZA5F5UNNwyHvfYh5xkLS2Fr1mev`  |

Prefer the SDK constants over hardcoding these where available:
`ephemeral_rollups_sdk::consts::PERMISSION_PROGRAM_ID`,
`ephemeral_rollups_sdk::consts::ESPL_TOKEN_PROGRAM_ID`,
`ephemeral_vrf_sdk::consts::VRF_PROGRAM_ID` (and `VRF_PROGRAM_IDENTITY`,
`DEFAULT_QUEUE`, `DEFAULT_EPHEMERAL_QUEUE`).

## VRF Oracle Queues

The `oracle_queue` is a state account. Like every Solana account it lives on
Solana, but a delegated queue is directly writable only from inside an
ephemeral rollup, while a non-delegated queue is directly writable on the base
layer. Request randomness from the queue that matches where the transaction
runs. Prefer the `ephemeral_vrf_sdk::consts` constants over hardcoding
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

```toml
[dependencies]
anchor-lang = { version = "1.0.2", features = ["init-if-needed"] }
ephemeral-rollups-sdk = { version = "0.14.3", features = ["anchor"] }

# Feature flag picks the Anchor line:
#   "anchor"        → Anchor 1.0.x (current default)
#   "anchor-compat" → Anchor 0.32.1 (legacy)
# The "disable-realloc" feature no longer exists — drop it if migrating from <0.14.

# Add the access-control feature for Private Ephemeral Rollups (PER)
# ephemeral-rollups-sdk = { version = "0.14.3", features = ["anchor", "access-control"] }

# For cranks
magicblock-magic-program-api = { version = "0.10.1", default-features = false }
bincode = "^1.3"
sha2 = "0.10"

# For VRF
ephemeral-vrf-sdk = { version = "0.3.0", features = ["anchor"] }
```

Use this block as a known-good example for the active examples. For a real repo,
copy its existing version line unless doing an explicit migration.

## NPM Dependencies Snapshot

```json
{
  "dependencies": {
    "@coral-xyz/anchor": "0.32.1",
    "@magicblock-labs/ephemeral-rollups-sdk": "0.14.3"
  }
}
```

> The TypeScript `@coral-xyz/anchor` client stays on **0.32.1** even when the
> on-chain program is built with Anchor 1.0.2 — the IDL/client are compatible,
> so don't bump the npm anchor package to 1.x.

## Documentation Links

- [MagicBlock Documentation](https://docs.magicblock.gg/)
- [Router getDelegationStatus](https://docs.magicblock.gg/pages/ephemeral-rollups-ers/api-reference/er/getDelegationStatus)
- [MagicBlock Status API](https://status.magicblock.app/api/services)
- [MagicBlock Engine Examples](https://github.com/magicblock-labs/magicblock-engine-examples)
- [Ephemeral SPL Token](https://github.com/magicblock-labs/ephemeral-spl-token)
- [MagicBlock Validator](https://github.com/magicblock-labs/magicblock-validator)
- [Ephemeral Rollups SDK (Rust)](https://crates.io/crates/ephemeral-rollups-sdk)
- [Ephemeral VRF SDK (Rust)](https://crates.io/crates/ephemeral-vrf-sdk)
- [NPM Package](https://www.npmjs.com/package/@magicblock-labs/ephemeral-rollups-sdk)
- [Private Payments API Reference](https://payments.magicblock.app/reference)
