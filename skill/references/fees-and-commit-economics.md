# Fees and Commit Economics

Read this guide first for any question about ER transaction cost, delegation deposits, commit
sponsorship, `magic_fee_vault`, refunds, fee-payer top-ups, Magic Action charges, or validator fee
claims. The active model is split between the Delegation Program on Solana and the MagicBlock
validator. Reading either repository alone gives an incomplete answer.

Values below were source-verified on 2026-08-20 against:

- Delegation Program `main` at `6898ef4b82ba1f2b6fbb5d91eca578729edbbeb8`
- MagicBlock validator release `master` at `cec4cf574ace267029e9487b61780d5218256b42`

Do not call commits "free" merely because no lamports move during the scheduling instruction. A
commit can consume the fee budget held in delegation PDAs and be charged later at undelegation.

## Cost buckets

| Bucket | Active amount | When it is charged | Source of funds |
|---|---:|---|---|
| ER signature fee | Validator-configurable; release default is `0` | Every executed ER transaction | ER transaction fee payer |
| Intent scheduling fee | `0` | When an intent bundle is scheduled | No standalone debit |
| Delegation session fee | `300_000` lamports | Delegation cleanup at undelegation | Delegation record + metadata PDAs |
| Delegation commit fee | `100_000` lamports for each finalized commit after the first | Delegation cleanup at undelegation | Delegation record + metadata PDAs, capped by their combined balance |
| Extra live commit fee | `100_000` lamports per committed account once its current nonce is at least `25` | When the ER schedules the next commit through the fee-vault path | Delegated fee payer on the ER |
| Base Action fee | `50_000` micro-lamports per requested CU | When an intent bundle is scheduled through the fee-vault path | Delegated fee payer on the ER |
| Add-callback fee | `5_000` lamports per callback attachment instruction | When `AddActionCallback` succeeds | Delegated fee payer on the ER |
| Ephemeral Account rent | `32 * (data_len + 60)` lamports | Create/grow; refunded on shrink/close | Ephemeral Account sponsor on the ER |

Base-layer Solana transaction fees for delegation, top-up, settlement, or other base transactions are
separate. Product-specific charges in other programs, such as the Ephemeral SPL Token sponsored
lamports-transfer setup charge, are also separate.

## 1. ER transaction signature fee

The validator's release configuration defaults `validator.basefee` to `0`. The runtime computes the
signature fee as:

```text
number of transaction signatures * configured basefee
```

The value is configurable by a validator operator, so `0` is a default, not a protocol invariant for
every public, private, or dedicated deployment. Query the target validator when an exact runtime cost
matters.

This ordinary ER signature fee is independent of commit, delegation, and Magic Action fees.

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
requested_fee = 300_000 + 100_000 * commit_count
collectible_fee = min(
  requested_fee,
  delegation_record_lamports + delegation_metadata_lamports
)
refund = combined_delegation_PDA_lamports - collectible_fee
```

Consequences:

- A session with no finalized commit still requests the `300_000`-lamport session fee.
- Commit 1 adds no commit fee.
- Commits 2, 3, and so on add `100_000` lamports each.
- Collection is capped by the two PDA balances. An exhausted deposit does not cause
  `InsufficientFunds`, and this path does not record the remainder as debt.
- Every unused lamport is returned to the `rent_payer` stored at delegation time, not necessarily to
  the current account authority or the transaction payer that requested undelegation.

`RENT_FEES_PERCENTAGE = 10` still exists in `dlp-api/src/consts.rs`, but the active cleanup path does
not reference it. Do not calculate the session charge as 10% of rent. The current cleanup uses the
fixed session/commit formula above and uses `PROTOCOL_FEES_PERCENTAGE = 10` only for distribution.

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
cleanup request = 300_000 + 100_000 * (1 - 1)
                = 300_000
cleanup charge  = min(D, 300_000)
refund          = D - cleanup charge
live commit fee = 0
```

