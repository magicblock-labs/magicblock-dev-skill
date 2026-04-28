# Private Payments API

The MagicBlock Private Payments API builds unsigned SPL token transactions for deposits, transfers, withdrawals, swaps, and mint initialization across Solana (base chain) and MagicBlock ephemeral rollups. It also exposes balance queries and a wallet challenge/login flow that issues bearer tokens for reading private data.

The API is stateless: it only builds transactions, never signs or submits them. The caller deserializes the response, signs client-side, then submits to the chain indicated by `sendTo`.

**Base URL (mainnet):** `https://payments.magicblock.app`

## Authentication

Endpoints that read private data inside the Private Ephemeral Rollup require a bearer token issued by a wallet challenge/login flow:

1. `GET /v1/spl/challenge?pubkey=<wallet>` — returns a `challenge` string
2. The wallet signs the challenge
3. `POST /v1/spl/login` with `{ pubkey, challenge, signature }` — returns a `token`
4. Pass `Authorization: Bearer <token>` on:
   - `GET /v1/spl/private-balance` (**required**)
   - `POST /v1/spl/transfer` (**optional** — only when the request needs to connect to the Private Ephemeral Rollup)

Tokens are scoped to the wallet that signed the challenge.

## Typical Workflow

```
1. GET  /health                      Health check
2. POST /v1/spl/initialize-mint      One-time per mint+validator
3. GET  /v1/spl/challenge            Get challenge to sign (read-private flows)
4. POST /v1/spl/login                Exchange signed challenge for bearer token
5. POST /v1/spl/deposit              Deposit to ER → sign → send to "base"
6. GET  /v1/spl/private-balance      Check ER balance (auth required)
7. POST /v1/spl/transfer             Public or private transfer
8. GET  /v1/swap/quote               Quote a swap between two mints
9. POST /v1/swap/swap                Build swap (public or private)
10. POST /v1/spl/withdraw            Withdraw from ER → sign → send to "base"
11. GET  /v1/spl/balance             Check base balance
```

## Common Response Format

All transaction-building endpoints (`deposit`, `transfer`, `withdraw`, `initialize-mint`) return:

```json
{
  "kind": "deposit" | "withdraw" | "transfer" | "initializeMint",
  "version": "legacy" | "v0",
  "transactionBase64": "<base64-encoded unsigned transaction>",
  "sendTo": "base" | "ephemeral",
  "recentBlockhash": "<blockhash>",
  "lastValidBlockHeight": 284512337,
  "instructionCount": 3,
  "requiredSigners": ["<pubkey>"],
  "validator": "<pubkey>"
}
```

Private `base → base` transfers may return `version: "v0"` when a useful lookup table is configured (set `legacy: true` to force a legacy transaction). All other flows return `legacy`.

The client must:
1. Deserialize `transactionBase64`
2. Sign with each key in `requiredSigners`
3. Send to the chain indicated by `sendTo` (`"base"` = Solana, `"ephemeral"` = ER RPC)

The `/v1/swap/swap` endpoint has its own response shape (see Swap section).

## Error Responses

**400 (Build/Query error):**
```json
{ "error": { "code": "<string>", "message": "<string>", "details": {} } }
```

Common 400 codes: `MISSING_AUTH_TOKEN`, `UNSUPPORTED_TRANSFER_ROUTE`.

