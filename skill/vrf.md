# VRF (Verifiable Random Function)

VRF provides provably fair randomness for games, lotteries, and any application requiring verifiable randomness.

## Additional Dependencies

```toml
[dependencies]
ephemeral-vrf-sdk = { version = "0.2.1", features = ["anchor"] }
```

## VRF Imports

```rust
use ephemeral_vrf_sdk::anchor::vrf;
use ephemeral_vrf_sdk::instructions::{create_request_randomness_ix, RequestRandomnessParams};
use ephemeral_vrf_sdk::types::SerializableAccountMeta;
```

## Request Randomness

```rust
pub fn request_randomness(ctx: Context<RequestRandomnessCtx>, client_seed: u8) -> Result<()> {
    let ix = create_request_randomness_ix(RequestRandomnessParams {
        payer: ctx.accounts.payer.key(),
        oracle_queue: ctx.accounts.oracle_queue.key(),
        callback_program_id: ID,
        callback_discriminator: instruction::ConsumeRandomness::DISCRIMINATOR.to_vec(),
        caller_seed: [client_seed; 32],
        accounts_metas: Some(vec![SerializableAccountMeta {
            pubkey: ctx.accounts.my_account.key(),
            is_signer: false,
            is_writable: true,
        }]),
        ..Default::default()
    });

    ctx.accounts.invoke_signed_vrf(&ctx.accounts.payer.to_account_info(), &ix)?;
    Ok(())
}

#[vrf]  // Required macro for VRF interactions
#[derive(Accounts)]
pub struct RequestRandomnessCtx<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(seeds = [MY_SEED, payer.key().to_bytes().as_slice()], bump)]
    pub my_account: Account<'info, MyAccount>,
    /// CHECK: Oracle queue
    #[account(mut, address = ephemeral_vrf_sdk::consts::DEFAULT_EPHEMERAL_QUEUE)]
    pub oracle_queue: AccountInfo<'info>,
}
```

## Consume Randomness Callback

```rust
pub fn consume_randomness(ctx: Context<ConsumeRandomnessCtx>, randomness: [u8; 32]) -> Result<()> {
    let random_value = ephemeral_vrf_sdk::rnd::random_u8_with_range(&randomness, 1, 6);
    ctx.accounts.my_account.last_random = random_value;
    Ok(())
}

#[derive(Accounts)]
pub struct ConsumeRandomnessCtx<'info> {
    /// SECURITY: Validates callback is from VRF program
    #[account(address = ephemeral_vrf_sdk::consts::VRF_PROGRAM_IDENTITY)]
    pub vrf_program_identity: Signer<'info>,
    #[account(mut)]
    pub my_account: Account<'info, MyAccount>,
}
```

## Oracle Queue Constants

| Constant | Use Case |
|----------|----------|
| `DEFAULT_QUEUE` | Non-delegated programs (base layer) |
| `DEFAULT_EPHEMERAL_QUEUE` | Delegated programs (ephemeral rollup) |

## Key Points

- VRF provides cryptographically verifiable randomness
- The callback pattern ensures randomness is delivered asynchronously
- Always validate `vrf_program_identity` signer in the callback to prevent spoofed randomness
- Use `DEFAULT_EPHEMERAL_QUEUE` for delegated accounts on the ephemeral rollup
- Use `DEFAULT_QUEUE` for non-delegated accounts on the base layer
- `caller_seed` can be used to add entropy from the client side
