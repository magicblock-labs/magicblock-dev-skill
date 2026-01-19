# MagicBlock Dev Skill

MagicBlock Ephemeral Rollups development skill for [Claude Code](https://claude.ai/code).

## Installation

### Option 1: Install Script (Recommended)

```bash
git clone https://github.com/sporicle/claude.git /tmp/magicblock-skill
cd /tmp/magicblock-skill
./install.sh
rm -rf /tmp/magicblock-skill
```

This installs the skill to `~/.claude/skills/magicblock`, making it available in all projects.

#### Install Options

```bash
./install.sh                    # Install to ~/.claude/skills/magicblock (default)
./install.sh --project          # Install to .claude/skills/magicblock (current project only)
./install.sh --path /custom/path # Install to custom path
```

### Option 2: Manual Installation

```bash
git clone https://github.com/sporicle/claude.git /tmp/magicblock-skill
cp -r /tmp/magicblock-skill/skill ~/.claude/skills/magicblock
rm -rf /tmp/magicblock-skill
```

## What This Skill Covers

- MagicBlock Ephemeral Rollups integration
- Delegating/undelegating Solana accounts
- High-performance, low-latency transaction flows
- Crank scheduling (recurring automated transactions)
- VRF (Verifiable Random Function) for provable randomness
- Dual-connection architecture (base layer + ephemeral rollup)
- Gaming and real-time app development on Solana

## Usage

The skill activates automatically when you ask about MagicBlock or Ephemeral Rollups. Examples:

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
├── delegation.md         # Core delegation/undelegation patterns
├── typescript-setup.md   # TypeScript frontend setup
├── cranks.md             # Scheduled tasks (cranks)
├── vrf.md                # Verifiable Random Function
└── resources.md          # Environment vars, versions, links
```

## License

MIT
