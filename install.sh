#!/bin/bash

# MagicBlock Dev Skill Installer
# Installs the skill into Claude Code, Codex, Cursor, Windsurf, Cline, Continue,
# or as an AGENTS.md file at the project root.
#
# Usage: ./install.sh [TARGET FLAGS] [--project] [--path <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="magicblock"
SOURCE_DIR="$SCRIPT_DIR/skill"
DIST_DIR="$SCRIPT_DIR/dist"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

INSTALL_CLAUDE=false
INSTALL_CODEX=false
INSTALL_CURSOR=false
INSTALL_WINDSURF=false
INSTALL_CLINE=false
INSTALL_CONTINUE=false
INSTALL_AGENTS_MD=false
PROJECT_INSTALL=false
CUSTOM_PATH=""
TARGET_SELECTED=false

print_help() {
    cat <<EOF
MagicBlock Dev Skill Installer

Usage: ./install.sh [OPTIONS]

Targets with global + project install location:
  --claude       Install for Claude Code (~/.claude/skills/$SKILL_NAME)
  --codex        Install for Codex (~/.codex/skills/$SKILL_NAME)

Project-scoped targets (always install into the current directory):
  --cursor       Install Cursor rule (.cursor/rules/$SKILL_NAME.mdc)
  --windsurf     Install Windsurf rule (.windsurf/rules/$SKILL_NAME.md)
  --cline        Install Cline rule (.clinerules/$SKILL_NAME.md)
  --continue     Install Continue rule (.continue/rules/$SKILL_NAME.md)
  --agents-md    Write flattened AGENTS.md to the project root

Combined:
  --all          Install all of the above into the current project
                 (Claude/Codex use project-scoped paths)

Modifiers:
  --project      For --claude/--codex, install to .claude/.codex inside the
                 current project instead of the global location
  --path PATH    Install the raw skill/ folder to a custom path
  -h, --help     Show this help message

Defaults:
  No target flags  Install --claude and --codex to their global locations

Notes:
  --cursor, --windsurf, --cline, --continue, and --agents-md are always
  project-scoped and ignore the --project flag.
EOF
}

# Ensure dist/ artifacts exist; build if missing
ensure_built() {
    if [ ! -f "$DIST_DIR/AGENTS.md" ] || [ ! -f "$DIST_DIR/$SKILL_NAME.cursor.mdc" ]; then
        echo "Building dist/ artifacts..."
        bash "$SCRIPT_DIR/build.sh" >/dev/null
    fi
}

# Install a directory (used for Claude Code, Codex, custom path)
install_dir_to_path() {
    local install_path="$1"
    local label="$2"

    if [[ -e "$install_path" && ! -d "$install_path" ]]; then
        echo "Error: '$install_path' exists and is not a directory"
        return 1
    fi

    if [ -d "$install_path" ]; then
        echo "Warning: '$install_path' already exists"
        read -r -p "Overwrite $label? (y/N) " reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            echo "Skipped $label"
            return 1
        fi
        rm -rf "$install_path"
    fi

    mkdir -p "$install_path"
    cp -R "$SOURCE_DIR"/. "$install_path"/

    echo "Installed $label to: $install_path"
    return 0
}