### One account, ten plain commits, then undelegate

All ten are allowed by the no-vault path because the check happens against the current nonce before
the next commit.

```text
cleanup request = 300_000 + 100_000 * (10 - 1)
                = 1_200_000
cleanup charge  = min(D, 1_200_000)
refund          = D - cleanup charge
live commit fee = 0
```

An eleventh plain commit sees current nonce `10` and hard-fails with `0xA0000000`. Commit-and-
undelegate remains available so the account can exit.

### One account, 26 commits through the fee-vault path

```text
cleanup request       = 300_000 + 100_000 * (26 - 1)
                      = 2_800_000
cleanup charge        = min(D, 2_800_000)
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

## Funding a delegated fee payer

The validator does not automatically refill an application's delegated payer. Before scheduling a
billable bundle, ensure its ER balance covers:

```text
per-account live commit fees
+ Base Action fees
+ callback attachment fee, if sent separately
+ any configured ER signature fee
+ application safety buffer
```

Use `lamportsDelegatedTransferIx` for the SDK's sponsored base-to-ER top-up flow. Read
[lamports-topup.md](lamports-topup.md) for its routing, salt, setup-charge, and retry rules. Its current
`300_000`-lamport setup charge comes from the Ephemeral SPL Token program and must not be confused with
the Delegation Program's `300_000`-lamport session fee.

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
| Validator claims more than its base vault holds above rent | `InsufficientFunds` |

## Pending changes are not active pricing

[MIMD-0030](https://github.com/magicblock-labs/magicblock-validator/discussions/1580) is an open
proposal to raise both active fixed charges by 10x:

- session fee: `300_000` to `3_000_000` lamports;
- commit fee: `100_000` to `1_000_000` lamports.

It proposes retaining roughly today's upfront delegation funding after Solana rent reductions so the
reduced rent portion becomes fee budget. The pinned Delegation Program and validator constants above
still contain the current lower values, so do not quote the proposal as deployed behavior.

The proposal is motivated by
[SIMD-0437](https://github.com/solana-foundation/solana-improvement-documents/blob/main/proposals/0437-incremental-rent-reduction.md).
The SIMD document currently labels itself `status: Idea`. Verify the live feature/rent state and both
repositories before changing production estimates.

## How to verify current behavior

Check both repositories, because matching numeric constants do not prove matching enforcement:

### Delegation Program

- `dlp-api/src/consts.rs`: fixed session/commit amounts, protocol percentage, declared but unused
  `RENT_FEES_PERCENTAGE`, zero-data rent exception
- `src/processor/fast/undelegate.rs`: after-first commit count, capped cleanup request
- `src/processor/fast/utils/pda.rs`: refund destination and cleanup split
- `src/processor/fast/internal/commit_finalize_internal.rs`: base-layer lamport-delta settlement into
  the validator fees vault
- `src/processor/fast/commit_state.rs` and `src/processor/fast/finalize.rs`: validator-funded
  temporary commit rent/collateral and its refund
- `src/processor/validator_claim_fees.rs`: claim-time protocol percentage and insufficient-funds path
- `src/processor/top_up_ephemeral_balance.rs`: base-layer escrow funding behavior

Pinned source: [Delegation Program fee constants](https://github.com/magicblock-labs/delegation-program/blob/6898ef4b82ba1f2b6fbb5d91eca578729edbbeb8/dlp-api/src/consts.rs).

### MagicBlock validator

- `magicblock-config/src/consts.rs`: release default ER base fee
- `magicblock-config/src/config/chain.rs`: operator-side base commit compute-unit price setting
- `magicblock-processor/src/executor/processing.rs`: signature-fee formula
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

Pinned source: [validator commit and action fee calculation](https://github.com/magicblock-labs/magicblock-validator/blob/cec4cf574ace267029e9487b61780d5218256b42/magicblock-core/src/intent/mod.rs).
