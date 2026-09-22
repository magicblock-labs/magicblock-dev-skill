# Post-delegation actions

Use this guide when an instruction submitted on Solana must attach work for the ER validator to
run after the delegated account arrives in the rollup. Read [delegation.md](delegation.md) for the
ordinary account lifecycle and [local-development.md](local-development.md) for environment choice.

Post-delegation actions run **on the ER after delegation**. The base-layer Delegation Program stores
their compact payload in the delegation record; the validator executes it when it clones the account.
The caller does not submit a second ER transaction. This is distinct from
[Magic Actions](magic-actions.md), which an ER instruction schedules to run **on Solana after a
commit**. A successful base-layer delegation confirms that the payload was stored, not that its ER
action completed.

## Choose the action shape

- For public instructions, build ordinary Solana `Instruction` values and call `.cleartext()` to
  produce `PostDelegationActions`.
- For private inputs, encrypt the sensitive fields off-chain for the chosen validator, then pass the
  ciphertext through the base-layer instruction. Construct `PostDelegationActions` with clear
  program/account identities where possible and an encrypted instruction-data suffix. The
  base-layer program handles opaque ciphertext; the PER validator decrypts it before execution.
  Do not put the plaintext in a clear prefix, account key, event, or log.
- If the action needs a signer, include it in `PostDelegationActions.signers` and pass the matching
  signed `AccountInfo` through `action_signer_infos` to `delegate_account_with_actions`. The SDK
  looks up every declared signer there. The ER instruction must still enforce its own authority,
  PDA, and account constraints. The [counter example](https://github.com/magicblock-labs/magicblock-engine-examples/tree/main/delegation-actions/anchor)
  intentionally uses a permissionless `increment`; do not copy that authorization model for a
  privileged action.

Pin the validator in `DelegateConfig` when the payload is encrypted for that validator. Match the
action's PDA seeds and account metas to the instruction it calls. Account indices in the compact
format refer to the `signers` followed by `non_signers` in the simple form; merged/inserted actions
use a different index order. Prefer `.cleartext()` for ordinary actions and check the SDK's
[`PostDelegationActions` layout](https://github.com/magicblock-labs/delegation-program/blob/main/dlp-api/src/args/delegate_with_actions.rs)
when constructing the compact form by hand.

## Anchor delegation call

The `#[delegate]` accounts context supplies the owner program, buffer, delegation record,
metadata, delegation program, and system program. For a public action, a handler with a validated
`validator: Pubkey` can build the payload and call the SDK directly:

```rust
use anchor_lang::solana_program::instruction::{AccountMeta, Instruction};
use anchor_lang::InstructionData;
use ephemeral_rollups_sdk::cpi::{delegate_account_with_actions, DelegateAccounts, DelegateConfig};
use ephemeral_rollups_sdk::dlp_api::compact::ClearText;

let counter_key = ctx.accounts.pda.key();
let action = Instruction {
    program_id: crate::ID,
    accounts: vec![AccountMeta::new(counter_key, false)],
    data: crate::instruction::Increment {}.data(),
};
let actions = vec![action].cleartext();
let payer = ctx.accounts.payer.to_account_info();
let pda = ctx.accounts.pda.to_account_info();

delegate_account_with_actions(
    DelegateAccounts {
        payer: &payer,
        pda: &pda,
        owner_program: &ctx.accounts.owner_program,
        buffer: &ctx.accounts.buffer_pda,
        delegation_record: &ctx.accounts.delegation_record_pda,
        delegation_metadata: &ctx.accounts.delegation_metadata_pda,
        delegation_program: &ctx.accounts.delegation_program,
        system_program: &ctx.accounts.system_program,
    },
    &[COUNTER_SEED],
    DelegateConfig { validator: Some(validator), ..Default::default() },
    actions,
    &[], // The permissionless example needs no additional action signer.
)?;
```

Submit this handler on **Solana**. Keep the ordinary `#[ephemeral]` callback in the program if the
delegated account can later commit and undelegate. The full
[Anchor example](https://github.com/magicblock-labs/magicblock-engine-examples/blob/main/delegation-actions/anchor/programs/delegation-actions/src/lib.rs)
shows its accounts context and local test.

When the same base-layer instruction initializes or changes the PDA before delegating it, serialize
its final state before the delegation CPI changes ownership and clears its data. Avoid an Anchor
`Account<>` exit write after that CPI; use a suitable unchecked account and explicit validation and
serialization where the instruction requires this pattern.

## Verify completion

1. Confirm the delegation transaction on Solana and inspect the delegation record when diagnosing
   payload or rent failures. Attached actions enlarge the record's rent deposit; see
   [fees-and-commit-economics.md](fees-and-commit-economics.md).
2. Resolve the delegated account's validator through router `getDelegationStatus`. On that ER,
   check the application outcome. Do not infer action success from the base signature or the
   account appearing delegated.
3. If the action commits or undelegates, observe that transition separately on Solana. Bound
   polling and reconcile an action that remains pending or fails. For private inputs, test malformed
   ciphertext and application-level rejection against the actual target environment. Check the
   selected SDK, Delegation Program, and validator versions before relying on automatic recovery.

Sources: [ER quickstart](https://docs.magicblock.gg/pages/ephemeral-rollups-ers/how-to-guide/quickstart),
[PER quickstart](https://docs.magicblock.gg/pages/private-ephemeral-rollups-pers/how-to-guide/quickstart),
[SDK CPI](https://github.com/magicblock-labs/ephemeral-rollups-sdk/blob/main/rust/sdk/src/cpi.rs),
and [Anchor delegation-actions example](https://github.com/magicblock-labs/magicblock-engine-examples/tree/main/delegation-actions/anchor).
