# Topping Up a Delegated Account with Lamports

When a delegated account needs more lamports on the ER side — for example, to keep paying its own commits via a delegated fee payer pattern (see [delegation.md](delegation.md)) — you don't transfer lamports directly to the ER. Instead, you submit a **base-layer transaction** that uses the Ephemeral SPL Token program to shuttle lamports through a sponsored, single-use lamports PDA. The ER picks up the lamports as part of the delegation flow.

## When to use

- A delegated PDA (e.g. a fee payer for sponsored commits) is running low on lamports on the ER side.
- You need to top up the lamport balance of a delegated account that already exists on base layer and has a delegation record.
- You want a one-shot, signed-by-the-payer top-up that doesn't require the destination to interact.

## SDK helper

The SDK exposes `lamportsDelegatedTransferIx` (instruction discriminator `20`) which:

1. Creates a one-shot lamports PDA derived from `[b"lamports", payer, destination, salt]` under the Ephemeral SPL Token program.
2. Funds it with `amount` lamports from the payer.
3. Delegates the lamports PDA so the ER can consume it and credit the destination's delegated balance.

```typescript
import {
  lamportsDelegatedTransferIx,
  deriveLamportsPda,
} from "@magicblock-labs/ephemeral-rollups-sdk";

export async function lamportsDelegatedTransferIx(
  payer: Address,
  destination: Address,    // delegated destination on base layer
  amount: bigint,          // lamports
  salt: Uint8Array,        // exactly 32 bytes, generated per call
): Promise<Instruction>
```

## Full example

The pattern, end-to-end:

```typescript
import { Connection, Keypair, PublicKey, Transaction, sendAndConfirmTransaction } from "@solana/web3.js";
import {
  lamportsDelegatedTransferIx,
  deriveLamportsPda,
} from "@magicblock-labs/ephemeral-rollups-sdk";

async function topUpDelegatedAccount(
  connection: Connection,        // base-layer connection
  payer: Keypair,
  destination: PublicKey,        // delegated account to top up
  amountLamports: bigint,
) {
  // Generate a fresh 32-byte salt per top-up. Re-using a salt collides
  // with an existing lamports PDA and the instruction will fail.
  const salt = crypto.getRandomValues(new Uint8Array(32));

  const [lamportsPda] = deriveLamportsPda(payer.publicKey, destination, salt);

  const ix = await lamportsDelegatedTransferIx(
    payer.publicKey,
    destination,
    amountLamports,
    salt,
  );

  const tx = new Transaction().add(ix);
  tx.feePayer = payer.publicKey;

  // CRITICAL: Submit to BASE LAYER, not the ER.
  const sig = await sendAndConfirmTransaction(connection, tx, [payer], {
    commitment: "confirmed",
    skipPreflight: true,
  });

  return { sig, lamportsPda };
}
```

## Working reference

A full working integration is in `magicblock-engine-examples/spl-tokens/app/app/src/App.tsx` — search for `handleLamportsTransfer`. It demonstrates:

- Generating the salt with `crypto.getRandomValues(new Uint8Array(32))`
- Deriving the lamports PDA with `deriveLamportsPda` for logging/debugging
- Submitting the single-instruction transaction to the base-layer connection
- Verifying the payer has enough lamports before submitting

## Common gotchas

### Submit to the base-layer RPC, not the ER
The instruction creates accounts and triggers a delegation — these are base-layer operations. Sending the transaction to the ER will fail. Use the same `Connection` you'd use for `delegate`.

### Salt must be exactly 32 bytes
`lamportsDelegatedTransferIx` throws if `salt.length !== 32`. Always generate with `crypto.getRandomValues(new Uint8Array(32))`.

### Use a fresh salt per top-up
The lamports PDA is derived from `[b"lamports", payer, destination, salt]`. A repeated `(payer, destination, salt)` triple resolves to the same PDA, which already exists from the previous call and causes the instruction to fail. Generating a fresh 32-byte salt each call sidesteps this entirely.

### Destination must already be delegated
The instruction reads the destination's delegation record and uses it to route the lamports to the correct ER. If the destination isn't delegated yet, the instruction fails. Delegate first, then top up.

### Payer pays gas + the topped-up amount
The payer pays the base-layer transaction fee AND the `amount` being shuttled. Verify `connection.getBalance(payer)` is comfortably greater than `amount` before submitting.

### `amount` is in lamports, not SOL
1 SOL = 1,000,000,000 lamports. Keep this in mind when sourcing the value from a UI.

## Best practices

### Do's
- Generate a fresh 32-byte salt per top-up via `crypto.getRandomValues`
- Submit the transaction to the base-layer connection
- Verify the destination is delegated before topping up
- Pre-flight a balance check on the payer

### Don'ts
- Don't reuse salts — every call needs fresh entropy
- Don't submit the transaction to the ER connection
- Don't use this for non-delegated destinations — regular `SystemProgram.transfer` is the right tool there
- Don't use this for SPL token top-ups — see the SPL transfer flows in the SDK instead
