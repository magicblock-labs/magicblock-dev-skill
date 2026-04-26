# Delegation Patterns (Rust Programs)

## Rust Program Setup

### Dependencies

```toml
# Cargo.toml
[dependencies]
anchor-lang = { version = "0.32.1", features = ["init-if-needed"] }
ephemeral-rollups-sdk = { version = "0.11.2", features = ["anchor", "disable-realloc"] }

# Add the access-control feature for Private Ephemeral Rollups (PER)
# ephemeral-rollups-sdk = { version = "0.11.2", features = ["anchor", "disable-realloc", "access-control"] }
```

### Imports

```rust
use anchor_lang::prelude::*;
use ephemeral_rollups_sdk::anchor::{commit, delegate, ephemeral};
use ephemeral_rollups_sdk::cpi::DelegateConfig;
use ephemeral_rollups_sdk::ephem::MagicIntentBundleBuilder;
```

> **SDK 0.11+ note:** the free functions `commit_accounts` and
> `commit_and_undelegate_accounts` are deprecated. All commit / undelegate
> intents are now scheduled through `MagicIntentBundleBuilder`. The builder
> exposes inherent `build`, `build_and_invoke`, and `build_and_invoke_signed`
> methods for Anchor; native Rust call sites must additionally
> `use ephemeral_rollups_sdk::ephem::FoldableIntentBuilder;`.

### Program Macros

```rust
#[ephemeral]  // REQUIRED: Add before #[program]
#[program]
pub mod my_program {
    // ...
}
```

## Delegate Instruction

```rust
pub fn delegate(ctx: Context<DelegateInput>, uid: String) -> Result<()> {
    // Method name is `delegate_<field_name>` based on the account field
    ctx.accounts.delegate_my_account(
        &ctx.accounts.payer,
        &[b"seed", uid.as_bytes()],  // PDA seeds
        DelegateConfig::default(),
    )?;
    Ok(())
}

#[delegate]  // Adds delegation accounts automatically
#[derive(Accounts)]
#[instruction(uid: String)]
pub struct DelegateInput<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    /// CHECK: The PDA to delegate
    #[account(mut, del, seeds = [b"seed", uid.as_bytes()], bump)]
    pub my_account: AccountInfo<'info>,  // Use AccountInfo with `del` constraint
}
```

## Commit Without Undelegating

```rust
pub fn commit(ctx: Context<CommitState>) -> Result<()> {
    MagicIntentBundleBuilder::new(
        ctx.accounts.payer.to_account_info(),
        ctx.accounts.magic_context.to_account_info(),
        ctx.accounts.magic_program.to_account_info(),
    )
    .commit(&[ctx.accounts.my_account.to_account_info()])
    .build_and_invoke()?;
    Ok(())
}
```

## Undelegate Instruction

```rust
pub fn undelegate(ctx: Context<Undelegate>) -> Result<()> {
    MagicIntentBundleBuilder::new(
        ctx.accounts.payer.to_account_info(),
        ctx.accounts.magic_context.to_account_info(),
        ctx.accounts.magic_program.to_account_info(),
    )
    .commit_and_undelegate(&[ctx.accounts.my_account.to_account_info()])
    .build_and_invoke()?;
    Ok(())
}

#[commit]  // Adds magic_context and magic_program automatically
#[derive(Accounts)]
pub struct Undelegate<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(mut)]
    pub my_account: Account<'info, MyAccount>,
}
```

## Private Ephemeral Rollups (PER): Delegating with Permissions

For Private Ephemeral Rollups, accounts are delegated alongside a **permission account**
that gates who can interact with the account inside the TEE-backed validator.
The recommended pattern is to **create, delegate, and manage permissions in a single
atomic instruction** that combines the permission lifecycle with the account delegation.

**Why delegate the permission account itself?**
Once the permission account is delegated to the ER, member updates execute on the ER
in milliseconds instead of going through a base-layer transaction. This makes
permission changes — adding/removing members, rotating authorities, granting
read access — fast enough for interactive UX. The permission account behaves
like any other delegated account: low-latency writes on the ER, periodic
commits back to the base layer.