**422 (Validation error):**
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "<string>",
    "issues": [{ "code": "<string>", "message": "<string>", "path": ["field"] }]
  }
}
```

## Endpoints

### GET /health

Returns `{ "status": "ok" }`.

---

### GET /v1/spl/challenge

Generate a challenge string for a wallet to sign as part of the login flow.

**Query params:**

| Field | Type | Required | Description |
|---|---|---|---|
| pubkey | string (pubkey) | Yes | Wallet that will read private data |
| cluster | string | No | `"mainnet"`, `"devnet"`, or custom RPC URL |
| mock | boolean | No | Use a mock challenge for testing. Defaults to `false` |

```json
{ "challenge": "1234567890" }
```

---

### POST /v1/spl/login

Exchange a wallet-signed challenge for a bearer token.

| Field | Type | Required | Description |
|---|---|---|---|
| pubkey | string (pubkey) | Yes | The wallet that signed the challenge |
| challenge | string | Yes | Challenge string returned by `/v1/spl/challenge` |
| signature | string | Yes | Wallet signature over the challenge |
| cluster | string | No | Cluster selection |
| mock | boolean | No | Use mock login for testing |

```json
{ "token": "1234567890" }
```

Returns `403` if signature verification fails.

---

### POST /v1/spl/initialize-mint

Build an unsigned base-chain transaction that initializes and delegates a validator-scoped transfer queue for a mint. One-time setup per mint+validator pair.

| Field | Type | Required | Description |
|---|---|---|---|
| payer | string (pubkey) | Yes | Transaction fee payer |
| mint | string (pubkey) | Yes | SPL mint address |
| cluster | string | No | Cluster selection |
| validator | string (pubkey) | No | Validator override |

Response extends the standard format with:
- `transferQueue`: pubkey of the created transfer queue
- `rentPda`: pubkey of the rent PDA

---

### GET /v1/spl/is-mint-initialized

Check whether a mint has a validator-scoped transfer queue on the ephemeral RPC.

**Query params:** `mint` (required), `cluster` (optional), `validator` (optional)

```json
{
  "mint": "<pubkey>",
  "validator": "<pubkey>",
  "transferQueue": "<pubkey>",
  "initialized": true
}
```

---

### POST /v1/spl/deposit

Deposit SPL tokens from Solana into an ephemeral rollup.

| Field | Type | Required | Description |
|---|---|---|---|
| owner | string (pubkey) | Yes | Wallet address |
| amount | integer (>=1) | Yes | Base-unit token amount |
| cluster | string | No | `"mainnet"`, `"devnet"`, or custom RPC URL. Defaults to mainnet |
| mint | string (pubkey) | No | Defaults to USDC (mainnet: `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`, devnet: `4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU`) |
| validator | string (pubkey) | No | Defaults to ephemeral RPC identity via `getIdentity` |
| initIfMissing | boolean | No | Auto-initialize transfer queue if missing |
| initVaultIfMissing | boolean | No | Auto-initialize vault if missing |
| initAtasIfMissing | boolean | No | Auto-initialize ATAs if missing |
| idempotent | boolean | No | Use idempotent variants for any preparatory init instructions |

```json
{
  "owner": "3rXKwQ1kpjBd5tdcco32qsvqUh1BnZjcYnS5kYrP7AYE",
  "amount": 1,
  "initIfMissing": true,
  "initVaultIfMissing": true,
  "initAtasIfMissing": true,
  "idempotent": true
}
```

---

### POST /v1/spl/transfer

Transfer SPL tokens publicly or privately through an ephemeral rollup.

**Optional header:** `Authorization: Bearer <token>` — required only when the request needs to connect to the Private Ephemeral Rollup.

| Field | Type | Required | Description |
|---|---|---|---|
| from | string (pubkey) | Yes | Sender address |
| to | string (pubkey) | Yes | Recipient address |
| mint | string (pubkey) | Yes | SPL mint address |
| amount | integer (>=1) | Yes | Base-unit amount |
| visibility | `"public"` \| `"private"` | Yes | Transfer visibility |
| fromBalance | `"base"` \| `"ephemeral"` | Yes | Source balance location |
| toBalance | `"base"` \| `"ephemeral"` | Yes | Destination balance location |
| cluster | string | No | Cluster selection |
| validator | string (pubkey) | No | Validator override |
| initIfMissing | boolean | No | Auto-initialize transfer queue |
| initAtasIfMissing | boolean | No | Auto-initialize ATAs |
| initVaultIfMissing | boolean | No | Auto-initialize vault. Defaults to `false` |
| memo | string | No | Appends a Memo Program instruction with this UTF-8 message |
| minDelayMs | string (numeric) | No | Private only. Min delay in ms. Defaults to `"0"` |
| maxDelayMs | string (numeric) | No | Private only. Max delay. Defaults to `"0"` or `minDelayMs` |
| clientRefId | string (numeric) | No | Private only. Encrypted client reference ID for confirming a payment |
| split | integer (1-15) | No | Private only. Split into N sub-transfers. Defaults to 1. Cannot exceed `amount` |
| gasless | boolean | No | When `true`, the API uses the configured sponsor as fee payer and prepends a relay-fee token transfer to the sponsor ATA |
| legacy | boolean | No | Force a legacy transaction (skip lookup-table compilation). Defaults to `false` |

```json
{
  "from": "3rXKwQ1kpjBd5tdcco32qsvqUh1BnZjcYnS5kYrP7AYE",
  "to": "Bt9oNR5cCtnfuMmXgWELd6q5i974PdEMQDUE55nBC57L",
  "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  "amount": 1000000,
  "visibility": "private",
  "fromBalance": "base",
  "toBalance": "base",
  "initIfMissing": true,
  "initAtasIfMissing": true,
  "initVaultIfMissing": false,
  "memo": "Order #1042",
  "minDelayMs": "0",
  "maxDelayMs": "0",
  "clientRefId": "42",
  "split": 1,
  "gasless": true
}
```

---

### POST /v1/spl/withdraw

Withdraw SPL tokens from an ephemeral rollup back to Solana.

| Field | Type | Required | Description |
|---|---|---|---|
| owner | string (pubkey) | Yes | Wallet address |
| mint | string (pubkey) | Yes | SPL mint on Solana |
| amount | integer (>=1) | Yes | Base-unit amount |
| cluster | string | No | Cluster selection |
| validator | string (pubkey) | No | Validator override |
| initIfMissing | boolean | No | Auto-initialize transfer queue |
| initAtasIfMissing | boolean | No | Auto-initialize ATAs |
| escrowIndex | integer (>=0) | No | Escrow index |
| idempotent | boolean | No | Use idempotent variants for any preparatory init instructions |

```json
{
  "owner": "3rXKwQ1kpjBd5tdcco32qsvqUh1BnZjcYnS5kYrP7AYE",
  "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  "amount": 1000000,
  "idempotent": true
}
```

---

### GET /v1/spl/balance

Get the base-chain SPL token balance for an address. Reads the owner's ATA on the base RPC.

**Query params:**

| Field | Type | Required | Description |
|---|---|---|---|
| address | string (pubkey) | Yes | Owner wallet pubkey |
| mint | string (pubkey) | Yes | SPL mint pubkey |
| cluster | string | No | Cluster selection |

```json
{
  "address": "<pubkey>",
  "mint": "<pubkey>",
  "ata": "<pubkey>",
  "location": "base",
  "balance": "1000000"
}
```

`balance` is a base-unit string.

---

### GET /v1/spl/private-balance

Get the ephemeral-rollup SPL token balance for an address. Reads the owner's ATA on the ephemeral RPC.

**Required header:** `Authorization: Bearer <token>` (from `/v1/spl/login`)

**Query params:** same as `/v1/spl/balance` (`address`, `mint`, optional `cluster`).

Response has `"location": "ephemeral"`. Returns `400 MISSING_AUTH_TOKEN` if the header is absent.

---

### GET /v1/swap/quote

Get a swap quote between two SPL mints. Proxies the configured Triton Metis Swap API. The quote response can be passed as-is into `POST /v1/swap/swap`.

**Query params:**

| Field | Type | Required | Description |
|---|---|---|---|
| inputMint | string (pubkey) | Yes | Input token mint |
| outputMint | string (pubkey) | Yes | Output token mint |
| amount | string (numeric) | Yes | Raw amount before decimals |
| slippageBps | integer | No | Slippage in basis points |
| swapMode | `"ExactIn"` \| `"ExactOut"` | No | Defaults to `ExactIn` |
| dexes | string | No | Comma-separated DEX labels to include |
| excludeDexes | string | No | Comma-separated DEX labels to exclude |
| restrictIntermediateTokens | boolean | No | Restrict intermediates to a stable set |
| onlyDirectRoutes | boolean | No | Single-hop only |
| asLegacyTransaction | boolean | No | Request legacy-compatible route |
| platformFeeBps | integer | No | Platform fee in bps |
| maxAccounts | integer | No | Approximate max account budget |
| instructionVersion | `"V1"` \| `"V2"` | No | Instruction format |
| dynamicSlippage | boolean | No | Compatibility flag |
| forJitoBundle | boolean | No | Exclude routes incompatible with Jito bundles |
| supportDynamicIntermediateTokens | boolean | No | Allow dynamic intermediate selection |

Response is a Jupiter-style quote with `inputMint`, `inAmount`, `outputMint`, `outAmount`, `otherAmountThreshold`, `swapMode`, `slippageBps`, `priceImpactPct`, `routePlan`, etc. Pass it verbatim as `quoteResponse` to `/v1/swap/swap`.

---

### POST /v1/swap/swap

Build an unsigned swap transaction from a quote.

**Visibility modes:**

- **`visibility: "public"`** (default) — pure pass-through to Jupiter/Metis. Returns whatever the upstream produces.
- **`visibility: "private"`** — the server forces Jupiter's output into a program-owned stash ATA (deterministically derived from `(userPublicKey, quoteResponse.outputMint)`), prepends an idempotent ATA-create, and appends a `schedule_private_transfer` instruction that registers a one-shot Hydra crank. When the crank fires, it self-CPIs into the on-chain private-transfer flow to deliver the swapped tokens to `destination` with the requested delay/split policy.

| Field | Type | Required | Description |
|---|---|---|---|
| userPublicKey | string (pubkey) | Yes | Wallet that will sign the swap |
| quoteResponse | object | Yes | Quote response from `/v1/swap/quote` |
| visibility | `"public"` \| `"private"` | No | Defaults to `"public"` |
| destination | string (pubkey) | If private | Final private-transfer recipient |
| minDelayMs | string (numeric) | If private | Min delay in ms |
| maxDelayMs | string (numeric) | If private | Max delay in ms. Must be ≤ 600000 (10 min) |
| split | integer (1-14) | If private | Number of queue splits |
| clientRefId | string (numeric) | No | u64 correlation id attached to each split |
| validator | string (pubkey) | No | Defaults to `MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57` |
| payer | string (pubkey) | No | Optional fee payer override |
| wrapAndUnwrapSol | boolean | No | Wrap/unwrap native SOL when needed |
| useSharedAccounts | boolean | No | Allow shared accounts for routing |
| feeAccount | string (pubkey) | No | Token account to collect platform fees |
| destinationTokenAccount | string (pubkey) | No | Output token account. Server-controlled when `visibility="private"` — must match the derived stash ATA or returns `400` |
| asLegacyTransaction | boolean | No | Not allowed when `visibility="private"` |
| dynamicComputeUnitLimit | boolean | No | Auto compute unit limit |
| computeUnitPriceMicroLamports | integer | No | Exact compute unit price |
| prioritizationFeeLamports | integer \| object | No | Priority fee config |

**Public response:**
```json
{
  "swapTransaction": "<base64 unsigned transaction>",
  "lastValidBlockHeight": 318120000
}
```

**Private response** (adds diagnostic `privateTransfer` block):
```json
{
  "swapTransaction": "<base64 unsigned v0 transaction with appended ATA-create + schedule_private_transfer>",
  "lastValidBlockHeight": 318120000,
  "privateTransfer": {
    "stashAta": "<pubkey>",
    "hydraCrankPda": "<pubkey>",
    "shuttleId": 2147483647
  }
}
```

The returned transaction is unsigned — the client signs with `userPublicKey` and submits.

```json
{
  "userPublicKey": "3rXKwQ1kpjBd5tdcco32qsvqUh1BnZjcYnS5kYrP7AYE",
  "quoteResponse": { /* from /v1/swap/quote */ },
  "visibility": "private",
  "destination": "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU",
  "minDelayMs": "0",
  "maxDelayMs": "60000",
  "split": 1
}
```

## MCP Endpoint

### POST /mcp

Stateless Streamable HTTP MCP endpoint (JSON-RPC 2.0). Each request creates a fresh server with no session state.

**Headers:** `Content-Type: application/json`, `Accept: application/json`

**Registered MCP tools** (subset of the REST surface):

| Tool name | Description |
|---|---|
| `spl.deposit` | Build an unsigned base-chain deposit transaction |
| `spl.withdraw` | Build an unsigned ER → base withdraw transaction |
| `spl.transfer` | Build an unsigned public or private SPL transfer |
| `spl.getBalance` | Read the owner ATA balance on the base RPC |
| `spl.getPrivateBalance` | Read the owner ATA balance on the ephemeral RPC |

`initialize-mint`, `is-mint-initialized`, `challenge`, `login`, and the swap endpoints are **not** exposed as MCP tools — call them via REST.

**Initialize:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-11-25",
    "capabilities": {},
    "clientInfo": { "name": "my-client", "version": "1.0.0" }
  }
}
```

