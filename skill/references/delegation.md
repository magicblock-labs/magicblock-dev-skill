# Delegation Patterns (Rust Programs)

## Rust Program Setup

### Dependencies

SDK version example, verified 2026-11-19 against crates.io `0.18.0`, the line that supports
validator 1.x and 2.0. crates.io latest `0.20.0` is the 2.0-only line, so `cargo add` without a
version is wrong for mainnet and the TEE ERs, which run 1.x; see [resources.md](resources.md#sdk-lines). Before changing a
real project, inspect its existing manifests; keep the project's versions unless the task explicitly
requests an upgrade.

```toml
# Cargo.toml
[dependencies]
anchor-lang = { version = "1.0.2", features = ["init-if-needed"] }
ephemeral-rollups-sdk = { version = "0.18.0", features = ["anchor"] }

# Anchor line is selected by the SDK feature flag:
#   "anchor"        → Anchor 1.x
#   "anchor-compat" → Anchor >=0.28,<1.0 (0.18.x and earlier)
# Add the access-control feature for Private Ephemeral Rollups (PER)
# ephemeral-rollups-sdk = { version = "0.18.0", features = ["anchor", "access-control"] }
```

SDK `0.18.0` feature flags (`0.17.3` has the same set without `magic-accounts`):

| Feature | Enables |
|---|---|
| `anchor` | Anchor 1.x (alias for `anchor-modern`) |
| `anchor-compat` | Anchor >=0.28,<1.0 (includes `backward-compat`) |
| `backward-compat` | Legacy Solana types without Anchor |
| `modular-sdk` | Builds against the modular Solana crates (`solana-account-info`, `solana-cpi`, …) |
| `access-control` | `access_control` module (PER permission CPIs), `anchor::PermissionProgram` |
| `spl` | `spl` module (eSPL builders), `anchor::EsplProgram`; also enables `encryption` and `instruction` |
| `instruction` | Re-exports `dlp_api::instruction_builder` as `ephemeral_rollups_sdk::instruction_builder` |
| `vrf` | `vrf` module, `anchor::{vrf, vrf_callback}` |
| `crank` | `crank` module (Hydra crank CPIs plus the deprecated legacy scheduling CPIs) |
| `anchor-debug` | Anchor debug logging |
| `magic-accounts` | `magic_accounts` module (0.18.0; pulls `magicblock-magic-program-api` `2.0.0`) |

Without a compatibility flag the SDK targets Solana 3.0. Do not combine `anchor` with
`anchor-compat` or `backward-compat`; that fails at compile time. SDK `0.20.0` removed
`anchor-compat` and `backward-compat` (#317) and requires anchor-lang ≥ 1.2.2; `0.18.x` keeps both.
Check the target version's `Cargo.toml` before relying on either flag.

### Imports

```rust
use anchor_lang::prelude::*;
use ephemeral_rollups_sdk::anchor::{commit, delegate, ephemeral};
use ephemeral_rollups_sdk::cpi::DelegateConfig;
use ephemeral_rollups_sdk::ephem::MagicIntentBundleBuilder;
```

> The free functions `commit_accounts` and `commit_and_undelegate_accounts`
> are deprecated. Schedule commit / undelegate intents through
> `MagicIntentBundleBuilder`. The chained commit methods come from
> `FoldableIntentBuilder`. Inside a module marked `#[ephemeral]`, the macro
> injects that trait import. Native Rust call sites must import it explicitly:
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

To attach an instruction that the validator runs after the account reaches the ER, use
[post-delegation actions](delegation-actions.md) instead of the plain delegation helper below.

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

Since SDK `0.17.1` (#288), `#[delegate]` rejects any `del` field that is not `UncheckedAccount` or
`AccountInfo` at compile time. A typed `Account<>` would be written back after the handler, which
fails with `ExternalAccountDataModified` once SIMD-0460 direct mapping is active.

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
the ER, then update or close it there as needed. New code needs no separate base-layer
permission account to create, delegate, commit, or undelegate.

That is application guidance, not a protocol rule. The permission program still implements the
legacy v1 base-layer permission (create, delegate, commit, undelegate), and the TEE still honors it:
for v1, `members: None` is public and `Some([])` is private (verified on the deployed program and the
query-filtering decision code, 2026-11-19). v1 and v2 share the PDA `[PERMISSION_SEED, account]`
(permission-program source `5dc3748e`), so an account that still has a delegated v1 permission cannot
get an `EphemeralPermission` until the v1 record is undelegated and closed.

The delegated data PDA signs each permission CPI with its program seeds. It also
pays the ephemeral permission rent, so pre-fund the data PDA during base-layer
initialization with enough lamports for `EphemeralPermission::size_of(member_count)`.
Choose a maximum member count up front and enforce that cap in every create and
update instruction so permission growth cannot exceed the funded capacity.

Default visibility on the TEE (PER `v0.2.0`, verified in source and against devnet-tee on
2026-11-13): an account with no permission is public, except SPL / Token-2022 token accounts,
which only their owner can read. Mints stay public, and a token-program account that decodes as
neither fails closed. Reading a user's token account on a TEE therefore needs that owner's auth
token. Permission records are visible only to their members. The permission program rejects
creating a permission for a System-Program-owned account with `InvalidOwner` (#23).

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
        // Anchor 1.0.x: CpiContext::new takes the program key
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
transactions. Skip creation only when that PDA is already an initialized
permission-program account.

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
    if ctx.accounts.permission.owner == &PERMISSION_PROGRAM_ID
        && !ctx.accounts.permission.data_is_empty()
    {
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

With the `access-control` feature, SDK `0.17.x` and `0.18.x` also expose `anchor::PermissionProgram`, so
`pub permission_program: Program<'info, PermissionProgram>` can replace the
`UncheckedAccount` + `address = PERMISSION_PROGRAM_ID` pair.

## Exit Paths and Recovery

Normal exit is `commit_and_undelegate` from the ER. Two other paths exist for when that
instruction cannot run:

- **Undelegation request from the base layer.** The Delegation Program's `RequestUndelegation`
  (discriminator `26`) creates an `UndelegationRequest` PDA for one delegated account. The
  delegation rent payer and the delegated PDA must both sign, so the owner program issues it by CPI
  with the PDA's seeds. The live validator (`1.1.1`) watches these PDAs and schedules
  commit-and-undelegate. A backfill poll runs every 5 minutes by default
  (`undelegation-request-poll-interval`).
- **Rollback after timeout.** If the validator has not undelegated within
  `DEFAULT_UNDELEGATION_REQUEST_TIMEOUT_SLOTS = 9000` slots (about 60 minutes),
  `UndelegateWithRollbackAfterTimeout` (`27`) returns the account to the owner program. It is
  authorized by the owner program through CPI, as with the request. It returns only the last
  base-chain state, so any ER state that was never committed is lost. The owner-program wrapper
  must save the delegated account's data before the CPI and restore it afterwards.

Both instructions are deployed on devnet and mainnet. Both clusters have run Delegation Program
`0c551fa` since 2026-11-03 (executable hash verified). SDK `0.17.3` and `0.18.0` have no Anchor or CPI wrapper
for them. With the `instruction` (or `spl`) feature they re-export the dlp-api 3.1.0 builders
`ephemeral_rollups_sdk::instruction_builder::{request_undelegation,
undelegate_with_rollback_after_timeout}`; issue the resulting instruction by CPI with the
delegated PDA's seeds.

## Common errors

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
Not delegated, base: account.owner == YOUR_PROGRAM_ID
Delegated, base:     account.owner == DELEGATION_PROGRAM_ID
Delegated, ER:       account.owner == YOUR_PROGRAM_ID
```

The layer-specific owner difference is a routing and lifecycle signal. It does not replace application
authorization: instructions executing on the ER must enforce the same signer, authority, PDA, and
account constraints they require on Solana.

### MagicIntentBundleBuilder takes owned `AccountInfo`

The builder's `new` and `commit` / `commit_and_undelegate` methods take owned
`AccountInfo` values, not references. Use `.to_account_info()` (Anchor) or
`.clone()` (native Rust) on each account passed in. Anchor's `Account<>` and
`Signer<>` types coerce via `.to_account_info()`.

### `FoldableIntentBuilder` must be in scope

The chained `.commit(...)` / `.commit_and_undelegate(...)` methods are
trait methods on `FoldableIntentBuilder`. The `#[ephemeral]` macro injects the
trait import inside the annotated Anchor program module. Native Rust call sites
must add `use ephemeral_rollups_sdk::ephem::FoldableIntentBuilder;` explicitly.

### PER permissions are ephemeral

For new code, do not create or delegate a base-layer permission account. Delegate
the data PDA, then create, update, and close its `EphemeralPermission` on the ER.
Pre-fund the data PDA for permission rent before delegation. A legacy v1 permission
still works but occupies the same PDA; see
[PER: ER-local permissions](#private-ephemeral-rollups-per-er-local-permissions).

### Accounts that cannot be committed

The live 1.x validators (`8886db2`, same as the `v1.1.1` tag here) refuse to schedule a commit or
commit-and-undelegate for (2.0 has the same size check):

- An account whose data is larger than 10,240 bytes (`MAX_PERMITTED_DATA_INCREASE`). The log reads
  `ScheduleCommit ERR: account <pubkey> is too large to be committed` and the instruction fails
  with `InvalidAccountData`. Keep delegated accounts at or under 10 KiB, or split state across
  several PDAs.
- A Magic ATA. Funds leave it through the eSPL shuttle withdrawal flow instead; see
  [ephemeral-spl-token.md](ephemeral-spl-token.md).

See [fees-and-commit-economics.md](fees-and-commit-economics.md#failure-map) for the other
commit-time errors.

## Implementation checklist

### Required

- Keep preflight enabled for supported base-layer transactions. On the ER, preflight
  is not a simulation: with or without it, the transaction executes and is recorded
  (a failure lands as a failed transaction). `skipPreflight: true` only makes
  `sendTransaction` return before execution instead of returning the execution error.
  If you skip it, check the ER signature status and logs (verified on `8886db2`,
  2026-11-19)
- Use dual connections - Base layer for delegate, ER for operations/undelegate
- Verify delegation for routing/debugging - Query router status and compare the base and ER owners;
  do not use delegation itself as application authorization
- Wait for state propagation: poll router status plus base and ER ownership until they match the
  expected delegated or undelegated state. Use a bounded timeout and fail the test explicitly if the
  transition is not observed
- Use `GetCommitmentSignature` to extract the base signature from ER logs, then
  confirm that returned signature separately on the base connection. Use the TS
  SDK `0.18.x` helper: it reads both the 1.x log and the 2.0 outbox; 0.17.x
  throws on 2.0 (the devnet regional ERs) and 0.20.x throws on 1.x (devnet-tee and mainnet). Base-layer settlement
  transactions are already v1 transactions on devnet and mainnet (checked 2026-11-13), so fetch
  them with `maxSupportedTransactionVersion: 1`; a request with `0` fails with "Transaction version
  (1) is not supported". `@solana/web3.js` 1.98.4's `VersionedMessage.deserialize` rejects v1
  messages. Whether `Connection.getTransaction` decodes them through its JSON path is untested, so
  prefer a raw JSON-RPC call or confirming the signature status
- For PER: delegate only the data PDA, then manage its `EphemeralPermission` on the ER

> **Validator 2.0 (released; devnet-us, devnet-eu, and devnet-as run `2.0.4` on 2026-11-24).** The scheduling transaction
> logs `Outbox for scheduled intent: <address>` instead of
> `ScheduledCommitSent signature: <sig>`. Find completion with `getSignaturesForAddress(outbox)`
> then `getTransaction`; SDK `0.18.x` `GetCommitmentSignature` does this. Committed accounts must
> also be writable, including when committing from inside another program (otherwise
> `ReadonlyDataModified`), and commit IDs are reserved at scheduling time, so the commit limit and
> fee threshold count queued commits. Check `getVersion` before relying on either behaviour: 2.0
> reports `core`, 1.x reports `magicblock-core`.

### Avoid

- Sending delegation transactions to the ER; delegation runs on base layer
- Sending delegated-account operations to base layer; they run on the ER
- Omitting `#[ephemeral]` from the program module
- Using `Account<>` in the delegation context; use `AccountInfo` or `UncheckedAccount` with the
  `del` constraint (a compile error since SDK `0.17.1`)
- Delegating accounts larger than 10,240 bytes; the validator cannot commit them
- Omitting `#[commit]` from the undelegation context
- Calling deprecated `commit_accounts` or `commit_and_undelegate_accounts`; use `MagicIntentBundleBuilder`
- Creating or delegating a base-layer PER permission account in new code; use the ER-local
  `EphemeralPermission`

## Commit Limits & Fee Vault

Read [fees-and-commit-economics.md](fees-and-commit-economics.md) before estimating costs or describing
commits as free. The Delegation Program collects session and after-first-commit charges from delegation
PDA deposits at undelegation, while the validator separately enforces live commit limits and fees.

Without a delegated payer, the validator rejects a plain commit with `0xA0000000` once the account's
commit nonce reaches 10, so commit 11 fails when commits land one at a time. On 1.x the check reads
the last landed nonce, so queued commits are not counted until they land; 2.0 counts them at
scheduling. This is a hard cap, not a soft quota. Commit-and-undelegate kinds are exempt so the
account can exit; on the live `8886db2`, `commit_finalize` intents are capped too. You have two
options:

### Option 1: Re-delegate to reset the count

Undelegating and re-delegating the account resets its commit nonce, so the next delegation can commit
ten more times. This fits flows that already cycle through delegation boundaries (session start →
play → session end → next session), and needs no fee-vault accounts or builder methods. It does not
make commits free: each undelegation charges the 3,000,000-lamport session fee plus 1,000,000 per
commit after the first, capped by that delegation's deposit (about 2.8M–3.3M for short seeds without actions), and each re-delegation
pays a new deposit. See
[fees-and-commit-economics.md](fees-and-commit-economics.md#2-delegation-deposits-and-undelegation-charges).

### Option 2: Pay your own commits via `magic_fee_vault` + delegated fee payer

For long-lived delegations or high commit frequency, attach a `magic_fee_vault` to the intent bundle
and use a delegated fee payer, usually a PDA that signs via seeds. This selects the validator's
fee-vault path. Commits 1 through 25 have no additional live debit; commit 26 and later debit
`1_000_000` lamports per committed account on the live validators (`8886db2`; the `v1.1.1` tag
charged `100_000`). Delegation cleanup fees still apply separately.

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

If the program pins the validator when it delegates
(`DelegateConfig { validator: Some(<validator>), .. }`) and stores that key, derive the vault from the
stored key instead. Both give the same PDA; the delegation record is the source of truth when the
validator is not pinned.

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

The fee vault must be passed in the outer instruction's accounts context as a writable `AccountInfo`.
The payer must be delegated, non-confined, writable, and able to sign. The vault must be the canonical
validator-scoped PDA, writable, and delegated. A billable bundle fails atomically with
`InsufficientFunds` when the payer cannot cover its per-account commit fees plus any Base Action fees.

#### When to pick which option

| Pattern | Recommended path |
|---|---|
| Short delegations (at most 10 plain commits per session) | No fee-vault wiring; budget for cleanup fees |
| Sessionized flows that re-delegate naturally | Re-delegate to reset the nonce and settle/refund the session |
| Long-lived or high-frequency commits | `magic_fee_vault` + delegated fee payer |
| PDA-driven backend dispatching commits on behalf of users | `magic_fee_vault` + delegated fee payer (PDA must be the payer) |