### Imports

```rust
use ephemeral_rollups_sdk::access_control::instructions::{
    CommitAndUndelegatePermissionCpiBuilder, CreatePermissionCpiBuilder,
    DelegatePermissionCpiBuilder, UpdatePermissionCpiBuilder,
};
use ephemeral_rollups_sdk::access_control::structs::{Member, MembersArgs, PERMISSION_SEED};
use ephemeral_rollups_sdk::consts::PERMISSION_PROGRAM_ID;
use ephemeral_rollups_sdk::ephem::MagicIntentBundleBuilder;
```

### Atomic Delegate (create permission + delegate permission + delegate account)

```rust
pub fn delegate(
    ctx: Context<DelegatePrivately>,
    members: Option<Vec<Member>>,
) -> Result<()> {
    let validator = ctx.accounts.validator.as_ref();

    // 1. Create the permission account (skip if it already exists).
    if ctx.accounts.permission.data_is_empty() {
        CreatePermissionCpiBuilder::new(&ctx.accounts.permission_program)
            .permissioned_account(&ctx.accounts.my_account.to_account_info())
            .permission(&ctx.accounts.permission.to_account_info())
            .payer(&ctx.accounts.payer.to_account_info())
            .system_program(&ctx.accounts.system_program.to_account_info())
            .args(MembersArgs { members })
            .invoke_signed(&[&[ACCOUNT_SEED, &[ctx.bumps.my_account]]])?;
    }

    // 2. Delegate the permission account itself (skip if already delegated).
    //    This is what makes permission updates fast: once delegated, member
    //    changes run on the ER instead of base layer.
    if ctx.accounts.permission.owner != &ephemeral_rollups_sdk::id() {
        DelegatePermissionCpiBuilder::new(&ctx.accounts.permission_program.to_account_info())
            .permissioned_account(&ctx.accounts.my_account.to_account_info(), true)
            .permission(&ctx.accounts.permission.to_account_info())
            .payer(&ctx.accounts.payer.to_account_info())
            .authority(&ctx.accounts.my_account.to_account_info(), false)
            .system_program(&ctx.accounts.system_program.to_account_info())
            .owner_program(&ctx.accounts.permission_program.to_account_info())
            .delegation_buffer(&ctx.accounts.buffer_permission.to_account_info())
            .delegation_metadata(&ctx.accounts.delegation_metadata_permission.to_account_info())
            .delegation_record(&ctx.accounts.delegation_record_permission.to_account_info())
            .delegation_program(&ctx.accounts.delegation_program.to_account_info())
            .validator(validator)
            .invoke_signed(&[&[ACCOUNT_SEED, &[ctx.bumps.my_account]]])?;
    }

    // 3. Delegate the permissioned account (skip if already delegated).
    if ctx.accounts.my_account.owner != &ephemeral_rollups_sdk::id() {
        ctx.accounts.delegate_my_account(
            &ctx.accounts.payer,
            &[ACCOUNT_SEED],
            DelegateConfig {
                validator: validator.map(|v| v.key()),
                ..Default::default()
            },
        )?;
    }
    Ok(())
}
```

### Updating Permissions on the ER

Because the permission account is delegated, member updates run inside the
ER and confirm in milliseconds. Use `UpdatePermissionCpiBuilder` from any
ER-side instruction:

```rust
UpdatePermissionCpiBuilder::new(&ctx.accounts.permission_program.to_account_info())
    .authority(&ctx.accounts.payer.to_account_info(), true)
    .permissioned_account(&ctx.accounts.my_account.to_account_info(), true)
    .permission(&ctx.accounts.permission.to_account_info())
    .args(MembersArgs { members: Some(new_members) })
    .invoke_signed(&[&[ACCOUNT_SEED, &[ctx.bumps.my_account]]])?;
```

### Atomic Undelegate (release permission + commit/undelegate account)

`undelegate` mirrors `delegate`: both the permission account and the
permissioned account are released in a single ER transaction.

