# Cranks (Scheduled Tasks)

Cranks enable automatic, recurring transactions on Ephemeral Rollups without external infrastructure.

## Additional Dependencies

```toml
[dependencies]
magicblock-magic-program-api = { version = "0.3.1", default-features = false }
bincode = "^1.3"
sha2 = "0.10"
```

## Crank Imports

```rust
use anchor_lang::solana_program::{
    instruction::{AccountMeta, Instruction},
    program::invoke_signed,
};
use ephemeral_rollups_sdk::consts::MAGIC_PROGRAM_ID;
use magicblock_magic_program_api::{args::ScheduleTaskArgs, instruction::MagicBlockInstruction};
```

## Crank Arguments

```rust
#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct ScheduleCrankArgs {
    pub task_id: u64,                    // Unique task identifier
    pub execution_interval_millis: u64,  // Milliseconds between executions
    pub iterations: u64,                 // Number of times to execute
}
```

## Schedule Crank Instruction

```rust
pub fn schedule_my_crank(ctx: Context<ScheduleCrank>, args: ScheduleCrankArgs) -> Result<()> {
    let crank_ix = Instruction {
        program_id: crate::ID,
        accounts: vec![AccountMeta::new(ctx.accounts.my_account.key(), false)],
        data: anchor_lang::InstructionData::data(&crate::instruction::MyCrankInstruction {}),
    };

    let ix_data = bincode::serialize(&MagicBlockInstruction::ScheduleTask(ScheduleTaskArgs {
        task_id: args.task_id,
        execution_interval_millis: args.execution_interval_millis,
        iterations: args.iterations,
        instructions: vec![crank_ix],
    })).map_err(|_| ProgramError::InvalidArgument)?;

    let schedule_ix = Instruction::new_with_bytes(
        MAGIC_PROGRAM_ID,
        &ix_data,
        vec![
            AccountMeta::new(ctx.accounts.payer.key(), true),
            AccountMeta::new(ctx.accounts.my_account.key(), false),
        ],
    );

    invoke_signed(&schedule_ix, &[
        ctx.accounts.payer.to_account_info(),
        ctx.accounts.my_account.to_account_info(),
    ], &[])?;

    Ok(())
}
```

## Client-Side Crank Scheduling

```typescript
import { MAGIC_PROGRAM_ID } from "@magicblock-labs/ephemeral-rollups-sdk";

// CRITICAL: Send to Ephemeral Rollup (not base layer)
const tx = await program.methods
  .scheduleMyCrank({
    taskId: new BN(1),
    executionIntervalMillis: new BN(100),
    iterations: new BN(10),
  })
  .accounts({
    magicProgram: MAGIC_PROGRAM_ID,
    payer: erProvider.wallet.publicKey,
    program: program.programId,
  })
  .transaction();
```

## Key Points

- Cranks run automatically on the Ephemeral Rollup
- No external infrastructure needed (no servers, no cron jobs)
- Schedule transactions must be sent to the Ephemeral Rollup, not base layer
- `task_id` must be unique per scheduled task
- `execution_interval_millis` controls timing between executions
- `iterations` controls how many times the task runs
