# TypeScript Frontend Setup

## Dependencies

```json
{
  "dependencies": {
    "@coral-xyz/anchor": "^0.32.1",
    "@magicblock-labs/ephemeral-rollups-sdk": "^0.6.5"
  }
}
```

## Imports

```typescript
import {
  DELEGATION_PROGRAM_ID,
  GetCommitmentSignature,
} from "@magicblock-labs/ephemeral-rollups-sdk";
```

## Dual Connections

```typescript
// Base layer connection (Solana devnet/mainnet)
const baseConnection = new Connection("https://api.devnet.solana.com");

// Ephemeral rollup connection
const erConnection = new Connection(
  process.env.EPHEMERAL_PROVIDER_ENDPOINT || "https://devnet.magicblock.app/",
  { wsEndpoint: process.env.EPHEMERAL_WS_ENDPOINT || "wss://devnet.magicblock.app/" }
);
```

## Transaction Flow Summary

| Action | Send To | Provider |
|--------|---------|----------|
| Initialize account | Base Layer | `provider` |
| Delegate | Base Layer | `provider` |
| Operations on delegated | Ephemeral Rollup | `providerER` |
| Commit (keep delegated) | Ephemeral Rollup | `providerER` |
| Undelegate | Ephemeral Rollup | `providerER` |

## Check Delegation Status

```typescript
function checkIsDelegated(accountOwner: PublicKey): boolean {
  return accountOwner.equals(DELEGATION_PROGRAM_ID);
}

const accountInfo = await connection.getAccountInfo(pda);
const isDelegated = checkIsDelegated(accountInfo.owner);
```

## Delegate Transaction (Base Layer)

```typescript
async function buildDelegateTx(payer: PublicKey, uid: string): Promise<Transaction> {
  const instruction = await program.methods
    .delegate(uid)
    .accounts({ payer })
    .instruction();

  const tx = new Transaction().add(instruction);
  tx.feePayer = payer;
  return tx;
}

// Send to BASE LAYER
const txHash = await baseProvider.sendAndConfirm(tx, [], {
  skipPreflight: true,
  commitment: "confirmed",
});
```

## Execute on Delegated Account (Ephemeral Rollup)

```typescript
let tx = await program.methods
  .myInstruction()
  .accounts({ myAccount: pda })
  .transaction();

// CRITICAL: Use ephemeral rollup connection
tx.feePayer = erProvider.wallet.publicKey;
tx.recentBlockhash = (await erConnection.getLatestBlockhash()).blockhash;
tx = await erProvider.wallet.signTransaction(tx);

const txHash = await erProvider.sendAndConfirm(tx, [], { skipPreflight: true });
```

## Undelegate Transaction (Ephemeral Rollup)

```typescript
async function buildUndelegateTx(payer: PublicKey, pda: PublicKey): Promise<Transaction> {
  const instruction = await program.methods
    .undelegate()
    .accounts({
      payer,
      myAccount: pda,
      magicProgram: new PublicKey("Magic11111111111111111111111111111111111111"),
      magicContext: new PublicKey("MagicContext1111111111111111111111111111111"),
    })
    .instruction();

  const tx = new Transaction().add(instruction);
  tx.feePayer = payer;
  return tx;
}

// Send to EPHEMERAL ROLLUP
const txHash = await erProvider.sendAndConfirm(tx, [], { skipPreflight: true });

// Wait for commitment on base layer
const commitTxHash = await GetCommitmentSignature(txHash, erConnection);
```

## Key Program IDs

```typescript
const DELEGATION_PROGRAM_ID = new PublicKey("DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh");
const MAGIC_PROGRAM_ID = new PublicKey("Magic11111111111111111111111111111111111111");
const MAGIC_CONTEXT_ID = new PublicKey("MagicContext1111111111111111111111111111111");
const LOCALNET_VALIDATOR = new PublicKey("mAGicPQYBMvcYveUZA5F5UNNwyHvfYh5xkLS2Fr1mev");
```

## Localnet Requires Validator Identity

```typescript
const remainingAccounts = endpoint.includes("localhost")
  ? [{ pubkey: LOCALNET_VALIDATOR, isSigner: false, isWritable: false }]
  : [];
```

## React Native Buffer Issues

Anchor's `program.account.xxx.fetch()` may fail in React Native. Manually decode:

```typescript
const accountInfo = await connection.getAccountInfo(pda);
const isDelegated = accountInfo.owner.equals(DELEGATION_PROGRAM_ID);
const data = manuallyDecodeAccount(accountInfo.data);
```
