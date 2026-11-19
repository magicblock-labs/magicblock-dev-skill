# Cranks (Scheduled Tasks)

Cranks let an Ephemeral Rollup schedule recurring execution without an application-operated cron
server. A successful schedule, update, or cancel transaction means the request was accepted and stashed;
the scheduler applies it asynchronously. Product logic must distinguish **request accepted**,
**scheduler change observed**, **iteration attempted**, and **desired state reached**.

## Contents

- [When to use](#when-to-use)
- [Lifecycle](#lifecycle)
- [Current program surface](#current-program-surface)
- [Authorization and identity](#authorization-and-identity)
- [Design for retries and failure](#design-for-retries-and-failure)
- [Validation checklist](#validation-checklist)
- [Hydra cranks](#hydra-cranks)
- [Validator 2.0 (Hydra, devnet-us)](#validator-20-hydra-devnet-us)

## When to use

Use cranks for repeated ER-local work such as game ticks, auctions, queue processing, periodic commits,
or maintenance. Prefer a user transaction when work only needs to happen after an explicit user action.
Prefer an external service when the trigger depends on off-chain data or cross-system orchestration the
ER scheduler cannot observe.

Cranks do not make a non-idempotent instruction safe, do not guarantee an exact wall-clock execution
time, and do not automatically settle changed state to Solana.

## Lifecycle

1. Create and delegate every writable account needed by the scheduled instruction.
2. Build the exact instruction the scheduler will execute, including account metas and data.
3. Submit the schedule request on the ER with a task ID, interval, and finite or deliberately chosen
   iteration count; transaction success records request acceptance, not scheduler registration.
4. Observe the scheduler-applied registration before depending on the task, then observe actual
   iterations and state/log changes separately.
5. Submit update or cancel as the same authority, and observe that the scheduler applied the requested
   change before reporting it complete or releasing target accounts.
6. Commit/undelegate separately when the resulting state must settle to base.

The target accounts must remain available and writable on that ER for every iteration. Undelegating or
closing them while the task remains active creates a predictable failure path; cancel first or make the
scheduled instruction safely detect terminal state.

## Current program surface

Every public ER except devnet-us runs the 1.x line (`getVersion` reports `magicblock-core 1.1.1`,
commit `8886db2`; verified 2026-11-19), whose built-in scheduler executes
`MagicBlockInstruction::ScheduleTask` on the Magic program. devnet-us runs 2.0; see
[Validator 2.0](#validator-20-hydra-devnet-us). Build the CPI with the SDK's
`crank` feature; the `crank` module does not exist without it:

```toml
# Anchor 1.x
ephemeral-rollups-sdk = { version = "0.18.0", features = ["anchor", "crank"] }
# Anchor >=0.28,<1.0: use this line instead (0.18.x and earlier; 0.20 removed anchor-compat)
# ephemeral-rollups-sdk = { version = "0.18.0", features = ["anchor-compat", "crank"] }
```

Keep only the line that matches the program's existing Anchor version; enabling both `anchor` and
`anchor-compat` fails to compile.

```rust
#[allow(deprecated)]
use ephemeral_rollups_sdk::crank::{CancelCrankCpi, ScheduleCrankCpi, ScheduleTaskArgs};
```

`magicblock-engine-examples/crank-counter/anchor` uses this API (from SDK git rev `0fc4604`). Its
`ScheduleCrankCpi` takes the `payer` (signer, first account), the `magic_program`, the scheduled
instruction's accounts, and `ScheduleTaskArgs`. In SDK 0.17 both CPIs are marked deprecated in favour of
`crank::hydra::ephemeral::{create::CreateCrankCpi, cancel::CancelCrankCpi}` (see
[Hydra cranks](#hydra-cranks)); the deprecated path is still the one the live `1.1.1` scheduler runs.

Do not copy the older direct `magicblock-magic-program-api = "0.10.1"` + `bincode` setup with the
signer code below: `0.10.1` has no `crank_signer_pda` function (only a global `CRANK_SIGNER`
constant), and SDK 0.17.3 and 0.18.0 still depend on `0.10.1`. The per-authority `crank_signer_pda`
exists from `0.11` through `1.1.1`; crates.io latest `2.0.0` is the validator 2.0 API, which removed
it. The argument types are signed 64-bit integers:

```rust
pub struct ScheduleTaskArgs {
    pub task_id: i64,
    pub execution_interval_millis: i64,
    pub iterations: i64,
    pub instructions: Vec<Instruction>,
}
```

The cancel surface is `MagicBlockInstruction::CancelTask { task_id }` (`CancelCrankCpi`). These shapes are
unchanged in `magicblock-magic-program-api` `1.1.1`. Verify the exact account list against
`crank-counter/anchor` and the target validator before copying an instruction builder.

Schedule and cancel transactions go to the ER and use an ER blockhash. Keep preflight on: on the ER,
`skipPreflight: true` does not skip a simulation, it only makes `sendTransaction` return before
execution and hide the error. If you skip it, check the ER signature status and logs. The scheduled
inner instruction also executes in that ER.

## Authorization and identity

- A task ID is validator-global within a scheduler instance; the authority is the task's owner, not
  part of its key. Treat `task_id` as the durable identity used for scheduling, rescheduling, and
  cancellation.
- Derive a globally collision-resistant ID from the application, object, and authority (or allocate
  and store one in durable state). Small UI counters can collide with another application's task.
- Verify the pinned scheduler version's authority rules before relying on who may replace, invoke, or
  cancel a task. Do not generalize permissionless behavior from a product-specific queue crank to every
  scheduled task.
- The task authority signs schedule/reschedule and cancel. Scheduled execution does not reuse that
  signature. The only signer a scheduled instruction can carry is the crank signer PDA,
  `crank_signer_pda(&task_authority)`: seeds `[b"crank-executor", task_authority]` under
  `CRANK_PROGRAM_ID` (`Crank11111111111111111111111111111111111111`). The function is
  `magicblock_magic_program_api::pda::crank_signer_pda` from `0.11`; with SDK 0.17.3 or 0.18.0 (which
  pin `0.10.1`), derive it inline with `Pubkey::find_program_address(&[b"crank-executor",
  authority.as_ref()], &CRANK_PROGRAM_ID).0`.
- The scheduler signs for that PDA only when the program lists it. Add
  `AccountMeta::new_readonly(crank_signer_pda(&authority), true)` to the scheduled inner instruction's
  accounts, then validate it in the target handler, for example
  `#[account(address = crank_signer_pda(&state.authority))] pub crank_signer: Signer<'info>`. Without
  that account and check, the scheduled handler is permissionless: anyone can call it directly.
- In every scheduled inner instruction, only that derived crank signer may have `is_signer = true`,
  and its meta must be read-only. The scheduler rejects other inner signer metas and rejects a writable
  crank-signer meta when the task is scheduled.
- If a PDA is the task authority, invoke schedule/cancel with its signer seeds and test that authority
  separately from the derived read-only signer used by the scheduled handler.
- Do not expose an instruction that lets an arbitrary caller schedule arbitrary program instructions.
  Construct the permitted target instruction inside the program and validate its accounts.

Rescheduling an existing `task_id` is an update only when the existing authority authorizes it. A
different authority cannot claim an occupied ID, but because apply is asynchronous the occupied-ID
rejection can occur after the submission transaction succeeded. Wrong-authority cancellation can
similarly be rejected or become a no-op when processed later. Preserve authority and observe the
scheduler-applied registration, update, or removal rather than inferring it from transaction success.

## Design for retries and failure

Scheduled instructions should be idempotent or monotonic. Good patterns include “advance to the next
unprocessed timestamp,” “settle item if pending,” or “return success if already complete.” Fragile
patterns include “increment blindly” or “pay again whenever called” without an execution marker.

Define:

- how late execution may be before it is skipped or caught up;
- whether missed intervals are coalesced or replayed;
- the maximum iterations and who renews them;
- what state records the last successful logical execution;
- behavior when accounts are missing, no longer delegated, underfunded, or locked;
- alerting and manual recovery after repeated failures;
- commit frequency and sponsorship cost if crank-driven mutations settle to base.

Avoid assuming scheduler retries have exactly-once semantics. Application state must prevent duplicate
economic effects.

## Validation checklist

Test:

- schedule on the correct ER, observe asynchronous registration, then observe multiple actual executions;
- duplicate/reschedule under the same ID and authority, including request acceptance before apply;
- task-ID collision from another authority, plus later rejection/no-op of unauthorized reschedule and cancel;
- authorized cancel, observed scheduler removal, and absence of later mutations;
- a direct call to the scheduled handler without the crank signer PDA, which must fail;
- callback instruction failure and subsequent behavior;
- duplicate execution/idempotency;
- late execution and terminal state;
- account undelegation or closure while scheduled;
- finite iteration exhaustion;
- commit/undelegation after the task is stopped.

Working example: `magicblock-engine-examples/crank-counter/anchor`. It demonstrates scheduling and
execution with a deliberately permissionless `increment`; add the lifecycle and failure tests above.

MagicSVM `0.3.0` runs this `1.1.1` model in process: `ScheduleTask`/`CancelTask` with the validator's
validation, executions on their millisecond deadlines in `warp_to_slot`, retries with the validator's
backoff, same-ID replacement, and ignored reschedule/cancel from another authority. Use it for the
checklist items above that don't need a live scheduler (see
[local-development.md](local-development.md#magicsvm) and the example's `tests-magicsvm-rs/`); it does
not model Hydra or validator 2.0.

Pinned scheduler source (validator `v1.1.1`; the live 1.x ERs run V1 head `8886db2`, where the
crank-signer and task-ID rules above were re-tested on 2026-11-19; `master` is the 2.0 line):
[inner signer validation](https://github.com/magicblock-labs/magicblock-validator/blob/v1.1.1/programs/magicblock/src/schedule_task/mod.rs) and
[scheduled execution](https://github.com/magicblock-labs/magicblock-validator/blob/v1.1.1/programs/magicblock/src/schedule_task/process_execute_task.rs).

## Hydra cranks

Hydra is MagicBlock's permissionless crank runner (`magicblock-labs/hydra`, crate `hydra-api` `0.2.1`;
the SDK `crank` feature re-exports it as `crank::hydra::{base, ephemeral}`). A cranker sends a
top-level `Trigger` followed by the scheduled instructions; `Trigger` checks them against the bytes
stored on the crank PDA, pays the cranker, and advances the schedule. The scheduled instructions run
top-level, not through CPI.

| Program | Address | Last deployed (verified 2026-11-13) |
|---|---|---|
| Base | `Hydra17i1feui9deaxu6d1TzSQMRNHeBRkDR1Awy7zea` | 2026-05-01 (Mainnet and Devnet) |
| Ephemeral (crank lives as an ephemeral account on the ER) | `eHyd5BU8QffvHi4GnXwxrK4WpS7pM2x9UGKHBWii7mf` | 2026-08-26 (Mainnet and Devnet) |

- Up to 16 scheduled instructions per crank (`MAX_INSTRUCTIONS`), 32 accounts, 1,024 data bytes.
- Scheduled instructions cannot carry signer metas. A preceding `Trigger` alone is not
  authorization: anyone can create and trigger their own crank that schedules your instruction. A
  handler that needs crank-only authority must take the instructions sysvar and reject unless
  `ix[k-1-j]` has the Hydra program ID, the `Trigger` discriminator, and, as its first account, the
  expected crank PDA, where `j` is the handler's 0-based position in its crank's scheduled list.
  The cranker sends `Trigger` and then every scheduled instruction contiguously and in order, and
  `Trigger` byte-matches that whole run against the stored template, so `ix[k-1]` is the `Trigger`
  only for the first scheduled instruction. Check the fixed position `j` your program scheduled the
  handler at; do not scan back to the nearest `Trigger`, because a cranker can append unbound
  instructions after the scheduled run. Derive the expected PDA with the seeds your crank was created with: the
  ephemeral program accepts both the payer-bound `[b"crank", payer, seed]` (preferred) and the
  legacy `[b"crank", seed]`; the deployed base program supports only the legacy seeds until it is
  redeployed. Cranks that the 2.0 validator creates from `ScheduleTask` use fixed legacy seeds and the
  validator as header authority; see [Validator 2.0](#validator-20-hydra-devnet-us). A read-only crank meta in the scheduled instruction can never match, because `Trigger`
  makes the crank writable for the whole transaction.
- When the schedule's creator matters, use the payer-bound seeds and derive the expected PDA from
  the expected payer: the payer must sign `Create` (it funds the account on base, and it is the
  ephemeral account sponsor on the ER), so the PDA check proves who created the crank. To check the header instead
  (`hydra_api::state::load_crank`, `authority == expected_authority`, `authority_signer == 1`), the
  handler needs the crank as an account. Hydra's README says not to list it, but `Create` does not
  reject it, and a meta stored as writable matches the promoted flag. This is untested; prefer the
  payer-bound PDA check.
- Base layer: each trigger pays the cranker 10,000 lamports plus `priority_tip` from the crank's
  balance. ER: the flat reward is `0`, so `priority_tip` is the cranker's only incentive.
- Something must run `hydra-cranker` (published as `@magicblock-labs/hydra-cranker-<platform>` npm
  packages, `--ephemeral` for ER cranks). It is not confirmed that MagicBlock runs a public cranker for
  ephemeral cranks; run your own or confirm before relying on one.
- The base program has not been redeployed since 2026-05-01, so multi-instruction cranks (hydra #6)
  and the payer-bound crank PDA (#30) in `hydra-api` 0.2.x are not live on base. Do not use
  `crank::hydra::base` against the deployed base program until it is redeployed.

## Validator 2.0 (Hydra, devnet-us)

Validator 2.0 is released (`v2.0.0` 2026-11-16; `v2.0.2` is GitHub Latest and npm `latest` is
`2.0.1` on 2026-11-19). devnet-us runs it (`getVersion` reports `core 2.0.0`, commit `9456c18`), and
the devnet router can place delegations there. It replaces the built-in scheduler with Hydra.
Verified against `9456c18` on 2026-11-19:

- `ScheduleTask` is forwarded to a `hydra-ephemeral` crank. `crank_signer_pda` and `ExecuteCrank` are
  removed (`ExecuteCrank` fails with "crank execution is handled by hydra"), and any signer meta in a
  scheduled instruction is rejected. The 1.1.1 pattern above (a read-only `crank_signer_pda` signer
  meta) therefore fails `ScheduleTask` with `MissingRequiredSignature`.
- Privileged handlers must authenticate the Hydra `Trigger` at their fixed position and its crank
  (program ID, discriminator, and expected crank PDA), as described in
  [Hydra cranks](#hydra-cranks). Checking only that a `Trigger` precedes the handler, which is all the
  `crank-counter` example comment describes, is not enough.
- A crank the validator creates from `ScheduleTask` uses the legacy unscoped PDA
  `[b"crank", sha256(task_authority ‖ task_id.to_le_bytes())]` under `eHyd5…`
  (`hydra_api` `ephemeral::find_crank_pda`), not the payer-bound form. Its header `authority` is the
  ER validator identity (the sponsor), `authority_signer == 1`, and `priority_tip == 0`. Derive the
  expected PDA from those seeds and expect the validator identity as header authority. A handler that
  requires its own program authority there rejects every validator-created crank. The legacy seeds do
  not bind the sponsor, so whether a third party can pre-create a crank at that address is unverified;
  do not rely on the PDA check alone.
- Task IDs are namespaced per authority (the PDA hashes the authority and `task_id`), so the collision
  guidance above no longer applies.
- Intervals round up to whole slots (minimum one).
- Cancelling a task that was never scheduled succeeds on the ER. The Hydra cancel that the scheduler
  sends afterwards is what fails, asynchronously and invisibly to the caller, so observe removal as on
  1.1.1.
- Tasks fire only while a `hydra-cranker` runs, and validator-created cranks pay it no tip. Whether
  MagicBlock runs one for devnet-us is unconfirmed. Locally, use `mb-stack --cranker` with
  `MB_STACK_CRANKER_KEYPAIR` set to a keypair funded on the ER.

Keep the `1.1.1` model above for ERs that report `magicblock-core 1.1.1`. Check `getVersion` on the
target ER: 2.0 reports its version under `core`.
