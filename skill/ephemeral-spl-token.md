# Ephemeral SPL Token Lifecycle: Deposit, Transfer, App-Program CPI, Undelegate, Withdraw

Use this reference when a project needs SPL tokens inside an Ephemeral Rollup:
depositing tokens into the ER, transferring them at ER speed (directly or through
an app program), and withdrawing them back to base-layer token accounts.
For the hosted Payments HTTP API (deposits, transfers, withdrawals, swaps as a
service, with auth) use [private-payments.md](private-payments.md) instead.

Sources of truth:

1. **Upstream program repo**: `https://github.com/magicblock-labs/ephemeral-spl-token`
   — program behavior, instruction data, account metas, PDA seeds, state layouts.
2. **TypeScript SDK**: `@magicblock-labs/ephemeral-rollups-sdk` — high-level
   `delegateSpl` / `transferSpl` / `undelegateIx` / `withdrawSpl` helpers plus
   per-instruction builders and PDA derivations.
3. **Working example**: `magicblock-engine-examples/spl-tokens/anchor` — end-to-end
   Anchor program + tests exercising the full lifecycle.

Version snapshot (known-good from the active example): TS + Rust
`ephemeral-rollups-sdk` **0.14.3**, Anchor **1.0.2**. Treat as compatibility
markers, not latest recommendations — see [resources.md](resources.md).

Program ID (all clusters): `SPLxh1LVZzEkX99H6rqYizhytLWPZVV296zyYDPagv2`

## Two Mental Models — Pick One First

**Model A — SDK lifecycle (default).** Clients drive the whole lifecycle with
SDK helpers: `delegateSpl` (deposit + delegate), `transferSpl`, `undelegateIx`,
`withdrawSpl`. On the ER, the delegated balance materializes as a **normal SPL
token account at the owner's canonical ATA address** — clients read it with
`getAccount(erConnection, ata)`, and app programs move it with a plain SPL
Token CPI. You never derive an eATA or vault PDA, and your program never calls
the Ephemeral SPL Token program. Use this for games, payments, and any app
that just needs token balances usable on the ER.

**Model B — direct program surface.** A smart contract (or bespoke client)
talks to the Ephemeral SPL Token program itself: derive the **eATA PDA**
(seeds `[owner, mint]`) and per-mint **global vault PDA** (seeds `[mint]`),
build instruction data from the `ephemeral-spl-api` crate, and wire exact
account metas. Use this only when Model A's helpers can't express the flow —
on-chain deposit/withdraw orchestration, transfer queues, shuttles, or custom
vault logic.

Both models share the same base-layer state: deposited tokens are locked in
the global vault, the user's balance is recorded in the eATA, and the eATA is
delegated to the delegation program. Undelegate + withdraw commits ER state
back to base and releases tokens from the vault to the owner's real ATA. The
difference is purely which surface you touch: canonical ATAs + SDK helpers
(A) versus raw PDAs + program instructions (B).

---

# Model A: SDK Lifecycle

### Lifecycle and Endpoint Routing

| Step | Helper | Endpoint | Signers |
|---|---|---|---|
| Create mint / ATAs / fund | standard `@solana/spl-token` | Base | payer |
| Deposit + delegate | `delegateSpl(...)` | Base | owner (+ payer) |
| Transfer inside ER | `transferSpl(...)` or app program | ER | from-owner |
| Read ER balance | `getAccount(erConnection, ata)` | ER | — |
| Undelegate | `undelegateIx(owner, mint)` | ER | owner |
| Wait for commit | `GetCommitmentSignature(sig, erConnection)` | ER → Base | — |
| Withdraw | `withdrawSpl(...)` | Base | owner |

## Client Integration (TypeScript)

### Dependencies

```json
{
  "dependencies": {
    "@coral-xyz/anchor": "0.32.1",
    "@magicblock-labs/ephemeral-rollups-sdk": "0.14.3",
    "@solana/spl-token": "^0.4.14"
  }
}
```

