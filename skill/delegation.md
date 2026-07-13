# Delegation Patterns (Rust Programs)

## Rust Program Setup

### Dependencies

SDK version example, verified 2026-07-13. Before changing a real project,
inspect its existing manifests and [resources.md](resources.md); keep the
project's versions unless the task explicitly requests an upgrade.

```toml
# Cargo.toml
[dependencies]
anchor-lang = { version = "1.0.2", features = ["init-if-needed"] }
ephemeral-rollups-sdk = { version = "0.15.5", features = ["anchor"] }

# Anchor line is selected by the SDK feature flag:
#   "anchor"        → Anchor 1.x
#   "anchor-compat" → Anchor >=0.28,<1.0
# Add the access-control feature for Private Ephemeral Rollups (PER)
# ephemeral-rollups-sdk = { version = "0.15.5", features = ["anchor", "access-control"] }
```

### Imports

```rust
use anchor_lang::prelude::*;
use ephemeral_rollups_sdk::anchor::{commit, delegate, ephemeral};
use ephemeral_rollups_sdk::cpi::DelegateConfig;
use ephemeral_rollups_sdk::ephem::MagicIntentBundleBuilder;
```

> The free functions `commit_accounts` and `commit_and_undelegate_accounts`
> are deprecated. Schedule commit / undelegate intents through
> `MagicIntentBundleBuilder`. The builder
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

## Private Ephemeral Rollups (PER): ER-local permissions

For Private Ephemeral Rollups, delegate only the data PDA to the TEE validator on
the base layer. After delegation, create its `EphemeralPermission` directly on
the ER, then update or close it there as needed. There is no separate base-layer
permission account to create, delegate, commit, or undelegate.

The delegated data PDA signs each permission CPI with its program seeds. It also
pays the ephemeral permission rent, so pre-fund the data PDA during base-layer
initialization with enough lamports for `EphemeralPermission::size_of(member_count)`.
Choose a maximum member count up front and enforce that cap in every create and
update instruction so permission growth cannot exceed the funded capacity.

### Imports

```rust
use anchor_lang::system_program::{transfer, Transfer};
use ephemeral_rollups_sdk::access_control::instructions::{
    CloseEphemeralPermissionCpi, CreateEphemeralPermissionCpi,
    UpdateEphemeralPermissionCpi,
};
use ephemeral_rollups_sdk::access_control::structs::{
    EphemeralMembersArgs, EphemeralPermission, Member, PERMISSION_SEED,
};
use ephemeral_rollups_sdk::consts::{
    EPHEMERAL_VAULT_ID, MAGIC_PROGRAM_ID, PERMISSION_PROGRAM_ID,
};
```

### 1. Pre-fund and delegate only the data PDA on base

```rust
// During base-layer initialization, fund the data PDA for the largest member
// list the permission will need on the ER.
const ACCOUNT_SEED: &[u8] = b"my-account";
const MAX_PERMISSION_MEMBERS: usize = 8;

pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
    transfer(
        CpiContext::new(
            ctx.accounts.system_program.key(),
            Transfer {
                from: ctx.accounts.authority.to_account_info(),
                to: ctx.accounts.my_account.to_account_info(),
            },
        ),
        ephemeral_rollups_sdk::ephemeral_accounts::rent(
            EphemeralPermission::size_of(MAX_PERMISSION_MEMBERS) as u32,
        ),
    )?;
    ctx.accounts.my_account.authority = ctx.accounts.authority.key();
    Ok(())
}

pub fn delegate(ctx: Context<DelegatePrivately>) -> Result<()> {
    let validator = ctx.accounts.validator.as_ref();
    if ctx.accounts.my_account.owner != &ephemeral_rollups_sdk::id() {
        ctx.accounts.delegate_my_account(
            &ctx.accounts.authority,
            &[ACCOUNT_SEED, ctx.accounts.authority.key().as_ref()],
            DelegateConfig {
                validator: validator.map(|v| v.key()),
                ..Default::default()
            },
        )?;
    }
    Ok(())
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + 32,
        seeds = [ACCOUNT_SEED, authority.key().as_ref()],
        bump
    )]
    pub my_account: Account<'info, MyAccount>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[delegate]
#[derive(Accounts)]
pub struct DelegatePrivately<'info> {
    pub authority: Signer<'info>,
    /// CHECK: The data PDA to delegate.
    #[account(
        mut,
        del,
        seeds = [ACCOUNT_SEED, authority.key().as_ref()],
        bump
    )]
    pub my_account: UncheckedAccount<'info>,
    /// CHECK: Optional target TEE validator, forwarded in DelegateConfig.
    pub validator: Option<UncheckedAccount<'info>>,
}

#[account]
pub struct MyAccount {
    pub authority: Pubkey,
}
```

### 2. Create the ephemeral permission on the ER

Derive `permission` from `[PERMISSION_SEED, my_account.key()]` under
`PERMISSION_PROGRAM_ID`. Make creation idempotent because clients may retry ER
transactions.

```rust
pub fn init_permission(
    ctx: Context<PermissionContext>,
    members: Option<Vec<Member>>,
) -> Result<()> {
    let (is_private, members) = match members {
        Some(members) => (true, members),
        None => (false, vec![]),
    };
    require!(
        members.len() <= MAX_PERMISSION_MEMBERS,
        PermissionError::TooManyMembers
    );
    if ctx.accounts.permission.lamports() > 0 {
        return Ok(());
    }
    let signer_seeds: &[&[u8]] = &[
        ACCOUNT_SEED,
        ctx.accounts.my_account.authority.as_ref(),
        &[ctx.bumps.my_account],
    ];
    CreateEphemeralPermissionCpi {
        payer: ctx.accounts.my_account.to_account_info(),
        permissioned_account: ctx.accounts.my_account.to_account_info(),
        permission: ctx.accounts.permission.to_account_info(),
        vault: ctx.accounts.ephemeral_vault.to_account_info(),
        magic_program: ctx.accounts.magic_program.to_account_info(),
        permission_program: ctx.accounts.permission_program.to_account_info(),
        args: EphemeralMembersArgs { is_private, members },
    }
    .invoke_signed(&[signer_seeds])?;
    Ok(())
}
```

