# Fees and Commit Economics

Read this guide first for any question about ER transaction cost, delegation deposits, commit
sponsorship, `magic_fee_vault`, refunds, fee-payer top-ups, Magic Action charges, or validator fee
claims. The active model is split between the Delegation Program on Solana and the MagicBlock
validator. Reading either repository alone gives an incomplete answer.

Values below were source-verified on 2026-10-06 and re-checked on 2026-11-13 against:

- Delegation Program `main` at `0c551fa64cd13d6dabc51dbf6d1575bde2d38067`, the build deployed on
  devnet and mainnet since 2026-11-03 (executable hash verified)
- MagicBlock validator tag `v1.1.1`, the version every public ER reports through `getVersion`

The validator's `master` branch now carries the 2.0 line (release candidates only). See
[Validator 2.0 changes](#validator-20-changes-release-candidate) before applying these numbers to a
2.0 node.

Do not call commits "free" merely because no lamports move during the scheduling instruction. A
commit can consume the fee budget held in delegation PDAs and be charged later at undelegation.

## Cost buckets

| Bucket | Active amount | When it is charged | Source of funds |
|---|---:|---|---|
| ER transaction fee | `0` in the current release | Every executed ER transaction | No debit |
| Intent scheduling fee | `0` | When an intent bundle is scheduled | No standalone debit |
| Delegation session fee | `3_000_000` lamports | Delegation cleanup at undelegation | Delegation record + metadata PDAs |
| Delegation commit fee | `1_000_000` lamports for each finalized commit after the first | Delegation cleanup at undelegation | Delegation record + metadata PDAs, capped by their combined balance |
| Extra live commit fee | `100_000` lamports per committed account once its current nonce is at least `25` | When the ER schedules the next commit through the fee-vault path | Delegated fee payer on the ER |
| Base Action fee | `50_000` micro-lamports per requested CU | When an intent bundle is scheduled through the fee-vault path | Delegated fee payer on the ER |
| Add-callback fee | `5_000` lamports per callback attachment instruction | When `AddActionCallback` succeeds | Delegated fee payer on the ER |
| Ephemeral Account rent | `32 * (data_len + 60)` lamports | Create/grow; refunded on shrink/close | Ephemeral Account sponsor on the ER |

Base-layer Solana transaction fees for delegation, top-up, settlement, or other base transactions are
separate. Product-specific charges in other programs, such as the Ephemeral SPL Token sponsored
lamports-transfer setup charge, are also separate.

## 1. ER transaction fee

The current validator release charges `0` for ordinary ER transaction execution. Commit,
delegation, and Magic Action fees are separate.

The current `ScheduledIntentBundle::calculate_fee` also declares `SCHEDULING_FEE = 0`. Intent bundles
therefore have no additional flat scheduling charge; only their commit, Base Action, and callback
components add validator-side fees.

### ER-only Ephemeral Account rent

The validator's Ephemeral Account program charges refundable ER-local rent:

```text
ephemeral_rent = (data_len + 60) * 32 lamports
```

Create and resize-up move the required amount from the sponsor into the canonical Ephemeral Account
vault. Resize-down and close move the corresponding amount back to the sponsor. A zero-data account
therefore reserves `1_920` lamports; a 1,000-byte account reserves `33_920` lamports. This rent is
separate from Delegation Program PDAs because Ephemeral Accounts never settle to Solana.

See [ephemeral-accounts.md](ephemeral-accounts.md) for the signer, ownership, size, and lifecycle
requirements. An underfunded sponsor fails the lifecycle instruction rather than partially funding
the account.

## 2. Delegation deposits and undelegation charges

Delegating an account creates two Solana PDAs funded by the delegation payer:

- a delegation record; its base serialized size is `96` bytes;
- delegation metadata; its size is `53` bytes plus the encoded account seeds.

Delegation with actions appends the serialized actions to the record, increasing its rent deposit.
Therefore the upfront deposit is not one universal constant. It depends on account sizes, seeds,
attached actions, and the active Solana rent parameters.

The metadata records the original `rent_payer`. At undelegation the program computes:

```text
commit_count = max(last_commit_id - 1, 0)
requested_fee = 3_000_000 + 1_000_000 * commit_count
collectible_fee = min(
  requested_fee,
  delegation_record_lamports + delegation_metadata_lamports
)
refund = combined_delegation_PDA_lamports - collectible_fee
```

Consequences:

- A session with no finalized commit still requests the `3_000_000`-lamport session fee.
- Commit 1 adds no commit fee.
- Commits 2, 3, and so on add `1_000_000` lamports each.
- Collection is capped by the two PDA balances. An exhausted deposit does not cause
  `InsufficientFunds`, and this path does not record the remainder as debt.
- The refund goes to the `rent_payer` stored at delegation time, not necessarily to the current
  account authority or the transaction payer that requested undelegation.
- Since Delegation Program #274 (deployed 2026-11-03), if adding the refund would still leave that
  rent payer below rent-exemption (for example an empty sponsor wallet receiving a few thousand
  lamports), the refund goes to the validator fees vault instead. Before this fix the whole
  undelegation failed in that case. A funded rent payer is refunded as before.

dlp-api 4.0 removed `RENT_FEES_PERCENTAGE`. Do not calculate the session charge as a percentage of
rent. The cleanup uses the fixed session/commit formula above and uses
`PROTOCOL_FEES_PERCENTAGE = 10` only for distribution.

Do not read these amounts from `ephemeral_rollups_sdk::dlp_api::consts`. SDK `0.17.3` re-exports
dlp-api `3.1.0`, whose `COMMIT_FEE_LAMPORTS = 100_000` and `SESSION_FEE_LAMPORTS = 300_000` are the
values from before the 10x increase. dlp-api `4.0.1` has `1_000_000` and `3_000_000`, which match the
deployed program.

### A zero-data account rent top-up is not a fee

When the delegated account itself has zero data and zero lamports, delegation transfers
`890_880` lamports to make that account rent-exempt. This is account funding, not protocol revenue,
and is distinct from the delegation record/metadata deposits.

## 3. Validator-side commit limits and metering

The ER chooses one of two scheduling paths based on the payer account.

### Path A: no delegated fee payer

For an ordinary plain commit without the fee-vault path, the validator reads the current commit nonce
for every committed account.

- Current nonce `0` through `9`: the next commit is accepted.
- Current nonce `10` or greater: the whole scheduling instruction fails with custom error
  `0xA0000000` (`COMMIT_LIMIT_ERR`).
- The log tells the caller to undelegate/re-delegate or use a delegated account as payer.

This is a hard scheduling limit, not proof that the accepted commits cost zero. Their session and
after-first-commit charges are still calculated from the delegation PDAs at undelegation.

The legacy `ScheduleCommit` path deliberately skips the hard limit for commit-and-undelegate, so an
account can still exit. The intent-bundle path likewise applies the no-vault hard-limit check only to
its plain `commit` accounts. Do not use exit behavior as an unlimited-commit strategy.

### Path B: delegated payer + validator-scoped `magic_fee_vault`

The fee-vault path is selected when the intent payer is both delegated and not confined. The program
then requires the exact validator-scoped `magic_fee_vault` account and requires that vault to be
writable and delegated.

For each committed account:

```text
if current_nonce >= 25:
    live_commit_fee += 100_000 lamports
```

The nonce is the number of commits already finalized. This means:

- commits 1 through 25 have no additional validator-side commit debit;
- commit 26 is the first one debited `100_000` lamports;
- the charge is per committed account, not per transaction or intent bundle;
- accounts at different nonces in one bundle are charged independently;
- commit, commit-and-undelegate, commit-finalize, and commit-finalize-and-undelegate variants all
  participate in fee calculation on the fee-vault path.

The validator subtracts the total from the delegated payer and adds it to the delegated magic fee
vault atomically. If the payer lacks the full amount, the instruction fails with
`InstructionError::InsufficientFunds`; it does not partially charge the bundle.

The committed account and the fee payer are independent. If a backend PDA pays for users' commits,
apply explicit application budgets, authorization, and rate limits to that payer.

### These mechanisms add; one does not replace the other

The validator-side threshold does not disable Delegation Program cleanup. At undelegation, the fixed
session/commit formula still runs and is capped by the delegation PDA balances. For a source-exact
cost estimate, calculate both:

1. the capped cleanup charge for every delegated account; and
2. any live fee-vault debits made after each account crossed the validator threshold.

## 4. Magic Action and callback charges

On the fee-vault path, an intent bundle also charges for requested Base Action compute:

```text
action_fee_lamports = ceil(
  sum(action.compute_units) * 50_000 / 1_000_000
)
```

Examples:

- one `200_000` CU action: `10_000` lamports;
- two `200_000` CU actions: `20_000` lamports;
- an action-only bundle still owes its action fee when it uses the delegated payer path.

`AddActionCallback` separately charges a flat `5_000` lamports when the callback is attached. The
callback's own `compute_units` field is not included in `calculate_actions_fee`; the current scheduling
code charges the flat attachment fee instead.

## Settlement and operator cash flows that are not extra app fees

Do not classify every lamport movement into a validator-owned vault or account as a protocol charge.

### Delegated-account lamport settlement

On commit/finalize, the Delegation Program compares the account's newly committed lamport balance to
the balance stored in its delegation record:

- If the committed balance is lower, the difference moves from the delegated base account into the
  validator fees vault.
- If the committed balance is higher, the validator supplies the difference to the delegated base
  account.

This reconciles ER-side lamport movements with Solana. It is not another percentage or fixed fee.
ER-side commit/action charges reduce the delegated payer and credit the magic fee vault, so the
payer's later balance settlement is also how that revenue reaches the base-layer validator fees
vault.

### Legacy two-step commit rent and collateral

The Delegation Program still supports this path, but validator `1.1.1` no longer uses it: it builds
only `commit_finalize` and `commit_finalize_from_buffer` tasks (validator #1763 / #1764 removed the
legacy Commit/Finalize tasks). Treat the following as reference for older nodes.

The legacy `CommitState` / `CommitDiff` path creates temporary commit-state and commit-record PDAs.
The validator funds their rent and, when a committed balance increased, fronts the balance delta as
collateral. `Finalize` applies the state, closes both temporary PDAs, and returns their remaining
lamports to the validator. The fast commit-finalize path updates the account directly and does not
create those two temporary PDAs.

These are validator working-capital and base-transaction costs, not charges debited by the validator's
live app-fee calculation.

### Base-layer commit transaction priority fee

The release committor configuration defaults its Solana compute-unit price to `1_000_000`
micro-lamports per CU. The operator can change it to control inclusion priority for commit
transactions. Do not confuse this operator-side base transaction setting with the app-facing Base
Action rate of `50_000` micro-lamports per requested CU.

### Fee-vault setup rent

The protocol fees vault, each validator fees vault, and each magic fee vault are initialized as
8-byte Delegation Program PDAs. Their setup payer funds rent. This is infrastructure account funding,
not a recurring per-commit app charge. Protocol and validator claims preserve the vault's rent-exempt
reserve; closing a validator fees vault sends its remaining lamports to the validator identity.

## Worked examples

Let `D` be the combined lamports in one account's delegation record and metadata PDAs immediately
before cleanup. These examples exclude ordinary Solana transaction fees.

### One account, one commit, then undelegate

```text
cleanup request = 3_000_000 + 1_000_000 * (1 - 1)
                = 3_000_000
cleanup charge  = min(D, 3_000_000)
refund          = D - cleanup charge
live commit fee = 0
```

### One account, ten plain commits, then undelegate

All ten are allowed by the no-vault path because the check happens against the current nonce before
the next commit.

```text
cleanup request = 3_000_000 + 1_000_000 * (10 - 1)
                = 12_000_000
cleanup charge  = min(D, 12_000_000)
refund          = D - cleanup charge
live commit fee = 0
```

An eleventh plain commit sees current nonce `10` and hard-fails with `0xA0000000`. Commit-and-
undelegate remains available so the account can exit.

### One account, 26 commits through the fee-vault path

```text
cleanup request       = 3_000_000 + 1_000_000 * (26 - 1)
                      = 28_000_000
cleanup charge        = min(D, 28_000_000)
live fee-vault debits = 100_000  # commit 26
refund                = D - cleanup charge
```

The total economic outflow is the cleanup charge plus the live debit, even if different payer
accounts supplied them.

### Three accounts in one bundle

Suppose their current nonces are `24`, `25`, and `31`. The next commit charges:

```text
account at nonce 24 -> 0
account at nonce 25 -> 100_000
account at nonce 31 -> 100_000
bundle commit fee   -> 200_000 lamports
```

Add the bundle's Base Action fee, if any, before checking the delegated payer balance.

## Where the lamports go

There are two fee-collection routes.

### Delegation cleanup route

As the record and metadata PDAs close, each collected chunk is split using
`PROTOCOL_FEES_PERCENTAGE = 10`:

- approximately 10% goes directly to the protocol fees vault;
- the remainder goes to the validator fees vault;
- integer division can produce small rounding differences per closed PDA.

### Validator fee-vault claim route

The validator fees vault also receives lamport decreases settled from delegated accounts, which is
how ER-side fee-payer debits become base-layer validator revenue. When a validator later claims an
amount from its base-layer validator fees vault, another 10% of the claimed amount is transferred to
the protocol fees vault and the validator receives the remainder.

For cleanup-derived revenue that passes through both steps, the source therefore applies one split
during cleanup and another when the validator claims its remaining share. Avoid simplifying this to a
single 10% cut when reconciling vault balances.

The validator's automatic claim task skips balances at or below `100_000_000` lamports and defaults to
a 24-hour polling interval. That threshold controls claim batching; it is not an application fee.
Validator 2.0 removes this automatic task; see [Validator 2.0 changes](#validator-20-changes-release-candidate).

## Funding a delegated fee payer

The validator does not automatically refill an application's delegated payer. Before scheduling a
billable bundle, ensure its ER balance covers:

```text
per-account live commit fees
+ Base Action fees
+ callback attachment fee, if sent separately
+ application safety buffer
```

Use `lamportsDelegatedTransferIx` for the SDK's sponsored base-to-ER top-up flow. Read
[lamports-topup.md](lamports-topup.md) for its routing, salt, setup-charge, and retry rules. Its setup
charge comes from the Ephemeral SPL Token program and must not be confused with the Delegation
Program's `3_000_000`-lamport session fee. eSPL #161 raised that charge from `300_000` to `3_000_000`
lamports. As of 2026-11-13 devnet runs the new value and mainnet still charges `300_000`; read the
deployed program's constant rather than assuming either.

The Delegation Program also exposes `top_up_ephemeral_balance`. It creates a zero-data ephemeral
balance PDA if needed and transfers the requested lamports into it. That instruction adds no explicit
protocol percentage or fixed charge in the Delegation Program; the payer still funds the amount,
required rent, and ordinary base transaction fee.

## Failure map

| Condition | Result |
|---|---|
| Plain commit with current nonce `>= 10`, no fee-vault path | Custom `0xA0000000` |
| Validator cannot find a nonce for a committed account | Custom `0xA0000001` |
| Delegated payer but wrong/missing validator-scoped magic fee vault | `MissingAccount` |
| Magic fee vault is not delegated or not writable | `IllegalOwner` |
| Delegated payer cannot cover the whole calculated fee | `InsufficientFunds` |
| Ephemeral Account sponsor cannot cover create/grow rent | `InsufficientFunds` |
| Delegation deposits cannot cover cleanup request | No underfund error; charge is capped and no debt is recorded |
| Refund would leave the recorded rent payer below rent-exemption | Refund goes to the validator fees vault (since DLP #274) |
| Committed account data larger than 10,240 bytes | `InvalidAccountData`; log `ScheduleCommit ERR: account <pubkey> is too large to be committed` |
| Intent exceeds the validator's size limits | Custom `0xA0000002` (`INTENT_TOO_LARGE_ERR`) |
| Commit or undelegate of a Magic ATA | Rejected; log says to use the shuttle withdrawal flow |
| Validator claims more than its base vault holds above rent | `InsufficientFunds` |

## How to verify current behavior

Check both repositories, because matching numeric constants do not prove matching enforcement:

### Delegation Program

- `dlp-api/src/consts.rs`: fixed session/commit amounts, protocol percentage, zero-data rent
  exception
- `src/processor/fast/undelegate.rs`: after-first commit count, capped cleanup request
- `src/processor/fast/utils/pda.rs`: refund destination, the rent-payer dust fallback, and cleanup
  split
- `src/processor/fast/internal/commit_finalize_internal.rs`: base-layer lamport-delta settlement into
  the validator fees vault
- `src/processor/fast/commit_state.rs` and `src/processor/fast/finalize.rs`: validator-funded
  temporary commit rent/collateral and its refund
- `src/processor/validator_claim_fees.rs`: claim-time protocol percentage and insufficient-funds path
- `src/processor/top_up_ephemeral_balance.rs`: base-layer escrow funding behavior

Pinned source: [Delegation Program fee constants](https://github.com/magicblock-labs/delegation-program/blob/0c551fa64cd13d6dabc51dbf6d1575bde2d38067/dlp-api/src/consts.rs).
The repository's default branch is now `dlp-v2` (unreleased fraud-proof work); the deployed program
builds from `main`.

### MagicBlock validator

- `magicblock-config/src/consts.rs`: current release ER transaction fee of `0`
- `magicblock-config/src/config/chain.rs`: operator-side base commit compute-unit price setting
- `programs/magicblock/src/magic_sys.rs`: hard commit limit and custom errors
- `programs/magicblock/src/schedule_transactions/mod.rs`: limit enforcement and fee-vault selection
- `magicblock-core/src/intent/mod.rs`: live commit threshold, commit amount, and Base Action formula
- `programs/magicblock/src/schedule_transactions/process_schedule_commit.rs`: legacy scheduling paths
- `programs/magicblock/src/schedule_transactions/process_schedule_intent_bundle.rs`: bundle charging
- `programs/magicblock/src/magic_scheduled_base_intent.rs`: zero flat intent scheduling fee
- `programs/magicblock/src/utils/account_actions.rs`: atomic payer debit and exact failure
- `programs/magicblock/src/schedule_transactions/process_add_action_callback.rs`: flat callback fee
- `magicblock-magic-program-api/src/lib.rs` and `programs/magicblock/src/ephemeral_accounts/mod.rs`:
  refundable ER-only Ephemeral Account rent
- `magicblock-validator-admin/src/claim_fees.rs`: automatic claim threshold and cadence

Pinned source: [validator commit and action fee calculation](https://github.com/magicblock-labs/magicblock-validator/blob/v1.1.1/magicblock-core/src/intent/mod.rs).

## Validator 2.0 changes (release candidate)

As of 2026-11-13, validator `v2.0.0-rc.3` is a draft prerelease with no published binaries, and
every public ER runs `1.1.1`. Its source changes these economics:

- The per-account live commit fee after the threshold rises from `100_000` to `1_000_000` lamports.
- Commit IDs are reserved when the commit is scheduled, so the limit of 10 and the threshold of 25
  count queued commits, not only finalized ones.
- The base-fee setting is removed; ER execution is always free.
- The automatic fee-claim task is removed. Operators run `magicblock claim-fees` on their own
  schedule.

Check `getVersion` (`magicblock-core`) on the target ER before using either set of numbers.