**Tool call:**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "spl.deposit",
    "arguments": {
      "owner": "3rXKwQ1kpjBd5tdcco32qsvqUh1BnZjcYnS5kYrP7AYE",
      "amount": 1,
      "initIfMissing": true,
      "initAtasIfMissing": true,
      "initVaultIfMissing": false,
      "idempotent": true
    }
  }
}
```

MCP responses include `result.structuredContent` with the same fields as the REST response.

`GET /mcp` returns a human-readable info document and `GET /.well-known/mcp.json` returns the MCP discovery document.

## Key Details

- Amounts are always in base units (e.g., 1 USDC = 1,000,000 with 6 decimals)
- `mint` defaults to USDC when omitted on deposit
- `validator` defaults to the ephemeral RPC identity resolved via `getIdentity` when omitted, or to `MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57` for swaps
- `cluster` accepts `"mainnet"`, `"devnet"`, or a custom `http(s)` RPC URL
- Private transfers and private swaps support `split` and `minDelayMs`/`maxDelayMs` for timing obfuscation. Transfers allow `split` 1–15; swaps allow 1–14 with `maxDelayMs ≤ 600000` (10 min)
- Set `initIfMissing`, `initAtasIfMissing`, and `initVaultIfMissing` all to `true` for the simplest deposit integration
- `idempotent`: when `true`, init instructions use idempotent variants
- `gasless` transfers use the configured sponsor as fee payer and prepend a relay-fee token transfer to the sponsor ATA
- Auth: `/v1/spl/private-balance` always requires `Authorization: Bearer <token>`. `/v1/spl/transfer` only requires it when the route needs the Private ER. All other endpoints are unauthenticated