### Imports and Connections

```typescript
import {
  delegateSpl,
  transferSpl,
  undelegateIx,
  withdrawSpl,
  deriveRentPda,
  GetCommitmentSignature,
} from "@magicblock-labs/ephemeral-rollups-sdk";
import { getAccount, getAssociatedTokenAddressSync } from "@solana/spl-token";
```

Use the standard dual-connection setup (see
[typescript-setup.md](typescript-setup.md)): one provider on the base layer,
one on the ER endpoint for the validator you delegate to.

### Prerequisites

- The owner's ATA for the mint must exist on base layer before delegating
  (or pass `initAtasIfMissing: true`).
- The global **rent PDA** (`deriveRentPda()`) sponsors shuttle rent for the
  deposit flow. On a fresh/local cluster, fund it before delegating (the
  example transfers 0.2 SOL to it during setup):

```typescript
const [rentPda] = deriveRentPda();
// SystemProgram.transfer(payer → rentPda, 0.2 * LAMPORTS_PER_SOL) on base layer
```

### Choosing the Validator

**Recommended: resolve one validator up front and pass the same `validator` to
every `delegateSpl` in the flow.** Balances can only interact in one ER
transaction if they live on the same ER, and the program's transfer queue is
scoped per `[mint, validator]` — so keep the validator consistent across all
delegations for a mint. Encrypted private transfers additionally hard-require
it (the SDK throws `"validator is required for encrypted private transfers"`).

Technically `validator` is optional — omitting it delegates unpinned
(`DelegateConfig { validator: None }` on-chain, the same default as ordinary
account delegation) and the account's ER is discovered afterwards via router
`getDelegationStatus`. If you go that way, verify all interacting accounts
report the same `fqdn` before sending joint ER transactions.

`validator` takes the ER validator's **identity pubkey**, and you need it
*before* delegating — router `getDelegationStatus` only returns an `fqdn` for
accounts that are already delegated. Resolve the identity of the ER endpoint
you plan to use with JSON-RPC `getIdentity` (this is how the upstream API
resolves it when the request omits `validator`; `web3.js`'s `Connection` does
not wrap this method):

```typescript
const res = await fetch(ER_ENDPOINT, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "getIdentity", params: [] }),
});
const validator = new PublicKey((await res.json()).result.identity);
```

The example's devnet tests default to validator
`mAGicPQYBMvcYveUZA5F5UNNwyHvfYh5xkLS2Fr1mev` (endpoint
`https://devnet-as.magicblock.app/`) — treat that as a snapshot and prefer
resolving via `getIdentity`.

### Deposit + Delegate (base layer)

```typescript
const delegateOpts = {
  validator,                    // ER validator pubkey
  idempotent: false as const,   // legacy vault flow — see mode note below
  payer: admin.publicKey,
};

// First delegation for a mint creates the shared vault; later ones reuse it.
const ixs = await delegateSpl(owner.publicKey, mint, 50n, {
  ...delegateOpts,
  initVaultIfMissing: true,     // true ONLY for the first delegation per mint
});
await provider.sendAndConfirm(new Transaction().add(...ixs), [owner, admin], {
  commitment: "confirmed",
  skipPreflight: true,
});
```

`DelegateSplOptions`: `payer?`, `validator?`, `initIfMissing?`,
`initVaultIfMissing?`, `initAtasIfMissing?`, `shuttleId?`, `escrowIndex?`,
`idempotent?`, `private?`.

### Transfer Inside the ER

```typescript
const transferIxs = await transferSpl(fromOwner.publicKey, toOwner.publicKey, mint, 2n, {
  visibility: "public",
  fromBalance: "ephemeral",
  toBalance: "ephemeral",
});
await erProvider.sendAndConfirm(new Transaction().add(...transferIxs), [fromOwner], {
  commitment: "confirmed",
  skipPreflight: true,
});

// Balances on the ER live at the canonical ATA addresses:
const erBalance = (await getAccount(erConnection, ata)).amount;
```

