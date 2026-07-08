# MagicBlock Dev Skill

MagicBlock Ephemeral Rollups development skill for AI coding agents. The skill packages MagicBlock-specific patterns (debugging live ER/delegation failures, delegation, Magic Actions, cranks, VRF, lamports top-up, commit sponsorship, private payments with swaps, dual-connection architecture) into a reusable workflow that activates automatically when you ask for MagicBlock or Ephemeral Rollups help.

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

The single-file targets (Cursor, Windsurf, Cline, Continue, AGENTS.md) are generated from `dist/` artifacts; `install.sh` runs `./build.sh` automatically if `dist/` is missing.

### Building dist/ artifacts manually

```bash
./build.sh
```

Produces:

- `dist/AGENTS.md` — full flattened skill (SKILL.md + all references)
- `dist/system-prompt.md` — trimmed SKILL.md + reference URLs (for chat-only platforms)
- `dist/magicblock.cursor.mdc` — Cursor-formatted rule with `.mdc` frontmatter
- `dist/magicblock.zip` — zipped `skill/` folder for Claude.ai upload

## What This Skill Covers

- MagicBlock Ephemeral Rollups integration
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
- Private payments (deposits, transfers, withdrawals, and swaps via the Payments API, with optional bearer-token auth for private reads)
- Commit sponsorship and lifting the 10-commit default with `magic_fee_vault`

## Usage

The skill activates automatically when you ask about MagicBlock or Ephemeral Rollups.

- In Claude Code, you can also invoke it directly with `/magicblock`.
- In Codex, you can mention it explicitly by name, for example: `use the magicblock skill`.
- In Cursor / Windsurf / Cline / Continue, the rule's description triggers contextually when you mention MagicBlock topics.
- For chat-only platforms, the skill is loaded once via the system prompt and persists for the session.

Examples:

```
Add delegation hooks to my player account
Debug why my delegated account gets InvalidWritableAccount
Change my roll_dice function to use VRF
Set up a crank that updates game state every 100ms
Add a Magic Action that updates my onchain leaderboard after every commit
Top up my delegated fee payer with lamports
Deposit SPL tokens into the ER, transfer them, and withdraw back to base layer
Build a private USDC transfer flow using the Payments API
Help me integrate MagicBlock into my Anchor program
```

## License

MIT
