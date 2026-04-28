# MagicBlock Dev Skill

MagicBlock Ephemeral Rollups development skill for [Claude Code](https://claude.ai/code) and Codex.

## Installation

### Claude Code quick install

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

You can target a specific environment:

```bash
./install.sh --claude
./install.sh --codex
./install.sh --project
./install.sh --project --codex
./install.sh --path /custom/path/magicblock
```

`--project` installs into the current repository under `.claude/skills/magicblock` and/or `.codex/skills/magicblock`.

## What This Skill Covers

- MagicBlock Ephemeral Rollups integration
- Delegating/undelegating Solana accounts
- High-performance, low-latency transaction flows
- Crank scheduling (recurring automated transactions)
- VRF (Verifiable Random Function) for provable randomness
- Magic Actions — base-layer instructions chained to an ER commit
- Topping up delegated accounts with lamports via `lamportsDelegatedTransferIx`
- Dual-connection architecture (base layer + ephemeral rollup)
- Gaming and real-time app development on Solana
- Private payments (deposits, transfers, withdrawals, and swaps via the Payments API, with optional bearer-token auth for private reads)
- Commit sponsorship and lifting the 10-commit default with `magic_fee_vault`

## Usage

The skill activates automatically when you ask about MagicBlock or Ephemeral Rollups.

- In Claude Code, you can also invoke it directly with `/magicblock`.
- In Codex, you can mention it explicitly by name, for example: `use the magicblock skill`.

Examples:

```
Add delegation hooks to my player account
Change my roll_dice function to use VRF
Set up a crank that updates game state every 100ms
Help me integrate MagicBlock into my Anchor program
```

## Structure

```
skill/
├── SKILL.md              # Main entry point
├── agents/openai.yaml    # Codex UI metadata
├── delegation.md         # Core delegation/undelegation patterns + commit sponsorship
├── magic-actions.md      # Post-commit base-layer instructions
├── lamports-topup.md     # Topping up delegated accounts with lamports
├── typescript-setup.md   # TypeScript frontend setup
├── cranks.md             # Scheduled tasks (cranks)
├── vrf.md                # Verifiable Random Function
├── private-payments.md   # Private Payments API reference
└── resources.md          # Environment vars, versions, links
```

## License

MIT
