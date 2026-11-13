# TypeScript Frontend Setup

## Dependencies

SDK version example, verified 2026-11-13 against npm `0.17.3`. Keep the target repo's existing
compatible package line unless the task is an explicit migration; see
[resources.md](resources.md).

```json
{
  "dependencies": {
    "@coral-xyz/anchor": "0.32.1",
    "@magicblock-labs/ephemeral-rollups-sdk": "0.17.3"
  }
}
```

Changes from `0.15.x` to `0.17.3` in this package are additive: Magic ATA helpers, lookup-table size
calculation, and an optional `template` argument on `getAuthToken` (it must contain `{timestamp}`;
the TEE also requires `{pubkey}`). The package still depends on `@solana/web3.js ^1.98.0`.

### `@solana/kit` codebases

`@magicblock-labs/ephemeral-rollups-kit` is the `@solana/kit` 4.x flavour of this SDK, published with
the same version numbers (latest `0.17.3`). It is not a drop-in replacement: `Connection.create(...)`
is async, and its `sendTransaction` defaults to `skipPreflight: true`, so pass
`skipPreflight: false` to keep preflight. As of 2026-11-13, fixes for escrow PDA derivation
(escrow top-ups fail with `InvalidSeeds`, PR #310), the `schedulePrivateTransfer` layout (fails with
`NotEnoughAccountKeys`, PR #311), and router writable-account lists that omit the fee payer (PR #308)
are open and unreleased. Keep the web3.js package for
Anchor TypeScript clients, which use web3.js anyway; use the kit package only in a codebase that is
already on `@solana/kit`, and avoid those three paths until a release includes the fixes.

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
const baseConnection = new Connection(
  process.env.SOLANA_RPC_ENDPOINT || "https://rpc.magicblock.app/devnet"
);

// Ephemeral rollup connection. Set this from router getDelegationStatus result.fqdn.
const erEndpoint = process.env.EPHEMERAL_PROVIDER_ENDPOINT || "https://devnet-as.magicblock.app/";
const erConnection = new Connection(erEndpoint);
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
type DelegationStatus = {
  isDelegated: boolean;
  fqdn?: string;
  delegationRecord?: {
    authority: string;
    owner: string;
    delegationSlot: number;
    lamports: number;
  };
};

async function getDelegationStatus(account: PublicKey): Promise<DelegationStatus> {
  const routerEndpoint = process.env.ROUTER_ENDPOINT || "https://devnet-router.magicblock.app/";
  const response = await fetch(routerEndpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "getDelegationStatus",
      params: [account.toBase58()],
    }),
  });
  const body = await response.json();
  if (body.error) throw new Error(body.error.message);
  return body.result;
}

function baseOwnerShowsDelegated(accountOwner: PublicKey): boolean {
  return accountOwner.equals(DELEGATION_PROGRAM_ID);
}

const delegationStatus = await getDelegationStatus(pda);
const baseAccountInfo = await baseConnection.getAccountInfo(pda);
const baseOwnerIsDelegationProgram = baseAccountInfo
  ? baseOwnerShowsDelegated(baseAccountInfo.owner)
  : false;
```

Router `isDelegated: true` plus base ownership by the delegation program is
expected. Use `delegationStatus.fqdn` for ER reads and transactions; on that ER,
the account should be owned by the original program.

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
  commitment: "confirmed",
});
```

## Execute on Delegated Account (Ephemeral Rollup)

```typescript
let tx = await program.methods
  .myInstruction()
  .accounts({ myAccount: pda })
  .transaction();

// Use the ephemeral rollup connection.
tx.feePayer = erProvider.wallet.publicKey;
tx.recentBlockhash = (await erConnection.getLatestBlockhash()).blockhash;
tx = await erProvider.wallet.signTransaction(tx);

const txHash = await erProvider.sendAndConfirm(tx, []);
```

These examples preserve preflight. Set `skipPreflight: true` only when the exact ER path has a
documented simulation incompatibility, then inspect the executed transaction logs.

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
const txHash = await erProvider.sendAndConfirm(tx, []);

// Extract the base signature from the ER transaction/logs. This does not
// confirm the base transaction.
const commitTxHash = await GetCommitmentSignature(txHash, erConnection);
await baseConnection.confirmTransaction(commitTxHash, "confirmed");
```

Since `0.17.1`, `GetCommitmentSignature` throws `Transaction failed; commitment was not scheduled`
when the ER transaction errored, instead of returning a signature from an earlier instruction's
log. Base settlement transactions are v1 transactions, and validator 2.0 changes the commit log
format; see the `GetCommitmentSignature` notes in
[delegation.md](delegation.md#implementation-checklist) before fetching or parsing them.

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
