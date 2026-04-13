# Private Payments API

The MagicBlock Private Payments API builds unsigned SPL token transactions for deposits, transfers, withdrawals, and mint initialization across Solana (base chain) and MagicBlock ephemeral rollups.

The API is stateless: it only builds transactions, never signs or submits them. The caller deserializes the response, signs client-side, then submits to the chain indicated by `sendTo`.

**Base URL (mainnet):** `https://payments.magicblock.app`

## Typical Workflow

```
1. GET  /health                      Health check
2. POST /v1/spl/initialize-mint      One-time per mint+validator
3. POST /v1/spl/deposit              Deposit to ER → sign → send to "base"
4. GET  /v1/spl/private-balance      Check ER balance
5. POST /v1/spl/transfer             Private transfer → sign → send to indicated chain
6. POST /v1/spl/withdraw             Withdraw from ER → sign → send to "base"
7. GET  /v1/spl/balance              Check base balance
```

## Common Response Format

All transaction-building endpoints return:

```json
{
  "kind": "deposit" | "withdraw" | "transfer" | "initializeMint",
  "version": "legacy",
  "transactionBase64": "<base64-encoded unsigned transaction>",
  "sendTo": "base" | "ephemeral",
  "recentBlockhash": "<blockhash>",
  "lastValidBlockHeight": 284512337,
  "instructionCount": 3,
  "requiredSigners": ["<pubkey>"],
  "validator": "<pubkey>"
}
```

The client must:
1. Deserialize `transactionBase64`
2. Sign with each key in `requiredSigners`
3. Send to the chain indicated by `sendTo` (`"base"` = Solana, `"ephemeral"` = ER RPC)

## Error Responses

**400 (Build/Query error):**
```json
{ "error": { "code": "<string>", "message": "<string>", "details": {} } }
```

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

### POST /v1/spl/deposit

Deposit SPL tokens from Solana into an ephemeral rollup.

| Field | Type | Required | Description |
|---|---|---|---|
| owner | string (pubkey) | Yes | Wallet address |
| amount | integer (>=1) | Yes | Base-unit token amount |
| cluster | string | No | `"mainnet"`, `"devnet"`, or custom RPC URL. Defaults to mainnet |
| mint | string (pubkey) | No | Defaults to USDC (mainnet: `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`, devnet: `4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU`) |
| validator | string (pubkey) | No | Defaults to ephemeral RPC identity via `getIdentity` |
| initIfMissing | boolean | No | Auto-initialize missing accounts |
| initVaultIfMissing | boolean | No | Auto-initialize vault |
| initAtasIfMissing | boolean | No | Auto-initialize ATAs |
| idempotent | boolean | No | Returns success even if already completed |

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
| initIfMissing | boolean | No | Auto-initialize |
| initAtasIfMissing | boolean | No | Auto-initialize ATAs |
| initVaultIfMissing | boolean | No | Auto-initialize vault |
| memo | string | No | Appends a Memo Program instruction with this UTF-8 message |
| minDelayMs | string (numeric) | No | Private only. Min delay in ms. Defaults to `"0"` |
| maxDelayMs | string (numeric) | No | Private only. Max delay. Defaults to `"0"` or `minDelayMs` |
| split | integer (1-15) | No | Private only. Split into N sub-transfers. Defaults to 1 |

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
  "initVaultIfMissing": true,
  "memo": "Order #1042",
  "minDelayMs": "0",
  "maxDelayMs": "0",
  "split": 1
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
| initIfMissing | boolean | No | Auto-initialize |
| initAtasIfMissing | boolean | No | Auto-initialize ATAs |
| escrowIndex | integer (>=0) | No | Escrow index |
| idempotent | boolean | No | Returns success even if already completed |

```json
{
  "owner": "3rXKwQ1kpjBd5tdcco32qsvqUh1BnZjcYnS5kYrP7AYE",
  "mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  "amount": 1000000,
  "idempotent": true
}
```

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

### GET /v1/spl/balance

Get the base-chain SPL token balance for an address.

**Query params:** `address` (required), `mint` (required), `cluster` (optional)

```json
{
  "address": "<pubkey>",
  "mint": "<pubkey>",
  "ata": "<pubkey>",
  "location": "base",
  "balance": "1000000"
}
```

---

### GET /v1/spl/private-balance

Get the ephemeral-rollup SPL token balance for an address.

Same params as `/v1/spl/balance`. Response has `"location": "ephemeral"`.

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

## MCP Endpoint

### POST /mcp

Stateless Streamable HTTP MCP endpoint (JSON-RPC 2.0). Each request creates a fresh server with no session state.

**Headers:** `Content-Type: application/json`, `Accept: application/json`

MCP tool names mirror the REST endpoints with identical arguments: `spl.deposit`, `spl.transfer`, `spl.withdraw`, `spl.balance`, `spl.privateBalance`, `spl.initializeMint`, `spl.isMintInitialized`.

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
      "initVaultIfMissing": true,
      "idempotent": true
    }
  }
}
```

MCP responses include `result.structuredContent` with the same fields as the REST response.

## Key Details

- Amounts are always in base units (e.g., 1 USDC = 1,000,000 with 6 decimals)
- `mint` defaults to USDC when omitted on deposit
- `validator` defaults to the ephemeral RPC identity resolved via `getIdentity` when omitted
- `cluster` accepts `"mainnet"`, `"devnet"`, or a custom `http(s)` RPC URL
- Private transfers support `split` (1-15) to break a transfer into multiple sub-transfers and `minDelayMs`/`maxDelayMs` for timing obfuscation
- Set `initIfMissing`, `initAtasIfMissing`, and `initVaultIfMissing` all to `true` for the simplest integration
- `idempotent`: when `true`, returns success even if the operation was already completed
