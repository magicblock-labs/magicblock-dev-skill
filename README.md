# MagicBlock Dev Skill

MagicBlock Ephemeral Rollups development skill for AI coding agents. The skill packages MagicBlock-specific patterns (delegation, Magic Actions, cranks, VRF, lamports top-up, commit sponsorship, private payments with swaps, dual-connection architecture) into a reusable workflow that activates automatically when you ask for MagicBlock or Ephemeral Rollups help.

## Supported Agents

| Agent | Format | Install location |
|---|---|---|
| Claude Code | Skills directory | `~/.claude/skills/magicblock/` |
| Claude.ai (chat/desktop) | Zip upload via Skills UI | `dist/magicblock.zip` |
| Codex | Skills directory | `~/.codex/skills/magicblock/` |
| Cursor | `.mdc` rule | `.cursor/rules/magicblock.mdc` |
| Windsurf | Markdown rule | `.windsurf/rules/magicblock.md` |
| Cline | Markdown rule | `.clinerules/magicblock.md` |
| Continue | Markdown rule | `.continue/rules/magicblock.md` |
| Cross-tool standard | `AGENTS.md` at repo root | `./AGENTS.md` |
| Chat-only (DeepSeek, ChatGPT default, etc.) | Paste as system prompt / custom instruction | `dist/system-prompt.md` |
| Custom GPTs | Paste into Instructions; upload `skill/*.md` as Knowledge | `dist/system-prompt.md` + `skill/` |

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

### Claude.ai upload

```bash
./build.sh
# Then upload dist/magicblock.zip via Settings → Capabilities → Skills in Claude.ai
```

### Chat-only platforms (DeepSeek, ChatGPT default, Claude.ai default)

```bash
./build.sh
cat dist/system-prompt.md
```

Paste the output into the platform's system prompt, custom instructions, or project context field.

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
- In Cursor / Windsurf / Cline / Continue, the rule's description triggers contextually when you mention MagicBlock topics.
- For chat-only platforms, the skill is loaded once via the system prompt and persists for the session.

Examples:

```
Add delegation hooks to my player account
Change my roll_dice function to use VRF
Set up a crank that updates game state every 100ms
Add a Magic Action that updates my onchain leaderboard after every commit
Top up my delegated fee payer with lamports
Build a private USDC transfer flow using the Payments API
Help me integrate MagicBlock into my Anchor program
```

## Structure

```
magicblock-dev-skill/
├── SKILL.md                     # Main entry point (in skill/)
├── README.md                    # This file
├── install.sh                   # Multi-agent installer
├── build.sh                     # Builds dist/ artifacts
├── skill/                       # Canonical source (single source of truth)
│   ├── SKILL.md                 # Main entry point
│   ├── agents/openai.yaml       # Codex UI metadata
│   ├── delegation.md            # Core delegation/undelegation patterns + commit sponsorship
│   ├── magic-actions.md         # Post-commit base-layer instructions
│   ├── lamports-topup.md        # Topping up delegated accounts with lamports
│   ├── typescript-setup.md      # TypeScript frontend setup
│   ├── cranks.md                # Scheduled tasks (cranks)
│   ├── vrf.md                   # Verifiable Random Function
│   ├── private-payments.md      # Private Payments API reference
│   └── resources.md             # Environment vars, versions, links
└── dist/                        # Generated by build.sh (gitignored)
    ├── AGENTS.md                # Cross-tool standard format
    ├── system-prompt.md         # Trimmed for chat-only platforms
    ├── magicblock.cursor.mdc    # Cursor format
    └── magicblock.zip           # For Claude.ai Skills upload
```

## License

MIT