For ephemeral→ephemeral public transfers this builds a plain SPL transfer
between the canonical ATAs — which is why an app program can do the same via
CPI (next section). `transferSpl` also routes base→ephemeral, base→base, and
`visibility: "private"` variants (queued private transfers via
`privateTransfer: { minDelayMs, maxDelayMs, split }`).

### Undelegate, Wait for Commit, Withdraw

```typescript
// 1. Undelegate on the ER — ONE owner per transaction (combined undelegates
//    in a single tx are flaky).
const commits: string[] = [];
for (const owner of owners) {
  const sgn = await erProvider.sendAndConfirm(
    new Transaction().add(undelegateIx(owner.publicKey, mint)),
    [owner],
    { commitment: "confirmed", skipPreflight: true },
  );
  commits.push(await GetCommitmentSignature(sgn, erConnection));
}

// 2. Wait for ALL commits to land on base before any withdraw. Withdraw needs
//    each eATA to be owned by the program again on base; racing a pending
//    commit fails with InvalidAccountOwner.
await Promise.all(commits.map((c) => baseConnection.confirmTransaction(c, "confirmed")));

// 3. Withdraw on base layer back to the owner's real ATA.
const withdrawIxs = await withdrawSpl(owner.publicKey, mint, amount, {
  idempotent: false,
});
await provider.sendAndConfirm(new Transaction().add(...withdrawIxs), [owner], {
  commitment: "confirmed",
});
```

### Mode Consistency: `idempotent` Flag

`delegateSpl` has two account layouts: the default **idempotent shuttle path**
and the **legacy vault path** (`idempotent: false`). The undelegate/withdraw
calls must match the mode used at delegation — the example's
`undelegateIx`/`withdrawSpl` flow above pairs with `idempotent: false`. Pick
one mode per flow and keep delegate, undelegate, and withdraw consistent.

## App Program Over Delegated Token Accounts (Anchor)

Use this when your program enforces custom rules while moving tokens on the ER.
This is still Model A: the program never touches the Ephemeral SPL Token
program — it receives the canonical ATAs (materialized as normal token
accounts on the ER) and CPIs into the SPL Token Program. Verbatim from the
working example (Anchor 1.0.2):

```rust
use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer as SplTransfer};
use ephemeral_rollups_sdk::anchor::ephemeral;

#[ephemeral]
#[program]
pub mod spl_tokens {
    use super::*;

    pub fn transfer(ctx: Context<TransferTokens>, amount: u64) -> Result<()> {
        require!(amount > 0, ErrorCode::InvalidAmount);

        let cpi_accounts = SplTransfer {
            from: ctx.accounts.from.to_account_info(),
            to: ctx.accounts.to.to_account_info(),
            authority: ctx.accounts.payer.to_account_info(),
        };
        // Anchor 1.0.x: CpiContext::new takes the program key
        let cpi_ctx = CpiContext::new(ctx.accounts.token_program.key(), cpi_accounts);
        token::transfer(cpi_ctx, amount)?;
        Ok(())
    }
}

#[derive(Accounts)]
pub struct TransferTokens<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        mut,
        constraint = from.owner == payer.key() @ ErrorCode::InvalidTokenOwner,
        constraint = from.mint == to.mint @ ErrorCode::MintMismatch
    )]
    pub from: Account<'info, TokenAccount>,
    #[account(mut)]
    pub to: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[error_code]
pub enum ErrorCode {
    #[msg("amount must be > 0")]
    InvalidAmount,
    #[msg("from token account is not owned by payer")]
    InvalidTokenOwner,
    #[msg("from and to token accounts must have the same mint")]
    MintMismatch,
}
```

Cargo dependencies (snapshot):

