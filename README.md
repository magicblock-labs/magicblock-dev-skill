# MagicBlock Dev Skill

MagicBlock Ephemeral Rollups development skill for [Claude Code](https://claude.ai/code).

## Installation

### Quick Install

```bash
npx add-skill https://github.com/magicblock-labs/magicblock-dev-skill
```

### Manual Install

```bash
git clone https://github.com/magicblock-labs/magicblock-dev-skill
cd skill
./install.sh
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
