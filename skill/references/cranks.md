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
- [Validator 2.0 (release candidate, not live)](#validator-20-release-candidate-not-live)

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

Public ERs run validator `1.1.1` (verified 2026-11-13 with `getVersion`), whose built-in scheduler
executes `MagicBlockInstruction::ScheduleTask` on the Magic program. Build the CPI with the SDK's
`crank` feature; the `crank` module does not exist without it:

```toml
ephemeral-rollups-sdk = { version = "0.17.3", features = ["anchor", "crank"] }
```

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
constant), and SDK 0.17.3 still depends on `0.10.1`. The per-authority `crank_signer_pda` exists from
`0.11` (latest `1.1.1`). The argument types are signed 64-bit integers:

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

Schedule and cancel transactions go to the ER and use an ER blockhash. Use `skipPreflight: true` only
when that ER cannot simulate the scheduler CPI faithfully, then inspect execution logs. The scheduled
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
  `magicblock_magic_program_api::pda::crank_signer_pda` from `0.11`; with SDK 0.17.3 (which pins
  `0.10.1`), derive it inline with `Pubkey::find_program_address(&[b"crank-executor",
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

Pinned scheduler source (validator `v1.1.1`, the live version; `master` is now the 2.0 line):
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
- Scheduled instructions cannot carry signer metas. A handler that needs crank-only authority must
  authenticate the preceding Hydra `Trigger` through the instructions sysvar.
- Base layer: each trigger pays the cranker 10,000 lamports plus `priority_tip` from the crank's
  balance. ER: the flat reward is `0`, so `priority_tip` is the cranker's only incentive.
- Something must run `hydra-cranker` (published as `@magicblock-labs/hydra-cranker-<platform>` npm
  packages, `--ephemeral` for ER cranks). It is not confirmed that MagicBlock runs a public cranker for
  ephemeral cranks; run your own or confirm before relying on one.
- The base program has not been redeployed since 2026-05-01, so multi-instruction cranks (hydra #6)
  and the payer-bound crank PDA (#30) in `hydra-api` 0.2.x are not live on base. Do not use
  `crank::hydra::base` against the deployed base program until it is redeployed.

## Validator 2.0 (release candidate, not live)

Validator `v2.0.0-rc.3` (draft prerelease, no published binaries) replaces the built-in scheduler with
Hydra. When 2.0 ships:

- `ScheduleTask` is forwarded to a `hydra-ephemeral` crank. `crank_signer_pda` and `ExecuteCrank` are
  removed (`ExecuteCrank` fails with "crank execution is handled by hydra"), and any signer meta in a
  scheduled instruction is rejected. Privileged handlers must check the preceding Hydra `Trigger`
  through the instructions sysvar, as the `crank-counter` example comment describes.
- The crank PDA is derived from `authority` and `task_id`, so task IDs are scoped per authority and
  the collision guidance above no longer applies.
- Intervals round up to whole slots (minimum one), and cancelling a crank that doesn't exist fails.
- Tasks fire only while a `hydra-cranker` runs; locally, `mb-stack --cranker` with
  `MB_STACK_CRANKER_KEYPAIR` set to a keypair funded on the ER.

Keep the `1.1.1` model above for live ERs until the target validator reports 2.0 in `getVersion`.
