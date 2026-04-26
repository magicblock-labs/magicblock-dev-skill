# Magic Actions (Post-Commit Actions)

Magic Actions are base-layer instructions that are scheduled inside an ER
transaction and executed atomically once the commit is sealed back to the
base layer. They let an ER-side instruction trigger arbitrary base-layer
work — updating a leaderboard, distributing rewards, transferring SPL
tokens — without a separate user transaction or external relayer.

## When to use

- After committing ER state, run a follow-up base-layer instruction in the
  same atomic unit (e.g., update a global leaderboard once a player's score
  is committed).
- Atomically commit + undelegate + execute side-effects in one ER transaction.
- PDA-driven flows where a delegated account needs to dispatch base-layer
  side-effects without a user signature.

If you just want to commit state, use `MagicIntentBundleBuilder.commit(...)`
without any actions — see [delegation.md](delegation.md). Magic Actions are
specifically for *follow-up base-layer instructions chained to a commit*.

## Imports

```rust
use ephemeral_rollups_sdk::ephem::{CallHandler, MagicIntentBundleBuilder};
use ephemeral_rollups_sdk::{ActionArgs, ShortAccountMeta};
```

## Action Handler Instruction (target of the call)

Mark the base-layer instruction that the action will invoke with the
`#[action]` attribute on its accounts context. This declares the instruction
as callable from a post-commit action.

```rust
pub fn update_leaderboard(ctx: Context<UpdateLeaderboard>) -> Result<()> {
    let leaderboard = &mut ctx.accounts.leaderboard;
    let counter_info = &mut ctx.accounts.counter.to_account_info();
    let mut data: &[u8] = &counter_info.try_borrow_data()?;
    let counter = Counter::try_deserialize(&mut data)?;

    if counter.count > leaderboard.high_score {
        leaderboard.high_score = counter.count;
    }
    Ok(())
}

#[action]
#[derive(Accounts)]
pub struct UpdateLeaderboard<'info> {
    #[account(mut, seeds = [LEADERBOARD_SEED], bump)]
    pub leaderboard: Account<'info, Leaderboard>,
    /// CHECK: PDA owner depends on whether it is delegated; access pattern
    /// validates this at the call site.
    pub counter: UncheckedAccount<'info>,
}
```

## Schedule a Commit + Action from the ER

Build a `CallHandler` describing the base-layer instruction, then attach it
to a `MagicIntentBundleBuilder` via `add_post_commit_actions`:

```rust
pub fn commit_and_update_leaderboard(
    ctx: Context<CommitAndUpdateLeaderboard>,
) -> Result<()> {
    let instruction_data =
        anchor_lang::InstructionData::data(&crate::instruction::UpdateLeaderboard {});
    let action_args = ActionArgs::new(instruction_data);
    let action_accounts = vec![
        ShortAccountMeta {
            pubkey: ctx.accounts.leaderboard.key(),
            is_writable: true,
        },
        ShortAccountMeta {
            pubkey: ctx.accounts.counter.key(),
            is_writable: false,
        },
    ];
    let action = CallHandler {
        destination_program: crate::ID,
        accounts: action_accounts,
        args: action_args,
        // Signer that pays transaction fees for the action from its escrow PDA
        escrow_authority: ctx.accounts.payer.to_account_info(),
        compute_units: 200_000,
    };

    MagicIntentBundleBuilder::new(
        ctx.accounts.payer.to_account_info(),
        ctx.accounts.magic_context.to_account_info(),
        ctx.accounts.magic_program.to_account_info(),
    )
    .commit(&[ctx.accounts.counter.to_account_info()])
    .add_post_commit_actions([action])
    .build_and_invoke()?;
    Ok(())
}

#[commit]
#[derive(Accounts)]
pub struct CommitAndUpdateLeaderboard<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(mut, seeds = [COUNTER_SEED], bump)]
    pub counter: Account<'info, Counter>,

    /// CHECK: Leaderboard PDA — writable flag is set inside the action accounts list.
    #[account(seeds = [LEADERBOARD_SEED], bump)]
    pub leaderboard: UncheckedAccount<'info>,
}
```

## Multiple Actions

`add_post_commit_actions` takes an `IntoIterator` — pass a slice or array
literal. Actions execute sequentially in the order passed.

```rust
MagicIntentBundleBuilder::new(
    ctx.accounts.payer.to_account_info(),
    ctx.accounts.magic_context.to_account_info(),
    ctx.accounts.magic_program.to_account_info(),
)
.commit(&[
    ctx.accounts.counter.to_account_info(),
    // ... additional committed accounts
])
.add_post_commit_actions([action_1, action_2, action_3])
.build_and_invoke()?;
```