```toml
anchor-lang = { version = "1.0.2", features = ["init-if-needed"] }
anchor-spl = { version = "1.0.2" }
ephemeral-rollups-sdk = { version = "0.14.3", features = ["anchor"] }
```

Calling it from the client — the transaction targets the **ER endpoint**, so
build it with the ER blockhash:

```typescript
const tx = await program.methods
  .transfer(new BN(2))
  .accounts({ payer: sender.publicKey, from: ataSender, to: ataReceiver })
  .transaction();
tx.recentBlockhash = (await erConnection.getLatestBlockhash()).blockhash;
tx.sign(sender);
const sgn = await erConnection.sendRawTransaction(tx.serialize(), { skipPreflight: true });
await erConnection.confirmTransaction(sgn, "confirmed");
```

Both `from` and `to` must already be delegated (via `delegateSpl`) before this
instruction is sent. Delegation, undelegation, and withdrawal are orchestrated
client-side around the app program.

---

# Model B: Direct Program Surface

Only reach for this when Model A's helpers can't express the flow. Everything
here works in terms of the program's own PDAs, not canonical ATAs.

### State Model

| Account | Seeds (program `SPLxh1...agv2`) | Holds |
|---|---|---|
| Ephemeral ATA (eATA) | `[owner, mint]` | owner, mint, `amount` (the ER-side balance), bump |
| Global vault | `[mint]` | mint, vault token account address, bump |
| Vault token account | ATA of `(vault, mint)` | the actual locked SPL tokens for the whole mint |
| Rent PDA | `[b"rent"]` | lamports sponsoring shuttle/queue rent |
| Transfer queue | `[b"queue", mint, validator]` | queued delayed transfers |

### Rust CPI via `ephemeral-spl-api`

Depend on the upstream API crate — `ephemeral-spl-api`, in the `e-token-api/`
directory of the program repo (unpublished; use a git dependency). The
on-chain program is Pinocchio-based, but the API crate is framework-agnostic.
Use its exports instead of copying bytes:

- Program ID: `ephemeral_spl_api::ID`; delegation program:
  `ephemeral_spl_api::program::DELEGATION_PROGRAM_ID`.
- Discriminators: `ephemeral_spl_api::instruction::ESplInstruction` —
  `to_vec()` for no-arg instructions, `with_data(&args.encode()...)` for
  argument payloads.
- Args: `ephemeral_spl_api::instructions::{DepositArgs, WithdrawArgs,
  DelegateArgs, InitializeTransferQueueArgs, DepositAndQueueTransferArgs,
  AmountAndSaltArgs, ...}` (encoded via `wheels::layout::Encodable`).
- State + PDAs: `state::ephemeral_ata::EphemeralAta` (`find_pda(owner, mint)`,
  `seeds`, `signer_seeds`), `state::global_vault::GlobalVault`
  (`find_pda(mint)`), `state::transfer_queue::TransferQueue`.
- Errors: `EphemeralSplError`.

```rust
use ephemeral_spl_api::instruction::ESplInstruction;

// No-arg instruction
let data = ESplInstruction::InitializeEphemeralAta.to_vec();

// Amount payload (little-endian u64 after the discriminator)
let mut data = ESplInstruction::DepositSplTokens.to_vec();
data.extend_from_slice(&amount.to_le_bytes());
```

### Core Instruction Account Metas

Verify against `e-token/tests/` when wiring; `(w)` = writable, `(s)` = signer.

| Instruction | Accounts (in order) |
|---|---|
| `InitializeEphemeralAta` | eATA PDA (w), payer (s), owner, mint, system program |
| `InitializeGlobalVault` | vault PDA (w), payer (s), mint, vault eATA (w), vault token account (w), token program, ATA program, system program |
| `DepositSplTokens` | owner eATA (w), vault, mint, source token account (w), vault token account (w), owner authority (s), token program |
| `WithdrawSplTokens` | owner (s), owner eATA (w), vault, mint, vault token account (w), destination token account (w), token program |
| `DelegateEphemeralAta` | payer (s), eATA (w), owner program, delegation buffer (w), delegation record (w), delegation metadata (w), delegation program, system program |
| `CloseEphemeralAta` | owner (s), eATA (w), rent destination (w) |