```rust
pub fn undelegate(ctx: Context<UndelegatePrivately>) -> Result<()> {
    // 1. Commit and undelegate the permission account.
    CommitAndUndelegatePermissionCpiBuilder::new(
        &ctx.accounts.permission_program.to_account_info(),
    )
    .authority(&ctx.accounts.payer.to_account_info(), true)
    .permissioned_account(&ctx.accounts.my_account.to_account_info(), true)
    .permission(&ctx.accounts.permission.to_account_info())
    .magic_context(&ctx.accounts.magic_context.to_account_info())
    .magic_program(&ctx.accounts.magic_program.to_account_info())
    .invoke_signed(&[&[ACCOUNT_SEED, &[ctx.bumps.my_account]]])?;

    // 2. Commit and undelegate the permissioned account.
    MagicIntentBundleBuilder::new(
        ctx.accounts.payer.to_account_info(),
        ctx.accounts.magic_context.to_account_info(),
        ctx.accounts.magic_program.to_account_info(),
    )
    .commit_and_undelegate(&[ctx.accounts.my_account.to_account_info()])
    .build_and_invoke()?;
    Ok(())
}

#[commit]
#[derive(Accounts)]
pub struct UndelegatePrivately<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(mut, seeds = [ACCOUNT_SEED], bump)]
    pub my_account: Account<'info, MyAccount>,
    /// CHECK: Checked by the permission program
    #[account(
        mut,
        seeds = [PERMISSION_SEED, my_account.key().as_ref()],
        bump,
        seeds::program = permission_program.key()
    )]
    pub permission: AccountInfo<'info>,
    /// CHECK: Permission Program
    #[account(address = PERMISSION_PROGRAM_ID)]
    pub permission_program: UncheckedAccount<'info>,
}
```

## Common Gotchas

### Method Name Convention
The delegate method is auto-generated as `delegate_<field_name>`:
```rust
pub my_account: AccountInfo<'info>,  // => ctx.accounts.delegate_my_account()
```

### PDA Seeds Must Match
Seeds in delegate instruction must exactly match account definition:
```rust
#[account(mut, del, seeds = [b"tomo", uid.as_bytes()], bump)]
pub tomo: AccountInfo<'info>,

// Delegate call - seeds must match
ctx.accounts.delegate_tomo(&payer, &[b"tomo", uid.as_bytes()], config)?;
```

### Account Owner Changes on Delegation
```
Not delegated: account.owner == YOUR_PROGRAM_ID
Delegated:     account.owner == DELEGATION_PROGRAM_ID
```

### MagicIntentBundleBuilder takes owned `AccountInfo`
The builder's `new` and `commit` / `commit_and_undelegate` methods take owned
`AccountInfo` values, not references. Use `.to_account_info()` (Anchor) or
`.clone()` (native Rust) on each account passed in. Anchor's `Account<>` and
`Signer<>` types coerce via `.to_account_info()`.

### Native Rust requires `FoldableIntentBuilder` in scope
The chained `.commit(...)` / `.commit_and_undelegate(...)` methods are
trait methods on `FoldableIntentBuilder`. Anchor users get this through
inherent forwarder methods on the builder struct; native Rust call sites
must add `use ephemeral_rollups_sdk::ephem::FoldableIntentBuilder;`.

### PER permission updates: keep the permission delegated
If you only delegate the permissioned account (and not the permission account
itself), every `UpdatePermission` call has to round-trip to base layer. The
recommended PER pattern is to delegate both — that way member changes execute
on the ER and confirm in milliseconds.

## Best Practices

### Do's
- Always use `skipPreflight: true` - Faster transactions, ER handles validation
- Use dual connections - Base layer for delegate, ER for operations/undelegate
- Verify delegation status - Check `accountInfo.owner.equals(DELEGATION_PROGRAM_ID)`
- Wait for state propagation - Add a 3 second sleep after delegate/undelegate in tests before proceeding to the next step
- Use `GetCommitmentSignature` - Verify commits reached base layer
- For PER: delegate the permission account alongside the permissioned account so member updates execute on the ER

