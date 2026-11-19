# Local Development and Validation

MagicBlock applications span more than one runtime. A local Solana validator can validate ordinary
program logic, but it does not by itself prove delegation, ER routing, commits, PER privacy, VRF
callbacks, cranks, Magic Actions, or hosted payment services.

## Choose the environment by claim

| Claim to validate | Minimum useful environment |
|---|---|
| Pure instruction math and account constraints | Solana program test/LiteSVM/Mollusk where compatible |
| Base initialization and ordinary SPL behavior | Local Solana validator |
| Delegation, ER writes, commit, undelegate, Ephemeral Accounts | MagicSVM first; local MagicBlock stack or Devnet for live propagation |
| Router discovery and live multi-endpoint propagation | Devnet |
| Crank execution, VRF callback, Magic Action delivery | MagicSVM `0.3.0` for program logic (validator `1.1.1` `ScheduleTask` cranks, VRF callbacks, post-commit actions); Devnet for live service delivery |
| PER confidentiality/authorization boundary | TEE-backed PER environment |
| Hosted Private Payments API behavior | The actual API environment or its repository's supported local service setup |

Use the smallest environment that proves the current claim, then add a live integration test for the
cross-runtime behavior the product depends on.

## Local stack

The current package family includes `@magicblock-labs/ephemeral-validator`, with binaries such as
`mb-stack`, `mb-test-validator`, `ephemeral-validator`, `query-filtering-service`, `rpc-router`, and
`vrf-oracle`. `mb-stack` starts `mb-test-validator`, `ephemeral-validator`, and
`query-filtering-service`; it does not start the router or VRF oracle. Names, versions,
and required configuration are version-sensitive: inspect the current package metadata and official
local-development guide before scripting them.

For the known-good `1.1.1` snapshot verified 2026-11-13 (the 1.x line that every public ER except
devnet-us runs; npm `latest` is now `2.0.1`), start the pinned package in a dedicated terminal:

```bash
npx --yes --package=@magicblock-labs/ephemeral-validator@1.1.1 mb-stack
```

The `mb-stack` scripts are byte-identical to the earlier `0.13.7` snapshot. In `1.1.1`, the defaults are base RPC `http://127.0.0.1:8899`, internal ER RPC
`http://127.0.0.1:7799`, and public query-filtering/ER entrypoint `http://127.0.0.1:6699`; websocket
ports are each HTTP port plus one. Override them with `MB_STACK_BASE_PORT`, `MB_STACK_ER_PORT`, and
`MB_STACK_PUBLIC_PORT`. Extra CLI arguments are forwarded to `mb-test-validator`, so base-validator
flags such as account/program loading belong after `mb-stack`. Use `MB_STACK_ER_REMOTES` only when the
ER must clone from/commit to a nonlocal base. Stop the supervisor with the terminal interrupt and
confirm its child processes exit.

Validator 2.0 (released; npm `2.0.1` checked 2026-11-19) adds `mb-stack --vrf`, `--vrf-er`, and
`--cranker` (with `MB_STACK_CRANKER_KEYPAIR`) to start a VRF oracle and a Hydra cranker. On a local
2.0 stack, scheduled tasks never fire without `--cranker`. Do not script these flags against `1.1.1`.

Limitations:

- The stack does not build or deploy the user's program for them.
- Some service binaries require configuration and are not guaranteed to expose a harmless `--help`
  path. In particular, do not use `mb-stack --help` as a discovery probe because it can start services.
- A base validator plus ER does not automatically prove router, VRF, PER, or hosted API behavior.
- RPC URLs, validator identity, websocket URLs, and program deployments must agree across the test.

## MagicSVM

`magicsvm` (`@magicblock-labs/magicsvm` on npm, `magicsvm` crate; `0.3.0` verified 2026-11-18) runs a
base ledger and an ephemeral ledger in one process: no validators, no network, and tests that finish in
milliseconds. It executes the real Delegation Program and Magic program paths for delegate,
`ScheduleCommit`, `ScheduleCommitAndUndelegate`, `ScheduleCommitFinalize`, `ScheduleBaseIntent`, and
`ScheduleIntentBundle`, including post-delegation actions and post-commit actions (intent-bundle actions
run through DLP `CallHandlerV2` with `source_program`, legacy `ScheduleBaseIntent` actions through
`CallHandler`), Ephemeral Account create/resize/close with sponsor rent moved to and from the ephemeral
vault, eATA projection, the delegated magic fee vault, and permission-gated reads (Rust
`get_account_for(target, &pubkey)` hides private accounts unless `set_authorized_user` names a
permission member).

Since `0.3.0` it also runs:

- **VRF.** A stand-in for the VRF program (`Vrf1RNUj…`) with the default and test queues on both
  ledgers validates requests like `solana-vrf` and fulfills each one in the slot after the request,
  through the program's callback with the VRF identity as account 0. Fulfillments run in
  `warp_to_slot`; `set_vrf_randomness` pins the value. It doesn't model VRF proofs, queue contents, or
  the oracle being paid.
- **Cranks.** The Magic program accepts `ScheduleTask` and `CancelTask` with validator `1.1.1`
  validation, and `warp_to_slot` runs due tasks on their millisecond deadlines (50 ms slots) through
  the `Crank111…` executor with the crank signer PDA, using the validator's retry backoff. This is the
  live `1.1.1` model, not Hydra or validator 2.0.