The program exposes a much larger surface (shuttle flows, transfer queues,
sponsored lamports transfers, stealth pools, scheduled private transfers) —
consult the upstream repo's README and `e-token/tests/` for those. Never call
the internal automation discriminators (196+, e.g. `UndelegationCallback`)
from an app program; they are callbacks fired by the delegation/magic programs.

### Low-Level TypeScript Builders

The SDK also exposes Model B client-side, mirroring the raw instructions
(module `instructions/ephemeral-spl-token-program`):

- PDAs: `deriveEphemeralAta(owner, mint)`, `deriveVault(mint)`,
  `deriveVaultAta(mint, vault)`, `deriveRentPda()`,
  `deriveLamportsPda(payer, destination, salt)`,
  `deriveShuttleEphemeralAta(owner, mint, shuttleId)`.
- Instructions: `initEphemeralAtaIx`, `initVaultIx`, `initVaultAtaIx`,
  `initRentPdaIx`, `depositSplTokensIx`, `delegateEphemeralAtaIx`,
  `withdrawSplIx`, `undelegateIx`, `mergeShuttleIntoAtaIx`,
  `lamportsDelegatedTransferIx` (see [lamports-topup.md](lamports-topup.md)),
  and eATA permission builders (`createEataPermissionIx`,
  `delegateEataPermissionIx`, `resetEataPermissionIx`,
  `undelegateEataPermissionIx`).
- State decoders: `decodeEphemeralAta`, `decodeGlobalVault`.

---

## Common Gotchas

- **Pin the same `validator` across a flow** — one ER transaction can only
  write accounts delegated to its own validator, and the transfer queue is
  scoped per `[mint, validator]`. Resolve it once via `getIdentity` on the ER
  endpoint and pass it to every `delegateSpl`. If you delegated unpinned
  (default config), confirm via router `getDelegationStatus` that all
  interacting accounts share the same `fqdn` first.
- **`initVaultIfMissing: true` exactly once per mint** — the first delegation
  creates the shared vault; passing `true` again is the idempotent path's job,
  in the legacy flow subsequent delegations use `false`.
- **Fund the rent PDA before delegating** on fresh/local clusters — shuttle
  rent is sponsored from `deriveRentPda()`; an unfunded rent PDA fails the
  deposit flow.
- **One undelegate per transaction, per owner** — combining undelegations in
  one transaction is flaky.
- **Wait for every undelegation commit before withdrawing** — withdraw runs on
  base and requires the eATA to be program-owned again; racing a pending
  commit fails with `InvalidAccountOwner`. Use `GetCommitmentSignature` on the
  ER signature, then confirm that signature on the base connection.
- **Blockhash must come from the connection you send to** — ER transactions
  need `erConnection.getLatestBlockhash()`; mixing endpoints produces
  blockhash-not-found or stale-state errors.
- **`skipPreflight: true` for ER transactions** and for delegation
  transactions on base.
- **Keep the `idempotent` mode consistent** across delegate → undelegate →
  withdraw; the two modes use different account layouts.
- **Verify balances against the right endpoint** — ER balances via the ER
  connection, base balances via the base connection; the other side is stale
  by design until commit.
- **Token vs Token-2022**: keep the token program consistent across mint,
  ATAs, vault, and CPIs; don't mix within one flow.
- **Private transfers settle later, not immediately** — queued private
  transfers execute within the `[minDelayMs, maxDelayMs]` window; don't assert
  destination balances right after sending.
- **Don't mix models** — an app program in Model A should never derive eATA or
  vault PDAs; a Model B contract must not assume canonical-ATA balances exist
  on base layer.
