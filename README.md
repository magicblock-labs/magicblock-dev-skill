# MagicBlock Dev Skill

An AI development skill for planning, implementing, and debugging MagicBlock applications on Solana.

## Installation

### Quick install

```bash
npx add-skill https://github.com/magicblock-labs/magicblock-dev-skill
```

### Manual install

```bash
git clone https://github.com/magicblock-labs/magicblock-dev-skill
cd magicblock-dev-skill
./install.sh
```

By default, `./install.sh` installs the skill to both personal skill directories:

- `~/.claude/skills/magicblock`
- `${CODEX_HOME:-~/.codex}/skills/magicblock`

### Targeting specific agents

Global / per-user targets:

```bash
./install.sh --claude
./install.sh --codex
```

Project-scoped targets (always install into the current directory):

```bash
./install.sh --cursor       # writes .cursor/rules/magicblock.mdc
./install.sh --windsurf     # writes .windsurf/rules/magicblock.md
./install.sh --cline        # writes .clinerules/magicblock.md
./install.sh --continue     # writes .continue/rules/magicblock.md
./install.sh --agents-md    # writes ./AGENTS.md
```

Combined:

```bash
./install.sh --all          # everything for the current project
./install.sh --project      # Claude + Codex into .claude/.codex inside the project
./install.sh --path /custom/path/magicblock
```

The single-file targets (Cursor, Windsurf, Cline, Continue, AGENTS.md) use lean artifacts by default:
architecture, composition, security, debugging, and source/version guidance are preloaded while
product-specific references remain fetch-on-demand. This five-guide list is the canonical core set in
`build.sh`. Use `--full` to preload every guide:

```bash
./install.sh --cursor --full
./install.sh --agents-md --full
```

Folder-based Claude/Codex installs always include every guide under `skill/references/` and rely on
progressive disclosure from `skill/SKILL.md`.
Single-file artifacts record the exact source commit, artifact-link mode, and content fingerprint.
Fetch-on-demand links are pinned to that commit only when the artifact inputs (`build.sh` and `skill/`)
are clean, `origin` is the canonical MagicBlock repository, and a local `origin/*` remote-tracking ref
contains `HEAD`. This is an offline proof based on the last fetched remote state; the build does not use
the network. Otherwise it produces self-contained single-file artifacts and rewrites cross-guide links
to explicit internal anchors. Unrelated changes such as README edits do not switch artifact mode.
When built from a source archive or vendored directory without Git metadata, provenance is recorded as
`unversioned` with commit `unknown` (or `MAGICBLOCK_SOURCE_COMMIT` when the packager supplies one), and
single-file artifacts are always self-contained. A Git checkout is required only for the offline proof
that permits lean, exact-commit fetch links; it is not required to build or install the skill.
`install.sh` runs `./build.sh` automatically when the required `dist/` artifact is missing or its
recorded fingerprint no longer matches the source commit, artifact-input state, link availability,
`build.sh`, and every regular file packaged under `skill/`.

### Building dist/ artifacts manually

```bash
./build.sh
```

Produces:

- `dist/AGENTS.md` — lean flattened skill for default single-file installs
- `dist/AGENTS.full.md` — full flattened skill with every product reference
- `dist/system-prompt.md` — lean SKILL.md + exact-commit reference URLs when locally proven published,
  or self-contained otherwise
- `dist/magicblock.cursor.mdc` — lean Cursor rule
- `dist/magicblock.full.cursor.mdc` — full Cursor rule
- `dist/magicblock.zip` — zipped `skill/` folder for Claude.ai upload

## Recommended companion skill: `solana-dev`

This skill covers MagicBlock-specific patterns: ER/PER, delegation, oracles, Session Keys, cranks, VRF,
Magic Actions, eSPL, and private payments. It assumes base-layer Solana and Anchor fluency. For program
scaffolding, PDAs, SPL tokens, clients, wallets, and LiteSVM/Mollusk testing, install the Solana
Foundation's [`solana-dev`](https://github.com/solana-foundation/solana-dev-skill) skill alongside it:

```bash
npx skills add https://github.com/solana-foundation/solana-dev-skill --skill solana-dev
```

Skills do not install dependencies automatically. See the
[solana-dev-skill repository](https://github.com/solana-foundation/solana-dev-skill) for other install
options. With both installed, agents use `solana-dev` for base-layer work and this skill for MagicBlock.

## What This Skill Covers

- MagicBlock architecture planning: product selection, account placement, delegation groups, routing, settlement, recovery, and validation environments
- MagicBlock Ephemeral Rollups integration
- Ephemeral Accounts for temporary ER-only state
- Pricing Oracle integration and safe feed consumption
- Session Keys for scoped temporary authority
- Debugging live ER transaction failures, delegation-state mismatches, and router/ER endpoint selection
- Delegating/undelegating Solana accounts
- High-performance, low-latency transaction flows
- Crank scheduling (recurring automated transactions)
- VRF (Verifiable Random Function) for provable randomness
- Magic Actions — base-layer instructions chained to an ER commit
- Topping up delegated accounts with lamports via `lamportsDelegatedTransferIx`
- Ephemeral SPL Token lifecycle: deposit, transfer, app-program CPI, undelegate, withdraw
- Dual-connection architecture (base layer + ephemeral rollup)
- Gaming and real-time app development on Solana
- Private payments (deposits, transfers, withdrawals, and swaps via the Payments API, with wallet challenge/login bearer auth for private reads and protected Private-ER routes)
- Commit sponsorship and lifting the 10-commit default with `magic_fee_vault`
- Local development and environment-specific validation
- Cross-product composition patterns and their security/settlement boundaries
- Source-backed MagicBlock security guidance that separates protocol guarantees, integration checks,
  application policy, and general Solana security

## Usage

The skill activates automatically when you ask about MagicBlock or Ephemeral Rollups.

- In Claude Code, you can also invoke it directly with `/magicblock`.
- In Codex, you can mention it explicitly by name, for example: `use the magicblock skill`.
- In Cursor / Windsurf / Cline / Continue, the rule's description triggers contextually when you mention MagicBlock topics.
- For chat-only platforms, the skill is loaded once via the system prompt and persists for the session.

Examples:

```
Design the MagicBlock architecture for a real-time trading application
Plan which accounts my multiplayer game should delegate and when they should settle
Add delegation hooks to my player account
Debug why my delegated account gets InvalidWritableAccount
Change my roll_dice function to use VRF
Set up a crank that updates game state every 100ms
Add a Magic Action that updates my onchain leaderboard after every commit
Top up my delegated fee payer with lamports
Deposit SPL tokens into the ER, transfer them, and withdraw back to base layer
Build a private USDC transfer flow using the Payments API
Build a prediction market with the Pricing Oracle, Session Keys, eSPL, and an ER
Use Ephemeral Accounts for temporary match or chat state
Choose which local and Devnet tests prove my MagicBlock integration
Help me integrate MagicBlock into my Anchor program
```

## License

MIT