### 3. Update the ephemeral permission on the ER

Rebuild the complete member list on every update, including any authority that
must retain access. Omitting a member revokes that member.

```rust
pub fn set_permission(
    ctx: Context<PermissionContext>,
    is_private: bool,
    members: Vec<Member>,
) -> Result<()> {
    require!(
        members.len() <= MAX_PERMISSION_MEMBERS,
        PermissionError::TooManyMembers
    );
    let signer_seeds: &[&[u8]] = &[
        ACCOUNT_SEED,
        ctx.accounts.my_account.authority.as_ref(),
        &[ctx.bumps.my_account],
    ];
    UpdateEphemeralPermissionCpi {
        payer: ctx.accounts.my_account.to_account_info(),
        permissioned_account: ctx.accounts.my_account.to_account_info(),
        permission: ctx.accounts.permission.to_account_info(),
        vault: ctx.accounts.ephemeral_vault.to_account_info(),
        magic_program: ctx.accounts.magic_program.to_account_info(),
        permission_program: ctx.accounts.permission_program.to_account_info(),
        authority: ctx.accounts.my_account.to_account_info(),
        authority_is_signer: false,
        args: EphemeralMembersArgs { is_private, members },
    }
    .invoke_signed(&[signer_seeds])?;
    Ok(())
}
```

### 4. Close the permission on the ER, then undelegate the data PDA

Close the ER-local permission before the data PDA leaves the ER if it is no
longer needed. Closing refunds its rent to the data PDA. Undelegate only the
data PDA with `MagicIntentBundleBuilder`; there is no permission undelegation.

```rust
pub fn close_permission(ctx: Context<PermissionContext>) -> Result<()> {
    let signer_seeds: &[&[u8]] = &[
        ACCOUNT_SEED,
        ctx.accounts.my_account.authority.as_ref(),
        &[ctx.bumps.my_account],
    ];
    CloseEphemeralPermissionCpi {
        payer: ctx.accounts.my_account.to_account_info(),
        permissioned_account: ctx.accounts.my_account.to_account_info(),
        permission: ctx.accounts.permission.to_account_info(),
        vault: ctx.accounts.ephemeral_vault.to_account_info(),
        magic_program: ctx.accounts.magic_program.to_account_info(),
        permission_program: ctx.accounts.permission_program.to_account_info(),
        authority: ctx.accounts.my_account.to_account_info(),
        authority_is_signer: false,
    }
    .invoke_signed(&[signer_seeds])?;
    Ok(())
}
```

Use a shared ER-side context for the three permission operations:

```rust
#[derive(Accounts)]
pub struct PermissionContext<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [ACCOUNT_SEED, my_account.authority.as_ref()],
        has_one = authority,
        bump
    )]
    pub my_account: Account<'info, MyAccount>,
    /// CHECK: Derived and checked under the Permission Program.
    #[account(
        mut,
        seeds = [PERMISSION_SEED, my_account.key().as_ref()],
        bump,
        seeds::program = permission_program.key()
    )]
    pub permission: UncheckedAccount<'info>,
    #[account(address = PERMISSION_PROGRAM_ID)]
    pub permission_program: UncheckedAccount<'info>,
    #[account(mut, address = EPHEMERAL_VAULT_ID)]
    pub ephemeral_vault: UncheckedAccount<'info>,
    #[account(address = MAGIC_PROGRAM_ID)]
    pub magic_program: UncheckedAccount<'info>,
}

#[error_code]
pub enum PermissionError {
    #[msg("Permission member count exceeds MAX_PERMISSION_MEMBERS")]
    TooManyMembers,
}
```

Replace `has_one = authority` with the application's actual authorization rule
when authority is stored elsewhere or controlled by a multisig. Never expose a
PDA-signed permission CPI through an instruction that lacks application-level
authorization.

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

### PER permissions are ephemeral
Do not create or delegate a base-layer permission account. Delegate the data PDA,
then create, update, and close its `EphemeralPermission` on the ER. Pre-fund the
data PDA for permission rent before delegation.

## Best Practices

### Do's
- Always use `skipPreflight: true` - Faster transactions, ER handles validation
- Use dual connections - Base layer for delegate, ER for operations/undelegate
- Verify delegation status - Check `accountInfo.owner.equals(DELEGATION_PROGRAM_ID)`
- Wait for state propagation - Add a 3 second sleep after delegate/undelegate in tests before proceeding to the next step
- Use `GetCommitmentSignature` - Verify commits reached base layer
- For PER: delegate only the data PDA, then manage its `EphemeralPermission` on the ER

### Don'ts
- Don't send delegate tx to ER - Delegation always goes to base layer
- Don't send operations to base layer - Delegated account ops go to ER
- Don't forget the `#[ephemeral]` macro - Required on program module
- Don't use `Account<>` in delegate context - Use `AccountInfo` with `del` constraint
- Don't skip the `#[commit]` macro - Required for undelegate context
- Don't call deprecated `commit_accounts` / `commit_and_undelegate_accounts` - Use `MagicIntentBundleBuilder` instead
- Don't create or delegate a base-layer PER permission account - Use the ER-local ephemeral permission lifecycle

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