### Don'ts
- Don't send delegate tx to ER - Delegation always goes to base layer
- Don't send operations to base layer - Delegated account ops go to ER
- Don't forget the `#[ephemeral]` macro - Required on program module
- Don't use `Account<>` in delegate context - Use `AccountInfo` with `del` constraint
- Don't skip the `#[commit]` macro - Required for undelegate context
- Don't call deprecated `commit_accounts` / `commit_and_undelegate_accounts` - Use `MagicIntentBundleBuilder` instead
- Don't update PER permissions on base layer when the permission account is delegated - Update on the ER for sub-second latency

## Commit Sponsorship & Fee Vault

MagicBlock sponsors **10 commits per delegated account by default** — each
delegation comes with 10 free commits to base layer at no cost. This is
enough for most short-lived delegations (e.g., a single game session).

When the sponsored quota is exhausted, you have two options:

### Option 1: Re-delegate to refresh the quota

Undelegating and re-delegating the account refreshes the sponsored commit
allowance. This is the simplest path for flows that already cycle through
delegation boundaries (session start → play → session end → next session).
No extra accounts, no extra builder methods — just call `delegate` again.

### Option 2: Pay your own commits via `magic_fee_vault` + delegated fee payer

For long-lived delegations or high commit frequency, attach a
`magic_fee_vault` to the intent bundle and use a delegated fee payer (a
PDA payer that signs via seeds). This lifts the sponsored cap — commits
are paid out of the fee vault instead of MagicBlock's sponsorship pool, so
there's no per-account quota.

#### Deriving the fee vault PDA

The fee vault is scoped to the validator running the ER. Read the validator
pubkey out of the delegation record (bytes 8..40) and derive the PDA from
`[b"magic-fee-vault", validator]` under the ephemeral rollups SDK program ID:

```rust
// DelegationRecord layout: [8 discriminator][32 authority = validator][...]
let delegation_record_data = ctx.accounts.delegation_record.try_borrow_data()?;
require!(
    delegation_record_data.len() >= 40,
    crate::errors::MyError::InvalidDelegationRecord
);
let validator = Pubkey::try_from(&delegation_record_data[8..40])
    .map_err(|_| error!(crate::errors::MyError::InvalidDelegationRecord))?;
drop(delegation_record_data);

let (expected_fee_vault, _) = Pubkey::find_program_address(
    &[b"magic-fee-vault", validator.as_ref()],
    &ephemeral_rollups_sdk::id(),
);
require_keys_eq!(
    ctx.accounts.magic_fee_vault.key(),
    expected_fee_vault,
    crate::errors::MyError::InvalidDelegationRecord
);
```

#### Wiring the fee vault into the intent bundle

The builder exposes `.magic_fee_vault(...)` for this. Pair it with
`build_and_invoke_signed` when the payer is a PDA. Note that the **payer**
(who pays for the bundle) and the **committed accounts** (whose state lands
back on base layer) are independent — they may be the same PDA, or different
accounts entirely:

```rust
let payer_seeds: &[&[u8]] = &[MY_PAYER_SEED, owner.as_ref(), &[bump]];

MagicIntentBundleBuilder::new(
    ctx.accounts.payer.to_account_info(),       // payer (PDA in this example)
    ctx.accounts.magic_context.to_account_info(),
    ctx.accounts.magic_program.to_account_info(),
)
.magic_fee_vault(ctx.accounts.magic_fee_vault.to_account_info())
.commit(&[ctx.accounts.my_account.to_account_info()])  // committed account(s) — can differ from payer
.build_and_invoke_signed(&[payer_seeds])?;
```

The fee vault must be passed in the outer instruction's accounts context
as a writable `AccountInfo` (it has lamports debited on each commit).

#### When to pick which option

| Pattern | Recommended path |
|---|---|
| Short delegations (<10 commits per session) | Default sponsorship — do nothing |
| Sessionized flows that re-delegate naturally | Re-delegate to refresh quota |
| Long-lived or high-frequency commits | `magic_fee_vault` + delegated fee payer |
| PDA-driven backend dispatching commits on behalf of users | `magic_fee_vault` + delegated fee payer (PDA must be the payer) |
