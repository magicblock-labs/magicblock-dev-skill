# Resources & Reference

## Environment Variables

```bash
EPHEMERAL_PROVIDER_ENDPOINT=https://devnet.magicblock.app/
EPHEMERAL_WS_ENDPOINT=wss://devnet.magicblock.app/
ROUTER_ENDPOINT=https://devnet-router.magicblock.app/
WS_ROUTER_ENDPOINT=wss://devnet-router.magicblock.app/
```

## Version Requirements

| Software | Version |
|----------|---------|
| Solana | 2.3.13 |
| Rust | 1.85.0 |
| Anchor | 0.32.1 |
| Node | 24.10.0 |

## Key Program IDs

| Program | Address |
|---------|---------|
| Delegation Program | `DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh` |
| Magic Program | `Magic11111111111111111111111111111111111111` |
| Magic Context | `MagicContext1111111111111111111111111111111` |
| Localnet Validator | `mAGicPQYBMvcYveUZA5F5UNNwyHvfYh5xkLS2Fr1mev` |

## Rust Dependencies

```toml
[dependencies]
anchor-lang = { version = "0.32.1", features = ["init-if-needed"] }
ephemeral-rollups-sdk = { version = "0.6.5", features = ["anchor", "disable-realloc"] }

# For cranks
magicblock-magic-program-api = { version = "0.3.1", default-features = false }
bincode = "^1.3"
sha2 = "0.10"

# For VRF
ephemeral-vrf-sdk = { version = "0.2.1", features = ["anchor"] }
```

## NPM Dependencies

```json
{
  "dependencies": {
    "@coral-xyz/anchor": "^0.32.1",
    "@magicblock-labs/ephemeral-rollups-sdk": "^0.6.5"
  }
}
```

## Documentation Links

- [MagicBlock Documentation](https://docs.magicblock.gg/)
- [MagicBlock Engine Examples](https://github.com/magicblock-labs/magicblock-engine-examples)
- [Ephemeral Rollups SDK (Rust)](https://crates.io/crates/ephemeral-rollups-sdk)
- [Ephemeral VRF SDK (Rust)](https://crates.io/crates/ephemeral-vrf-sdk)
- [NPM Package](https://www.npmjs.com/package/@magicblock-labs/ephemeral-rollups-sdk)