# Install a single file (used for Cursor/Windsurf/Cline/Continue/AGENTS.md)
install_file_to_path() {
    local source_file="$1"
    local install_path="$2"
    local label="$3"

    if [ -f "$install_path" ]; then
        echo "Warning: '$install_path' already exists"
        read -r -p "Overwrite $label? (y/N) " reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            echo "Skipped $label"
            return 1
        fi
    fi

    mkdir -p "$(dirname "$install_path")"
    cp "$source_file" "$install_path"

    echo "Installed $label to: $install_path"
    return 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --claude)
            INSTALL_CLAUDE=true; TARGET_SELECTED=true; shift ;;
        --codex)
            INSTALL_CODEX=true; TARGET_SELECTED=true; shift ;;
        --cursor)
            INSTALL_CURSOR=true; TARGET_SELECTED=true; shift ;;
        --windsurf)
            INSTALL_WINDSURF=true; TARGET_SELECTED=true; shift ;;
        --cline)
            INSTALL_CLINE=true; TARGET_SELECTED=true; shift ;;
        --continue)
            INSTALL_CONTINUE=true; TARGET_SELECTED=true; shift ;;
        --agents-md)
            INSTALL_AGENTS_MD=true; TARGET_SELECTED=true; shift ;;
        --all)
            INSTALL_CLAUDE=true
            INSTALL_CODEX=true
            INSTALL_CURSOR=true
            INSTALL_WINDSURF=true
            INSTALL_CLINE=true
            INSTALL_CONTINUE=true
            INSTALL_AGENTS_MD=true
            PROJECT_INSTALL=true
            TARGET_SELECTED=true
            shift ;;
        --project)
            PROJECT_INSTALL=true; shift ;;
        --path)
            if [[ $# -lt 2 ]]; then
                echo "Error: --path requires a value"
                exit 1
            fi
            CUSTOM_PATH="$2"; shift 2 ;;
        -h|--help)
            print_help; exit 0 ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1 ;;
    esac
done

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' not found"
    exit 1
fi

if [ ! -f "$SOURCE_DIR/SKILL.md" ]; then
    echo "Error: SKILL.md not found in '$SOURCE_DIR'"
    exit 1
fi

# --path is exclusive
if [[ -n "$CUSTOM_PATH" ]] && [[ "$TARGET_SELECTED" == true || "$PROJECT_INSTALL" == true ]]; then
    echo "Error: --path cannot be combined with other target flags"
    exit 1
fi

if [[ -n "$CUSTOM_PATH" ]]; then
    if install_dir_to_path "$CUSTOM_PATH" "custom path"; then
        echo ""
        echo "The skill is now available at: $CUSTOM_PATH"
    else
        echo ""
        echo "No targets were installed."
    fi
    exit 0
fi

# Default: install Claude + Codex globally
if [[ "$TARGET_SELECTED" == false ]]; then
    INSTALL_CLAUDE=true
    INSTALL_CODEX=true
fi

# Resolve Claude / Codex install paths
if [[ "$PROJECT_INSTALL" == true ]]; then
    CLAUDE_PATH=".claude/skills/$SKILL_NAME"
    CODEX_PATH=".codex/skills/$SKILL_NAME"
else
    CLAUDE_PATH="$CLAUDE_HOME/skills/$SKILL_NAME"
    CODEX_PATH="$CODEX_HOME/skills/$SKILL_NAME"
fi

# Editor-rule targets are always project-scoped
CURSOR_PATH=".cursor/rules/$SKILL_NAME.mdc"
WINDSURF_PATH=".windsurf/rules/$SKILL_NAME.md"
CLINE_PATH=".clinerules/$SKILL_NAME.md"
CONTINUE_PATH=".continue/rules/$SKILL_NAME.md"
AGENTS_MD_PATH="AGENTS.md"

# Build dist/ if any single-file targets are selected
if [[ "$INSTALL_CURSOR" == true || "$INSTALL_WINDSURF" == true || \
      "$INSTALL_CLINE" == true || "$INSTALL_CONTINUE" == true || \
      "$INSTALL_AGENTS_MD" == true ]]; then
    ensure_built
fi

declare -a INSTALLED_TARGETS=()
CLAUDE_INSTALLED=false
CODEX_INSTALLED=false
CURSOR_INSTALLED=false
WINDSURF_INSTALLED=false
CLINE_INSTALLED=false
CONTINUE_INSTALLED=false
AGENTS_MD_INSTALLED=false

echo "Installing MagicBlock Dev Skill..."
echo ""

if [[ "$INSTALL_CLAUDE" == true ]]; then
    if install_dir_to_path "$CLAUDE_PATH" "Claude Code"; then
        INSTALLED_TARGETS+=("Claude Code:$CLAUDE_PATH")
        CLAUDE_INSTALLED=true
    fi
fi

if [[ "$INSTALL_CODEX" == true ]]; then
    if install_dir_to_path "$CODEX_PATH" "Codex"; then
        INSTALLED_TARGETS+=("Codex:$CODEX_PATH")
        CODEX_INSTALLED=true
    fi
fi

if [[ "$INSTALL_CURSOR" == true ]]; then
    if install_file_to_path "$DIST_DIR/$SKILL_NAME.cursor.mdc" "$CURSOR_PATH" "Cursor rule"; then
        INSTALLED_TARGETS+=("Cursor:$CURSOR_PATH")
        CURSOR_INSTALLED=true
    fi
fi

if [[ "$INSTALL_WINDSURF" == true ]]; then
    if install_file_to_path "$DIST_DIR/AGENTS.md" "$WINDSURF_PATH" "Windsurf rule"; then
        INSTALLED_TARGETS+=("Windsurf:$WINDSURF_PATH")
        WINDSURF_INSTALLED=true
    fi
fi

if [[ "$INSTALL_CLINE" == true ]]; then
    if install_file_to_path "$DIST_DIR/AGENTS.md" "$CLINE_PATH" "Cline rule"; then
        INSTALLED_TARGETS+=("Cline:$CLINE_PATH")
        CLINE_INSTALLED=true
    fi
fi

if [[ "$INSTALL_CONTINUE" == true ]]; then
    if install_file_to_path "$DIST_DIR/AGENTS.md" "$CONTINUE_PATH" "Continue rule"; then
        INSTALLED_TARGETS+=("Continue:$CONTINUE_PATH")
        CONTINUE_INSTALLED=true
    fi
fi

if [[ "$INSTALL_AGENTS_MD" == true ]]; then
    if install_file_to_path "$DIST_DIR/AGENTS.md" "$AGENTS_MD_PATH" "AGENTS.md"; then
        INSTALLED_TARGETS+=("AGENTS.md:$AGENTS_MD_PATH")
        AGENTS_MD_INSTALLED=true
    fi
fi

if [[ "${#INSTALLED_TARGETS[@]}" -eq 0 ]]; then
    echo ""
    echo "No targets were installed."
    exit 0
fi

echo ""
echo "Installed targets:"
for target in "${INSTALLED_TARGETS[@]}"; do
    echo "  - $target"
done

echo ""
if [[ "$CLAUDE_INSTALLED" == true ]]; then
    echo "Claude Code: ask about MagicBlock Ephemeral Rollups or use /magicblock."
fi
if [[ "$CODEX_INSTALLED" == true ]]; then
    echo "Codex: ask about MagicBlock Ephemeral Rollups or say 'use the magicblock skill'."
fi
if [[ "$CURSOR_INSTALLED" == true ]]; then
    echo "Cursor: rule will activate based on the description; reload Cursor if it was open."
fi
if [[ "$WINDSURF_INSTALLED" == true ]]; then
    echo "Windsurf: rule loaded from .windsurf/rules/; restart Cascade if it was open."
fi
if [[ "$CLINE_INSTALLED" == true ]]; then
    echo "Cline: rule loaded from .clinerules/; reload the VS Code extension if it was open."
fi
if [[ "$CONTINUE_INSTALLED" == true ]]; then
    echo "Continue: rule loaded from .continue/rules/; reload the VS Code extension if it was open."
fi
if [[ "$AGENTS_MD_INSTALLED" == true ]]; then
    echo "AGENTS.md: read by any tool that follows the AGENTS.md convention (Codex, Cursor, Aider, Continue, etc.)."
fi
