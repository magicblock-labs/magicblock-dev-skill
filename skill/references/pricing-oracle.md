# Pricing Oracle

Use the MagicBlock Pricing Oracle when an ER application needs low-latency market data close to its
execution state. It republishes Pyth Lazer feeds into accounts that the oracle updates on the ER. The
program also has a Stork pusher (provider `stork-oracle`), but no live Stork feed was found on
2026-11-19 (devnet-as `SOLUSD` read `price = 0`, about 584 days stale; mainnet had none). Treat Stork
as unverified.

**Read feeds on the ER only.** Checked live on 2026-11-19 for SOL/USD (`ENYwebB…`), BTC, ETH, and
USDC:

- Every ER checked (as, eu, us, devnet-as/eu/us): owner `PriCems…`, age 0–1 s.
- Mainnet base: owner Delegation Program (the feeds are delegated), `publish_time` 2025-08-14, about
  462 days old.
- Devnet base: owner Delegation Program, mostly `price = 0`, `posted_slot = 0`.

A base-layer consumer with a freshness check always fails; one without a freshness check uses a price
more than a year old.

## Contents

- [When it fits](#when-it-fits)
- [Trust and freshness model](#trust-and-freshness-model)
- [Integration workflow](#integration-workflow)
- [Consumer safety checklist](#consumer-safety-checklist)
- [Testing and operations](#testing-and-operations)

## When it fits

Use it for price-aware games, prediction markets, trading, collateral checks, dynamic pricing, or any
instruction whose result depends on an external price. Do not use it as a substitute for application
state: the oracle tells the program what a source reported, while the application still defines
position ownership, limits, settlement, and failure policy.

Choose the data path deliberately:

| Need | Placement |
|---|---|
| Settlement or purchase on Solana | Not from the base copies (stale). Read the price on the ER and carry it to base in app state, or use a base-layer oracle |
| Repeated low-latency decisions in one ER | Make the feed available in that ER and read it there |
| Private application state | Keep application state in PER; treat the feed as public input |

An oracle feed and every account mutated by the same transaction must be visible to the same runtime.
Co-locate them before promising an atomic price-dependent operation.

## Trust and freshness model

Successful deserialization is insufficient. Verify:

1. **Address/source identity** — the configured provider, symbol, feed ID, and account address are the
   ones the product expects.
2. **Account type and owner** — live feeds are `PriceUpdateV3` accounts (Anchor discriminator)
   owned by `PriCems…`, with a field layout compatible with Pyth's `PriceUpdateV2`. Never declare
   them as `Account<'info, PriceUpdateV2>`: Anchor then rejects every live feed
   (`AccountOwnedByWrongProgram` 3007, or `AccountDiscriminatorMismatch` 3002 if re-owned). Check the
   account key and owner `PriCems…` yourself, then decode with
   `PriceUpdateV2::try_deserialize_unchecked`. Do not parse hard-coded byte offsets.
3. **Republisher trust** — `VerificationLevel::Full` alone is not proof of a republisher update:
   initialization also sets `Full` while writing a zero-value placeholder with `posted_slot = 0`. The
   authenticated update path requires the fixed MagicBlock republisher and writes a nonzero local
   posting slot. Require the canonical feed account, the expected feed ID (the account address; see
   below), `posted_slot > 0`, a sensible value, and a fresh upstream publish time. The account has no
   separate onchain provenance field that identifies which transition wrote the current value. The
   consumer trusts the program's update authorization; it does not independently verify the upstream
   Pyth Lazer or Stork proof.
4. **Freshness** — compare the upstream publish timestamp with the current clock and reject data older
   than the product's explicit maximum age.
5. **Value domain** — reject non-positive values where they are nonsensical. Do not use `conf` as an
   uncertainty measure: the oracle initializes it to `0` and never writes it, and the live SOL/USD
   feed on the mainnet and devnet ERs reads `conf == 0` (2026-11-19), so a confidence-width check
   passes every update. Take uncertainty from another source, or fail closed by policy (price
   bands, maximum move per update, or a second feed).
6. **Numeric conversion** — the stored `exponent` is wrong: it is `+8` on every feed checked on
   2026-11-19 (SOL, BTC, ETH, USDC, PEPE, NEIRO, BONK), wrong in sign for all and in magnitude for
   the −10 feeds. Take the exponent from the feed list (`pyth_lazer_list.json`: −8 for SOL/USD, −10
   for BONK), not from the account or `get_price_no_older_than(...).exponent`. Pyth-convention math on
   the stored value sold a $1.00 item for 1 lamport (correct: 13,394,321) against the live SOL/USD
   account. Use checked integer arithmetic; avoid floating point in the program.
7. **User protection** — price-based purchases and swaps should accept a user maximum/minimum or
   slippage bound so a valid but changed price cannot create an unwanted trade.

In the current oracle program, `publish_time` represents the upstream oracle timestamp, while the
locally posted slot is tracked separately. Use the publish time for staleness decisions.

**Feed identity.** The stored `price_message.feed_id` is the feed account's own address, not the Pyth
Lazer id. The address is the PDA `[b"price_feed", b"pyth-lazer", <Lazer id as a decimal string>]`
under `PriCems…` (SOL/USD is id `6` → `ENYwebBThHzmzwPLAQvCucUTsjyfBSZdD9ViXksS4jPu`). Pass the
account key as the expected feed id to `get_price_no_older_than`; the Lazer id bytes fail with a
feed-id mismatch.

## Integration workflow

1. Select provider and symbol from the current supported feed set.
2. Record the provider, symbol, Pyth Lazer id, expected price-account address (also the stored feed
   id), the feed-list exponent, and maximum age in application configuration.
3. Decide which ER (public or PER) runs the consuming instruction. Base-layer copies are stale.
4. Ensure the feed account is available in the same runtime as every account the instruction needs.
5. Check the key and owner, decode with `try_deserialize_unchecked`, verify freshness, then apply
   business constraints with checked math and the feed-list exponent.
6. Define the stale/missing-feed behavior before launch: reject, pause, or use another verified
   source. Never silently reuse an unbounded old value, and do not fall back to the base-layer copy.

The current oracle program ID is
`PriCems5tHihc6UDXDjzjeawomAwBduWMGAi8ZUjppd`. Treat addresses and package versions as
version-sensitive: verify them against the current oracle repository and target cluster before use.

## Consumer safety checklist

- Read the ER copy; the base-layer copy is stale.
- Verify the account key or derived feed address and the owner `PriCems…`, not only the data type.
  Decode with `try_deserialize_unchecked`; never `Account<PriceUpdateV2>`.
- Verify the expected feed ID after deserialization: it equals the account address.
- Never accept `VerificationLevel::Full` by itself: initialization sets it before a republisher update.
  Require the canonical account/feed/provider, expected feed ID, `posted_slot > 0`, a
  sensible value, and a fresh upstream publish timestamp. This is evidence consistent with the
  authenticated update path, not an onchain provenance field or independent upstream proof.
- Enforce a product-specific maximum age using the upstream publish timestamp.
- Reject impossible values and define a confidence policy.
- Take the exponent from the feed list, not the account (`+8` on every feed). Normalize with checked
  multiplication/division and explicit rounding.
- Prevent overflow in price × quantity calculations.
- Accept user price/slippage limits for value-changing instructions.
- Avoid storing a price indefinitely in app state without storing and checking its timestamp.
- Keep authorization independent from price validation: a valid price does not authorize a caller.

## Testing and operations

Test at least: correct feed, wrong feed ID, stale feed, zero/negative price, exponent conversion,
overflow boundary, user limit exceeded, missing ER clone, and provider outage. Build fixtures from a
dumped live ER feed account. A Pyth receiver fixture (owner `rec5EK…`, `PriceUpdateV2`, exponent −2)
hides the owner, discriminator, and exponent problems above. A local fixture proves consumer logic;
Devnet proves the live publisher/account path; production-like validation must also exercise
stale-feed behavior and the intended ER placement.

Examples:

- Do not copy `magicblock-engine-examples/oracle-priced-purchase/anchor`. It declares
  `Account<PriceUpdateV2>`, which rejects every live feed, and its tests pass only on a Pyth receiver
  fixture. With the unchecked decode it trusts the stored `+8` exponent and charges 1 lamport for
  $1.00 (checked 2026-11-19).
- `magicblock-engine-examples/binary-prediction/anchor` — composition with ER, Session Keys, and eSPL.
  Its feed read uses `try_deserialize_unchecked` with a key check; review its exponent handling before
  reusing it.

Sources: [Pricing Oracle repository](https://github.com/magicblock-labs/real-time-pricing-oracle),
[Pricing Oracle docs](https://docs.magicblock.gg/pages/tools/oracle/introduction), and
[engine examples](https://github.com/magicblock-labs/magicblock-engine-examples).