## Commit-and-Undelegate with Actions

Actions can be chained onto undelegation as well. The counter commits,
undelegates, and the actions run — all atomically in one ER transaction.

```rust
MagicIntentBundleBuilder::new(
    ctx.accounts.payer.to_account_info(),
    ctx.accounts.magic_context.to_account_info(),
    ctx.accounts.magic_program.to_account_info(),
)
.commit_and_undelegate(&[ctx.accounts.counter.to_account_info()])
.add_post_commit_actions([action])
.build_and_invoke()?;
```

## PDA-Signed Actions (escrow authority)

When the action's `escrow_authority` is a PDA (not a user wallet), use
`build_and_invoke_signed` and pass the PDA's seeds. This pattern is common
when the ER-side caller is itself a PDA dispatching base-layer side-effects
on behalf of users. As with any intent bundle, the **payer** and the
**committed accounts** are independent — they may be the same PDA (as in
the example below, where the reward distributor pays for and commits its
own state) or different accounts entirely.

```rust
let payer_seeds: &[&[u8]] = &[REWARD_LIST_SEED, distributor_key.as_ref(), &[bump]];

MagicIntentBundleBuilder::new(
    reward_list.to_account_info(),                       // payer (PDA)
    magic_context.to_account_info(),
    magic_program.to_account_info(),
)
.magic_fee_vault(magic_fee_vault.to_account_info())      // see commit-sponsorship section in delegation.md
.commit(&[reward_list.to_account_info()])                // committed account(s) — can differ from payer
.add_post_commit_actions([action])
.build_and_invoke_signed(&[payer_seeds])?;
```

## CallHandler Field Reference

| Field | Type | Description |
|---|---|---|
| `destination_program` | `Pubkey` | Program ID that will execute the action on base layer. Almost always your own `crate::ID`. |
| `accounts` | `Vec<ShortAccountMeta>` | Accounts the action needs. Set `is_writable: true` for any account the action mutates. |
| `args` | `ActionArgs` | Encoded instruction data — typically `ActionArgs::new(anchor_lang::InstructionData::data(&...))`. |
| `escrow_authority` | `AccountInfo` | Signer that pays transaction fees for the action from an escrow PDA. Use the user's wallet for user-paid flows; use a PDA + `build_and_invoke_signed` for program-paid flows. |
| `compute_units` | `u32` | Base-layer compute budget for this action. `200_000` is a reasonable default; increase for heavy actions. |

## Common Gotchas

### `#[action]` is required on the target instruction's accounts context
Without `#[action]`, the SDK can't dispatch into the instruction from a
post-commit action. This is the most common cause of "action target not
callable" errors.

### `is_writable` must match the action's actual writes
`ShortAccountMeta { is_writable: true }` for any account the action mutates,
even if the same account also appears in the outer `#[commit]` context with a
different mutability. The two contexts are independent — the action accounts
list is what the base-layer transaction sees.

### Use `[action]` (slice/array) not `vec![action]`
`add_post_commit_actions` takes `IntoIterator<Item = CallHandler>`. Array
literals are the cleaner form: `.add_post_commit_actions([action])`.

### PDA escrow authority needs `build_and_invoke_signed`
If `escrow_authority` is a PDA, the outer call must provide PDA seeds via
`build_and_invoke_signed(payer_seeds)`. Calling `build_and_invoke()` (without
`_signed`) will fail signature verification at action execution time.

### Compute units are per-action, not per-bundle
Each action gets its own compute budget. If you chain three actions at
200,000 CU each, you're declaring 600,000 total. Increase if any individual
action does heavy work.

## Best Practices

### Do's
- Use Magic Actions for atomic ER-commit + base-layer follow-ups
- Keep `escrow_authority` consistent — user wallet for user-paid, PDA for program-paid
- Pair `add_post_commit_actions` with `commit_and_undelegate` when the
  follow-up should run as part of the release path
- Set realistic `compute_units` — match the action's actual work

### Don'ts
- Don't use Magic Actions for ER-only state changes — `MagicIntentBundleBuilder.commit(...)` alone is sufficient
- Don't forget `#[action]` on the target instruction's accounts context
- Don't mix up `is_writable` between the outer `#[commit]` context and the action's accounts list — they serve different transactions
- Don't call `build_and_invoke()` when the escrow authority is a PDA
