#!/bin/bash

# MagicBlock Dev Skill Installer for Claude Code and Codex
# Usage: ./install.sh [--claude] [--codex] [--project] [--path <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="magicblock"
SOURCE_DIR="$SCRIPT_DIR/skill"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

INSTALL_CLAUDE=false
INSTALL_CODEX=false
PROJECT_INSTALL=false
CUSTOM_PATH=""
TARGET_SELECTED=false

print_help() {
    echo "MagicBlock Dev Skill Installer"
    echo ""
    echo "Usage: ./install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --claude      Install for Claude Code only"
    echo "  --codex       Install for Codex only"
    echo "  --project     Install into the current project"
    echo "  --path PATH   Install to a custom path"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Defaults:"
    echo "  No target flags: install to both personal locations"
    echo "  Claude Code:   $CLAUDE_HOME/skills/$SKILL_NAME"
    echo "  Codex:         $CODEX_HOME/skills/$SKILL_NAME"
}

install_to_path() {
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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --claude)
            INSTALL_CLAUDE=true
            TARGET_SELECTED=true
            shift
            ;;
        --codex)
            INSTALL_CODEX=true
            TARGET_SELECTED=true
            shift
            ;;
        --project)
            PROJECT_INSTALL=true
            shift
            ;;
        --path)
            if [[ $# -lt 2 ]]; then
                echo "Error: --path requires a value"
                exit 1
            fi
            CUSTOM_PATH="$2"
            shift 2
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
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

if [[ -n "$CUSTOM_PATH" ]] && { [[ "$TARGET_SELECTED" == true ]] || [[ "$PROJECT_INSTALL" == true ]]; }; then
    echo "Error: --path cannot be combined with --claude, --codex, or --project"
    exit 1
fi

if [[ -n "$CUSTOM_PATH" ]]; then
    if install_to_path "$CUSTOM_PATH" "custom path"; then
        echo ""
        echo "The skill is now available at: $CUSTOM_PATH"
    else
        echo ""
        echo "No targets were installed."
    fi
    exit 0
fi

if [[ "$TARGET_SELECTED" == false ]]; then
    INSTALL_CLAUDE=true
    INSTALL_CODEX=true
fi

CLAUDE_PATH="$CLAUDE_HOME/skills/$SKILL_NAME"
CODEX_PATH="$CODEX_HOME/skills/$SKILL_NAME"

if [[ "$PROJECT_INSTALL" == true ]]; then
    CLAUDE_PATH=".claude/skills/$SKILL_NAME"
    CODEX_PATH=".codex/skills/$SKILL_NAME"
fi

declare -a INSTALLED_TARGETS=()
CLAUDE_INSTALLED=false
CODEX_INSTALLED=false

echo "Installing MagicBlock Dev Skill..."

if [[ "$INSTALL_CLAUDE" == true ]]; then
    if install_to_path "$CLAUDE_PATH" "Claude Code"; then
        INSTALLED_TARGETS+=("Claude Code:$CLAUDE_PATH")
        CLAUDE_INSTALLED=true
    fi
fi

if [[ "$INSTALL_CODEX" == true ]]; then
    if install_to_path "$CODEX_PATH" "Codex"; then
        INSTALLED_TARGETS+=("Codex:$CODEX_PATH")
        CODEX_INSTALLED=true
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
echo "Installed Markdown files:"
for target in "${INSTALLED_TARGETS[@]}"; do
    path="${target#*:}"
    find "$path" -type f -name "*.md" | sort | while read -r file; do
        echo "  - $file"
    done
done

echo ""
if [[ "$CLAUDE_INSTALLED" == true ]]; then
    echo "Claude Code: ask about MagicBlock Ephemeral Rollups or use /magicblock."
fi
if [[ "$CODEX_INSTALLED" == true ]]; then
    echo "Codex: ask about MagicBlock Ephemeral Rollups or say 'use the magicblock skill'."
fi