`warp_to_slot` returns the results of the VRF fulfillments and crank runs it executed, in order. Base
transactions pay normal fees; ER transactions are fee-free.

It does not cover the router, commit limits or fee charging, Hydra cranks, the real VRF oracle, TEE
attestation, or cross-layer timing. Its permission-gated reads also miss the TEE's default token-account
privacy: in `0.3.0` an SPL token account with no permission PDA is readable by any viewer, while a TEE
shows it only to its owner (checked 2026-11-19). Do not use MagicSVM as evidence of TEE visibility for
token accounts. Programs are loaded from their compiled `.so`, so they can use any
SDK version; MagicSVM's own crate pins `ephemeral-rollups-sdk` `0.14.4`, which only matters if the test
crate shares SDK types with it. It is not evidence that live routing, service scheduling, TEE privacy,
or cross-layer propagation works.

### Writing a MagicSVM test

The Rust API (`cargo add --dev magicsvm@0.3.0`), in the order a test uses it:

```rust
use magicsvm::{MagicSVM, TransactionTarget};

let mut svm = MagicSVM::new();
svm.add_program_from_file(program_id, "target/deploy/my_program.so").unwrap();
svm.airdrop(&payer.pubkey(), 2_000_000_000).unwrap();
let validator = svm.validator_identity(); // delegate to this validator

// Initialize and delegate on base, then write on the ER.
svm.send_transaction_to(TransactionTarget::Base, init_and_delegate_tx).unwrap();
let tx = Transaction::new(&[&payer], message, svm.latest_blockhash_for(TransactionTarget::Ephemeral));
svm.send_transaction_to(TransactionTarget::Ephemeral, tx).unwrap();
svm.expire_blockhash_for(TransactionTarget::Ephemeral); // before resending identical bytes

// Read either ledger. A commit or undelegate is visible on base right after the ER transaction.
let account = svm.get_account_for(TransactionTarget::Base, &counter);

// Run the VRF callbacks and crank executions due up to a slot; VRF requests are
// fulfilled in the slot after the request.
let results = svm.warp_to_slot(request_slot + 1);
```

Failed transactions return `Err(FailedTransactionMetadata)`; assert on `failed.err` (for example
`TransactionError::InstructionError(0, InstructionError::Custom(2001))` for Anchor `ConstraintHasOne`)
rather than only on `is_err()`.

Working suites live in [magicblock-engine-examples](https://github.com/magicblock-labs/magicblock-engine-examples),
one `tests-magicsvm-rs/` crate per example with shared helpers in `test-utils/rust`:
`counter/anchor` (delegate, commit, undelegate), `crank-counter/anchor` (cranks), `roll-dice` and
`rewards-delegated-vrf/anchor` (VRF), `private-counter` and `sealed-auction/anchor` (PER privacy),
`spl-tokens/anchor` and `gasless-starter/anchor` (eATA deposits and fee-free ER transactions),
`magic-actions/anchor` (post-commit actions), and `ephemeral-account-chats/anchor` (Ephemeral
Accounts).

Pitfalls:

- MagicSVM needs a newer Rust than the 1.89 toolchain Anchor uses for program builds; run the suite
  with `cargo +stable test`.
- Build the program with `anchor build --ignore-keys` (or a pinned `anchor_version`); `anchor keys sync`
  rewrites `declare_id!` to a local keypair.
- A test crate that depends on an Anchor program with `no-entrypoint` can resolve newer
  `anchor-derive-*`/`anchor-syn` crates than the program's own `anchor-lang`, and fail to compile (for
  example on `create_account_allow_prefund`). Seed the test crate's `Cargo.lock` from the program's.

## Repeatable workflow

1. Pin or record package, validator, SDK, Anchor, and Solana versions from the target repository.
2. Start only the services needed for the test claim.
3. Build and deploy the program to the base validator used by the stack.
4. Resolve the ER validator identity and route all delegation to the intended ER.
5. Use separate base, router, and ER connections; never reuse a base blockhash for an ER transaction.
6. Initialize on base, delegate on base, discover/verify the ER, operate on ER, then commit or
   undelegate and confirm propagation back on base.
7. Capture transaction signatures and logs from both runtimes.
8. Tear down processes deterministically and avoid fixed sleeps where state polling is possible.

## Test gates

At minimum, a product integration should include:

- a fast deterministic program-logic test;
- a local or Devnet delegation lifecycle test;
- endpoint/ownership assertions before and after delegation;
- one failure/retry test for cross-runtime propagation;
- service-specific tests for VRF, cranks, Magic Actions, oracle freshness, or payments when used;
- a production-like configuration check without committing credentials.

When local behavior differs from Devnet, verify versions, program IDs, cloned accounts, validator
identity, and service availability before changing application logic.

Sources: [MagicBlock local development docs](https://docs.magicblock.gg/pages/ephemeral-rollups-ers/how-to-guide/local-development),
[ephemeral validator package](https://www.npmjs.com/package/@magicblock-labs/ephemeral-validator), and
[engine examples](https://github.com/magicblock-labs/magicblock-engine-examples).
