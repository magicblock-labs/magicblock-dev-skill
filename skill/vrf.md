# VRF (Verifiable Random Function)

VRF provides provably fair randomness for games, lotteries, and any application requiring verifiable randomness.

## Dependencies

VRF now ships as a **feature of the main SDK** — enable the `vrf` feature on
`ephemeral-rollups-sdk`. There is no separate `ephemeral-vrf-sdk` crate to add for new Anchor code.

```toml
[dependencies]
ephemeral-rollups-sdk = { version = "0.15.4", features = ["anchor", "vrf"] }
```

> Older examples import a standalone `ephemeral-vrf-sdk` crate and call the non-scoped
> `create_request_randomness_ix` with a manual `vrf_program_identity` signer account. That path still
> works, but new code should use the scoped API below (`ephemeral_rollups_sdk::vrf` +
> `create_request_scoped_randomness_ix` + `#[vrf]` / `#[vrf_callback]`).

## Imports

```rust
use ephemeral_rollups_sdk::{
    anchor::{vrf, vrf_callback},
    vrf::{
        self,
        instructions::{create_request_scoped_randomness_ix, RequestRandomnessParams},
        types::SerializableAccountMeta,
    },
};
```

## Request Randomness

```rust
pub fn roll_dice(ctx: Context<DoRollDiceCtx>, client_seed: u8) -> Result<()> {
    let ix = create_request_scoped_randomness_ix(RequestRandomnessParams {
        payer: ctx.accounts.payer.key(),
        oracle_queue: ctx.accounts.oracle_queue.key(),
        callback_program_id: ID,
        callback_discriminator: instruction::CallbackRollDice::DISCRIMINATOR.to_vec(),
        caller_seed: [client_seed; 32],
        // Accounts the callback needs
        accounts_metas: Some(vec![SerializableAccountMeta {
            pubkey: ctx.accounts.player.key(),
            is_signer: false,
            is_writable: true,
        }]),
        // Extra args forwarded to the callback
        callback_args: Some(vec![client_seed]),
        ..Default::default()
    });

    ctx.accounts
        .invoke_signed_vrf(&ctx.accounts.payer.to_account_info(), &ix)?;
    Ok(())
}

#[vrf] // Injects VRF accounts + invoke_signed_vrf
#[derive(Accounts)]
pub struct DoRollDiceCtx<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(seeds = [PLAYER, payer.key().to_bytes().as_slice()], bump)]
    pub player: Account<'info, Player>,
    /// CHECK: The oracle queue
    #[account(
        mut,
        constraint =
            oracle_queue.key() == vrf::consts::DEFAULT_QUEUE ||     // Devnet / Mainnet
            oracle_queue.key() == vrf::consts::DEFAULT_TEST_QUEUE   // Localnet
    )]
    pub oracle_queue: UncheckedAccount<'info>,
}
```

## Consume Randomness Callback

```rust
pub fn callback_roll_dice(
    ctx: Context<CallbackRollDiceCtx>,
    randomness: [u8; 32],
    client_seed: u8, // matches the callback_args passed in the request
) -> Result<()> {
    let rnd_u8 = vrf::rnd::random_u8_with_range(&randomness, 1, 6);
    let player = &mut ctx.accounts.player;
    player.last_result = rnd_u8;
    player.rollnum = player.rollnum.saturating_add(1);
    Ok(())
}

#[vrf_callback] // Injects the scoped VRF identity signer check
#[derive(Accounts)]
pub struct CallbackRollDiceCtx<'info> {
    #[account(mut)]
    pub player: Account<'info, Player>,
}
```

## Two required macros

Both contexts need a macro; the callback one is the one people forget:

- **`#[vrf]`** on the *request* context — injects the `program_identity`, `vrf_program`,
  `slot_hashes`, and `system_program` accounts plus the `invoke_signed_vrf` helper. Omit it and
  `invoke_signed_vrf` doesn't exist, so the program won't compile.
- **`#[vrf_callback]`** on the *callback* context — injects a `vrf_program_identity: Signer` bound
  to this program's scoped identity PDA, so you don't hand-write it. Omit it and the struct still
  compiles, but the callback has no identity check and accepts spoofed randomness.

## Oracle Queue Constants

The `oracle_queue` is a state account. Like every Solana account it lives on
Solana, but a delegated queue is directly writable only from inside an
ephemeral rollup, while a non-delegated queue is directly writable on the base
layer. Request randomness from the queue that matches where the transaction
runs — the base-layer queue from Solana, or the delegated queue from inside the
ephemeral rollup. Prefer the `ephemeral_rollups_sdk::vrf::consts` constants over
hardcoding addresses.

| Constant | Queue | Address |
|----------|-------|---------|
| `DEFAULT_QUEUE` | Base-layer queue | `Cuj97ggrhhidhbu39TijNVqE74xvKJ69gDervRUXAxGh` |
| `DEFAULT_EPHEMERAL_QUEUE` | Delegated queue (ephemeral rollup) | `5hBR571xnXppuCPveTrctfTU7tJLSN94nq7kv7FRK5Tc` |
| `DEFAULT_TEST_QUEUE` | Base-layer queue, localnet | `GKE6d7iv8kCBrsxr78W3xVdjGLLLJnxsGiuzrsZCGEvb` |
| `DEFAULT_EPHEMERAL_TEST_QUEUE` | Delegated queue, localnet | `Sc9MJUngNbQXSXGP3F67KvKwVnhaYn6kcioxXNVowYT` |

Queues by network:

| Network  | Base-layer queue    | Delegated queue (ephemeral rollup) |
| -------- | ------------------- | ---------------------------------- |
| Mainnet  | `DEFAULT_QUEUE`     | `DEFAULT_EPHEMERAL_QUEUE`           |
| Devnet   | `DEFAULT_QUEUE`     | `DEFAULT_EPHEMERAL_QUEUE`           |
| Localnet | `DEFAULT_TEST_QUEUE`| `DEFAULT_EPHEMERAL_TEST_QUEUE`      |

Mainnet and Devnet share the same default queue addresses — only the cluster
differs. Localnet uses dedicated test queues that the local validator clones
from Devnet.

## Non-Anchor (Pinocchio / native) programs

VRF is also supported outside Anchor via the `ephemeral-rollups-pinocchio` crate
(`ephemeral_rollups_pinocchio::vrf` — `RequestRandomness` / `RequestRandomnessCpi`,
`scoped_vrf_identity`, `random_u8_with_range`, `VRF_PROGRAM_IDENTITY`). The flow is the same
(request → oracle callback), but you validate the program identity manually against
`scoped_vrf_identity(program_id)` instead of relying on the `#[vrf_callback]` macro. See the
Pinocchio `roll-dice` example in the engine examples repo.

## Key Points

- VRF provides cryptographically verifiable randomness.
- The callback pattern ensures randomness is delivered asynchronously.
- Apply **both** `#[vrf]` (request) and `#[vrf_callback]` (callback) — see above.
- Use `DEFAULT_EPHEMERAL_QUEUE` when requesting from inside the ephemeral rollup (the queue is delegated to the ER).
- Use `DEFAULT_QUEUE` when requesting from the base layer (Solana).
- `caller_seed` adds client-side entropy; `callback_args` forwards extra data to the callback.
