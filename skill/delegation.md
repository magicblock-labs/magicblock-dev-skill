# Delegation Patterns (Rust Programs)

## Anchor Framework

### Dependencies

```toml
# Cargo.toml
[dependencies]
anchor-lang = { version = "0.32.1", features = ["init-if-needed"] }
ephemeral-rollups-sdk = { version = "0.6.5", features = ["anchor", "disable-realloc"] }
```

### Imports

```rust
use anchor_lang::prelude::*;
use ephemeral_rollups_sdk::anchor::{commit, delegate, ephemeral};
use ephemeral_rollups_sdk::cpi::DelegateConfig;
use ephemeral_rollups_sdk::ephem::{commit_accounts, commit_and_undelegate_accounts};
```

### Program Macros

```rust
#[ephemeral]  // REQUIRED: Add before #[program]
#[program]
pub mod my_program {
    // ...
}
```

### Delegate Instruction

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

### Undelegate Instruction

```rust
pub fn undelegate(ctx: Context<Undelegate>) -> Result<()> {
    commit_and_undelegate_accounts(
        &ctx.accounts.payer,
        vec![&ctx.accounts.my_account.to_account_info()],
        &ctx.accounts.magic_context,
        &ctx.accounts.magic_program,
    )?;
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

### Commit Without Undelegating

```rust
pub fn commit(ctx: Context<CommitState>) -> Result<()> {
    commit_accounts(
        &ctx.accounts.payer,
        vec![&ctx.accounts.my_account.to_account_info()],
        &ctx.accounts.magic_context,
        &ctx.accounts.magic_program,
    )?;
    Ok(())
}
```

### Anchor Gotchas

#### Method Name Convention
The delegate method is auto-generated as `delegate_<field_name>`:
```rust
pub my_account: AccountInfo<'info>,  // => ctx.accounts.delegate_my_account()
```

#### Don't use `Account<>` in delegate context
Use `AccountInfo` with `del` constraint instead.

#### Don't skip the `#[commit]` macro
Required for undelegate context.

## Pinocchio Framework

### Dependencies

```toml
# Cargo.toml
[dependencies]
pinocchio = { version = "0.10.2", features = ["cpi", "copy"] }
pinocchio-log = { version = "0.5" }
pinocchio-system = { version = "0.5" }
ephemeral-rollups-pinocchio = { version = "0.8.5" }
```

### Imports

```rust
use ephemeral_rollups_pinocchio::instruction::delegate_account;
use ephemeral_rollups_pinocchio::instruction::{
    commit_accounts, commit_and_undelegate_accounts, undelegate,
};
use ephemeral_rollups_pinocchio::types::DelegateConfig;
```

### Program Setup

No macros needed. Pinocchio uses explicit account slicing and manual instruction dispatch instead of Anchor's `#[program]`/`#[ephemeral]` macros.

### Delegate Instruction

```rust
pub fn delegate(
    _program_id: &Address,
    accounts: &[AccountView],
    bump: u8,
) -> ProgramResult {
    let [payer, pda_to_delegate, owner_program, delegation_buffer,
         delegation_record, delegation_metadata, _delegation_program,
         system_program, rest @ ..] = accounts
    else {
        return Err(ProgramError::NotEnoughAccountKeys);
    };
    let validator = rest.first().map(|account| *account.address());

    let seeds: &[&[u8]] = &[b"seed", payer.address().as_ref()];

    delegate_account(
        &[
            payer,
            pda_to_delegate,
            owner_program,
            delegation_buffer,
            delegation_record,
            delegation_metadata,
            system_program,
        ],
        seeds,
        bump,
        DelegateConfig {
            validator,
            ..Default::default()
        },
    )?;

    Ok(())
}
```

### Undelegate Instruction

```rust
pub fn undelegate(
    _program_id: &Address,
    accounts: &[AccountView],
) -> ProgramResult {
    let [payer, my_account, magic_program, magic_context] = accounts else {
        return Err(ProgramError::NotEnoughAccountKeys);
    };

    if !payer.is_signer() {
        return Err(ProgramError::MissingRequiredSignature);
    }

    commit_and_undelegate_accounts(
        payer,
        &[*my_account],
        magic_context,
        magic_program,
    )?;

    Ok(())
}

// REQUIRED: Handle the undelegation callback from the delegation program
pub fn undelegation_callback(
    program_id: &Address,
    accounts: &[AccountView],
    ix_data: &[u8],
) -> ProgramResult {
    let [delegated_acc, buffer_acc, payer, _system_program, ..] = accounts else {
        return Err(ProgramError::NotEnoughAccountKeys);
    };
    undelegate(delegated_acc, program_id, buffer_acc, payer, ix_data)?;
    Ok(())
}
```

### Commit Without Undelegating

```rust
pub fn commit(
    _program_id: &Address,
    accounts: &[AccountView],
) -> ProgramResult {
    let [payer, my_account, magic_program, magic_context] = accounts else {
        return Err(ProgramError::NotEnoughAccountKeys);
    };

    if !payer.is_signer() {
        return Err(ProgramError::MissingRequiredSignature);
    }

    commit_accounts(
        payer,
        &[*my_account],
        magic_context,
        magic_program,
    )?;

    Ok(())
}
```

### Pinocchio Gotchas

#### Undelegation Callback Required
You must implement a `process_undelegation_callback` handler that calls `undelegate()` — the delegation program invokes this on your program when undelegating.

#### Copy Semantics for Account References
`commit_accounts` and `commit_and_undelegate_accounts` take `&[AccountView]` (copied), not references like Anchor's `&AccountInfo`. This requires the `copy` feature on the `pinocchio` crate.

## Common Gotchas

### PDA Seeds Must Match
Seeds in delegate instruction must exactly match account definition.

**Anchor:**
```rust
#[account(mut, del, seeds = [b"tomo", uid.as_bytes()], bump)]
pub tomo: AccountInfo<'info>,

// Delegate call - seeds must match
ctx.accounts.delegate_tomo(&payer, &[b"tomo", uid.as_bytes()], config)?;
```

**Pinocchio:**
```rust
// Seeds used to derive the PDA
let seeds: &[&[u8]] = &[b"seed", payer.address().as_ref()];

// delegate_account call - seeds must match the PDA derivation
delegate_account(&[...], seeds, bump, delegate_config)?;
```

### Account Owner Changes on Delegation
```
Not delegated: account.owner == YOUR_PROGRAM_ID
Delegated:     account.owner == DELEGATION_PROGRAM_ID
```

## Best Practices

### Do's
- Always use `skipPreflight: true` - Faster transactions, ER handles validation
- Use dual connections - Base layer for delegate, ER for operations/undelegate
- Verify delegation status - Check `accountInfo.owner.equals(DELEGATION_PROGRAM_ID)`
- Wait for state propagation - Add a 3 second sleep after delegate/undelegate in tests before proceeding to the next step
- Use `GetCommitmentSignature` - Verify commits reached base layer

### Don'ts
- Don't send delegate tx to ER - Delegation always goes to base layer
- Don't send operations to base layer - Delegated account ops go to ER
- Don't forget the `#[ephemeral]` macro - Required on program module (Anchor)
