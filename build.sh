#!/bin/bash

# MagicBlock Dev Skill - Build Script
# Produces lean default artifacts plus explicit full-context variants.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$SCRIPT_DIR/skill"
REFERENCE_DIR="$SKILL_DIR/references"
DIST_DIR="$SCRIPT_DIR/dist"
SKILL_NAME="magicblock"
REPO_URL="https://github.com/magicblock-labs/magicblock-dev-skill"
GIT_CONTEXT=false
GIT_ROOT=""
if command -v git >/dev/null 2>&1; then
    GIT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ "$GIT_ROOT" = "$SCRIPT_DIR" ]; then
    GIT_CONTEXT=true
    SOURCE_COMMIT="$(git -C "$SCRIPT_DIR" rev-parse HEAD)"
    ORIGIN_URL="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)"
    if [ -z "$(git -C "$SCRIPT_DIR" status --porcelain --untracked-files=normal -- build.sh skill)" ]; then
        SOURCE_STATE="clean"
    else
        SOURCE_STATE="dirty"
    fi
else
    SOURCE_COMMIT="${MAGICBLOCK_SOURCE_COMMIT:-unknown}"
    SOURCE_STATE="unversioned"
    ORIGIN_URL=""
fi
SOURCE_BLOB_URL="$REPO_URL/blob/$SOURCE_COMMIT/skill"
REFERENCE_BLOB_URL="$SOURCE_BLOB_URL/references"

is_canonical_origin() {
    case "$ORIGIN_URL" in
        https://github.com/magicblock-labs/magicblock-dev-skill|\
        https://github.com/magicblock-labs/magicblock-dev-skill.git|\
        git@github.com:magicblock-labs/magicblock-dev-skill|\
        git@github.com:magicblock-labs/magicblock-dev-skill.git|\
        ssh://git@github.com/magicblock-labs/magicblock-dev-skill|\
        ssh://git@github.com/magicblock-labs/magicblock-dev-skill.git)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

head_is_origin_tracked() {
    git -C "$SCRIPT_DIR" for-each-ref \
        --format='%(refname)' \
        --contains "$SOURCE_COMMIT" \
        refs/remotes/origin/ \
        | grep -Evq '^refs/remotes/origin/HEAD$'
}

# Exact-commit links are emitted only when local Git state proves that the
# canonical origin has advertised this commit. Builds remain fully offline.
if [ "$GIT_CONTEXT" = true ] && [ "$SOURCE_STATE" = "clean" ] && \
   is_canonical_origin && head_is_origin_tracked; then
    LINK_MODE="exact-commit"
else
    LINK_MODE="self-contained"
fi

select_hash_backend() {
    local requested="${MAGICBLOCK_HASH_BACKEND:-auto}"
    case "$requested" in
        auto)
            if command -v sha256sum >/dev/null 2>&1; then
                HASH_BACKEND="sha256sum"
            elif command -v shasum >/dev/null 2>&1; then
                HASH_BACKEND="shasum"
            elif command -v openssl >/dev/null 2>&1; then
                HASH_BACKEND="openssl"
            else
                echo "Error: no SHA-256 tool found; install sha256sum, shasum, or openssl" >&2
                exit 1
            fi
            ;;
        sha256sum|shasum|openssl)
            if ! command -v "$requested" >/dev/null 2>&1; then
                echo "Error: requested SHA-256 backend '$requested' is unavailable" >&2
                exit 1
            fi
            HASH_BACKEND="$requested"
            ;;
        *)
            echo "Error: MAGICBLOCK_HASH_BACKEND must be auto, sha256sum, shasum, or openssl" >&2
            exit 1
            ;;
    esac
}

hash_stream() {
    case "$HASH_BACKEND" in
        sha256sum) LC_ALL=C LANG=C sha256sum | awk '{print $1}' ;;
        shasum) LC_ALL=C LANG=C shasum -a 256 | awk '{print $1}' ;;
        openssl) LC_ALL=C LANG=C openssl dgst -sha256 | awk '{print $NF}' ;;
    esac
}

hash_file() {
    hash_stream < "$1"
}

select_hash_backend

# Keep this in the same order as SKILL.md's Progressive disclosure section.
ALL_REFERENCES=(
    "architecture-planning.md"
    "composition-patterns.md"
    "security.md"
    "debugging.md"
    "delegation.md"
    "ephemeral-accounts.md"
    "magic-actions.md"
    "lamports-topup.md"
    "ephemeral-spl-token.md"
    "typescript-setup.md"
    "cranks.md"
    "vrf.md"
    "pricing-oracle.md"
    "session-keys.md"
    "private-payments.md"
    "local-development.md"
    "resources.md"
)

# Canonical clean-build preload: planning, composition, security, debugging,
# and source/version guidance. Product details stay fetch-on-demand.
CORE_REFERENCES=(
    "architecture-planning.md"
    "composition-patterns.md"
    "security.md"
    "debugging.md"
    "resources.md"
)

strip_frontmatter() {
    local file="$1"
    awk '
        BEGIN { in_fm = 0; line_count = 0 }
        {
            line_count++
            if (line_count == 1 && /^---$/) { in_fm = 1; next }
            if (in_fm && /^---$/) { in_fm = 0; next }
            if (in_fm) next
            print
        }
    ' "$file"
}

source_fingerprint() {
    (
        cd "$SCRIPT_DIR"
        {
            printf 'source-commit %s\n' "$SOURCE_COMMIT"
            printf 'source-state %s\n' "$SOURCE_STATE"
            printf 'link-mode %s\n' "$LINK_MODE"
            printf 'build.sh %s\n' "$(hash_file build.sh)"
            find skill -type f ! -name '.DS_Store' | LC_ALL=C sort | while IFS= read -r path; do
                printf '%s %s\n' "$path" "$(hash_file "$path")"
            done
        } | hash_stream
    )
}

if [ "${1:-}" = "--source-fingerprint" ]; then
    source_fingerprint
    exit 0
fi

if [ "$#" -gt 0 ]; then
    echo "Usage: $0 [--source-fingerprint]" >&2
    exit 1
fi

SOURCE_FINGERPRINT="$(source_fingerprint)"

rewrite_local_md_links_clean() {
    sed -E \
        -e "s|\]\((references/)?([^/:)#]+\.md)(#[^)]*)?\)|]($REFERENCE_BLOB_URL/\2\3)|g"
}

guide_anchor() {
    local ref="$1"
    printf 'guide-%s\n' "${ref%.md}"
}

rewrite_local_md_links_self_contained() {
    local content ref escaped_ref anchor
    content="$(cat)"
    for ref in "${ALL_REFERENCES[@]}"; do
        escaped_ref="${ref//./\\.}"
        anchor="$(guide_anchor "$ref")"
        content="$(printf '%s\n' "$content" \
            | sed -E "s|\]\((references/)?${escaped_ref}(#[^)]+)?\)|](#$anchor)|g")"
    done
    printf '%s\n' "$content"
}

namespace_intra_guide_links() {
    local file="$1"
    local ref="$2"
    local prefix fragments
    prefix="$(guide_anchor "$ref")"
    fragments="$(
        strip_frontmatter "$file" \
            | grep -Eo '\]\(#[^)]+\)' \
            | sed -E 's/^\]\(#([^)]*)\)$/\1/' \
            | LC_ALL=C sort -u \
            | tr '\n' ' ' \
            || true
    )"

    strip_frontmatter "$file" \
        | awk -v prefix="$prefix" -v fragments="$fragments" '
            BEGIN {
                count = split(fragments, values, " ")
                for (i = 1; i <= count; i++) {
                    if (values[i] != "") wanted[values[i]] = 1
                }
                in_fence = 0
            }
            function heading_slug(value, slug) {
                slug = tolower(value)
                gsub(/`/, "", slug)
                gsub(/[^[:alnum:] _-]/, "", slug)
                gsub(/[[:space:]]/, "-", slug)
                return slug
            }
            {
                if ($0 ~ /^```/ || $0 ~ /^~~~/) {
                    in_fence = !in_fence
                    print
                    next
                }
                if (!in_fence && $0 ~ /^#{1,6}[[:space:]]+/) {
                    heading = $0
                    sub(/^#{1,6}[[:space:]]+/, "", heading)
                    slug = heading_slug(heading)
                    if (wanted[slug]) {
                        printf "<a id=\"%s--%s\"></a>\n\n", prefix, slug
                    }
                }
                print
            }
        ' \
        | sed -E "s|\]\(#([^)]+)\)|](#$prefix--\1)|g"
}

render_source() {
    local file="$1"
    local content_mode="$2"
    if [ "$content_mode" = "exact-commit" ]; then
        strip_frontmatter "$1" | rewrite_local_md_links_clean
    else
        # Self-contained artifacts use explicit per-guide anchors. Cross-guide
        # fragments intentionally resolve to the guide boundary rather than to
        # an inferred renderer-specific heading slug.
        strip_frontmatter "$file" | rewrite_local_md_links_self_contained
    fi
}

render_guide() {
    local ref="$1"
    local content_mode="$2"
    if [ "$content_mode" = "self-contained" ]; then
        printf '<a id="%s"></a>\n\n' "$(guide_anchor "$ref")"
        namespace_intra_guide_links "$REFERENCE_DIR/$ref" "$ref" \
            | rewrite_local_md_links_self_contained
    else
        render_source "$REFERENCE_DIR/$ref" "$content_mode"
    fi
}

extract_title() {
    local file="$1"
    awk '
        BEGIN { in_fm = 0; line_count = 0 }
        {
            line_count++
            if (line_count == 1 && /^---$/) { in_fm = 1; next }
            if (in_fm && /^---$/) { in_fm = 0; next }
            if (in_fm) next
            if (/^# /) { sub(/^# /, ""); print; exit }
        }
    ' "$file"
}

contains_reference() {
    local needle="$1"
    local ref
    for ref in "${ALL_REFERENCES[@]}"; do
        if [ "$ref" = "$needle" ]; then return 0; fi
    done
    return 1
}

validate_sources() {
    local ref path path_dir file link target lines skill_manifest array_manifest

    for ref in "${ALL_REFERENCES[@]}"; do
        if [ ! -f "$REFERENCE_DIR/$ref" ]; then
            echo "Error: missing reference file: $ref" >&2
            exit 1
        fi
    done

    if [ "$LINK_MODE" = "exact-commit" ]; then
        if ! git -C "$SCRIPT_DIR" cat-file -e "$SOURCE_COMMIT:skill/SKILL.md"; then
            echo "Error: skill/SKILL.md does not exist at source commit $SOURCE_COMMIT" >&2
            exit 1
        fi
        for ref in "${ALL_REFERENCES[@]}"; do
            if ! git -C "$SCRIPT_DIR" cat-file -e "$SOURCE_COMMIT:skill/references/$ref"; then
                echo "Error: $ref does not exist at source commit $SOURCE_COMMIT" >&2
                exit 1
            fi
        done
    fi

    skill_manifest="$(
        awk '
            /^## Progressive disclosure/ { in_manifest = 1; next }
            in_manifest && /^## / { exit }
            in_manifest { print }
        ' "$SKILL_DIR/SKILL.md" \
            | sed -nE 's/.*\]\((references\/)?([^/)#]+\.md)(#[^)]*)?\).*/\2/p'
    )"
    array_manifest="$(printf '%s\n' "${ALL_REFERENCES[@]}")"
    if [ "$skill_manifest" != "$array_manifest" ]; then
        echo "Error: ALL_REFERENCES must exactly match SKILL.md Progressive disclosure order" >&2
        echo "ALL_REFERENCES:" >&2
        printf '  %s\n' "${ALL_REFERENCES[@]}" >&2
        echo "SKILL.md:" >&2
        printf '%s\n' "$skill_manifest" | sed 's/^/  /' >&2
        exit 1
    fi

    for path in "$REFERENCE_DIR"/*.md; do
        file="$(basename "$path")"
        if ! contains_reference "$file"; then
            echo "Error: $file exists but is not listed in ALL_REFERENCES" >&2
            exit 1
        fi
    done

    for path in "$SKILL_DIR/SKILL.md" "$REFERENCE_DIR"/*.md; do
        file="${path#"$SKILL_DIR/"}"
        path_dir="$(dirname "$path")"

        while IFS= read -r link; do
            target="${link#](}"
            target="${target%)}"
            target="${target%%#*}"
            case "$target" in
                http://*|https://*|mailto:*|"") continue ;;
            esac
            if [[ "$target" == *.md ]] && [ ! -f "$path_dir/$target" ]; then
                echo "Error: broken local Markdown link in $file: $target" >&2
                exit 1
            fi
        done < <(grep -Eo '\]\([^)]*\.md(#[^)]*)?\)' "$path" || true)
    done

    lines="$(wc -l < "$SKILL_DIR/SKILL.md" | tr -d ' ')"
    if [ "$lines" -gt 500 ]; then
        echo "Error: skill/SKILL.md is $lines lines; keep the core under 500" >&2
        exit 1
    fi
}

build_flattened() {
    local out="$1"
    local label="$2"
    local content_mode="$3"
    shift 3
    local ref
    {
        echo "<!-- Auto-generated $label artifact by build.sh from $REPO_URL -->"
        echo "<!-- Source commit: $SOURCE_COMMIT -->"
        echo "<!-- Source state: $SOURCE_STATE -->"
        echo "<!-- Artifact link mode: $content_mode -->"
        echo "<!-- Source fingerprint: sha256:$SOURCE_FINGERPRINT -->"
        if [ "$content_mode" = "exact-commit" ]; then
            echo "<!-- Fetch-on-demand reference: $SOURCE_BLOB_URL -->"
        else
            echo "<!-- Artifact mode: self-contained; exact canonical-origin publication is not locally proven or the artifact is explicitly full -->"
        fi
        echo ""
        render_source "$SKILL_DIR/SKILL.md" "$content_mode"
        for ref in "$@"; do
            echo ""
            echo "---"
            echo ""
            render_guide "$ref" "$content_mode"
        done
        if [[ "$label" == lean* ]] && [ "$content_mode" = "exact-commit" ]; then
            echo ""
            echo "---"
            echo ""
            echo "## Fetch-on-demand product references"
            echo ""
            echo "The default artifact stays lean. Fetch the relevant deep guide when its product or failure mode is selected:"
            echo ""
            for ref in "${ALL_REFERENCES[@]}"; do
                echo "- [$ref]($REFERENCE_BLOB_URL/$ref)"
            done
        fi
    } > "$out"
    echo "Built: $out ($(wc -c < "$out" | tr -d ' ') bytes)"
}

build_system_prompt() {
    local out="$DIST_DIR/system-prompt.md"
    local ref title
    {
        if [ "$LINK_MODE" = "exact-commit" ]; then
            echo "<!-- Lean prompt: core skill plus fetch-on-demand product references -->"
        else
            echo "<!-- Self-contained prompt: exact canonical-origin publication is not locally proven -->"
        fi
        echo "<!-- Source commit: $SOURCE_COMMIT -->"
        echo "<!-- Source state: $SOURCE_STATE -->"
        echo "<!-- Artifact link mode: $LINK_MODE -->"
        echo "<!-- Source fingerprint: sha256:$SOURCE_FINGERPRINT -->"
        if [ "$LINK_MODE" = "self-contained" ]; then
            echo "<!-- Artifact mode: self-contained; product guides use explicit internal anchors -->"
        fi
        echo ""
        render_source "$SKILL_DIR/SKILL.md" "$LINK_MODE"
        if [ "$LINK_MODE" = "exact-commit" ]; then
            echo ""
            echo "---"
            echo ""
            echo "## Reference patterns (fetch when needed)"
            echo ""
            echo "Fetch only the references relevant to the selected MagicBlock product or failure mode:"
            echo ""
            for ref in "${ALL_REFERENCES[@]}"; do
                title="$(extract_title "$REFERENCE_DIR/$ref")"
                if [ -z "$title" ]; then title="$ref"; fi
                echo "- [\`$ref\`]($REFERENCE_BLOB_URL/$ref) — $title"
            done
        else
            for ref in "${ALL_REFERENCES[@]}"; do
                echo ""
                echo "---"
                echo ""
                render_guide "$ref" "$LINK_MODE"
            done
        fi
    } > "$out"
    echo "Built: $out ($(wc -c < "$out" | tr -d ' ') bytes)"
}

build_cursor() {
    local out="$1"
    local label="$2"
    local content_mode="$3"
    shift 3
    local body_file="$DIST_DIR/.cursor-body.tmp"
    build_flattened "$body_file" "$label" "$content_mode" "$@" >/dev/null
    {
        cat <<'EOF'
---
description: Design, implement, and debug products with MagicBlock on Solana — ER/PER architecture, delegation and settlement, Pricing Oracle, Session Keys, Ephemeral Accounts, Magic Actions, Cranks, VRF, eSPL, private payments, and validation.
globs:
alwaysApply: false
---
EOF
        echo ""
        cat "$body_file"
    } > "$out"
    rm -f "$body_file"
    echo "Built: $out ($(wc -c < "$out" | tr -d ' ') bytes)"
}

build_zip() {
    local out="$DIST_DIR/$SKILL_NAME.zip"
    local zip_root
    if ! command -v zip >/dev/null 2>&1; then
        echo "Warning: 'zip' command not found, skipping $out"
        return 0
    fi
    rm -f "$out"
    zip_root="$(mktemp -d "$DIST_DIR/.zip-root.XXXXXX")"
    mkdir -p "$zip_root/skill"
    cp -R "$SKILL_DIR"/. "$zip_root/skill"/
    find "$zip_root" -type d -exec chmod 755 {} +
    find "$zip_root" -type f -exec chmod 644 {} +
    find "$zip_root" -exec env TZ=UTC touch -t 198001010000 {} +
    (
        cd "$zip_root"
        find skill -type f ! -name '.DS_Store' -print \
            | LC_ALL=C sort \
            | TZ=UTC zip -X -q "$out" -@
    )
    rm -rf "$zip_root"
    echo "Built: $out ($(wc -c < "$out" | tr -d ' ') bytes)"
}


validate_artifacts() {
    local artifact declared_mode target
    local artifacts=(
        "$DIST_DIR/AGENTS.md"
        "$DIST_DIR/AGENTS.full.md"
        "$DIST_DIR/system-prompt.md"
        "$DIST_DIR/$SKILL_NAME.cursor.mdc"
        "$DIST_DIR/$SKILL_NAME.full.cursor.mdc"
    )

    for artifact in "${artifacts[@]}"; do
        if grep -Eo '\]\([^)]*\.md(#[^)]*)?\)' "$artifact" \
            | grep -Evq '^\]\((https?://|mailto:)'; then
            echo "Error: unresolved relative Markdown link in $artifact" >&2
            exit 1
        fi
        if ! grep -Fq "<!-- Source commit: $SOURCE_COMMIT -->" "$artifact" || \
           ! grep -Fq "<!-- Source state: $SOURCE_STATE -->" "$artifact" || \
           ! grep -Fq "<!-- Source fingerprint: sha256:$SOURCE_FINGERPRINT -->" "$artifact"; then
            echo "Error: incomplete source provenance in $artifact" >&2
            exit 1
        fi

        declared_mode="$(sed -nE 's/^<!-- Artifact link mode: ([^ ]+) -->$/\1/p' "$artifact" | head -n 1)"
        if [ "$declared_mode" != "exact-commit" ] && [ "$declared_mode" != "self-contained" ]; then
            echo "Error: missing or invalid artifact link mode in $artifact" >&2
            exit 1
        fi
        if [ "$declared_mode" = "self-contained" ] && \
           grep -Eq "$REPO_URL/blob/[0-9a-f]{40}/skill/[^ )]+\.md" "$artifact"; then
            echo "Error: self-contained artifact contains a canonical-repo commit link: $artifact" >&2
            exit 1
        fi

        while IFS= read -r target; do
            if ! grep -Fq "<a id=\"$target\"></a>" "$artifact"; then
                echo "Error: unresolved explicit guide anchor #$target in $artifact" >&2
                exit 1
            fi
        done < <(grep -Eo '\]\(#guide-[a-z0-9-]+\)' "$artifact" \
            | sed -E 's/^\]\(#([^)]*)\)$/\1/' \
            | LC_ALL=C sort -u || true)
    done
}

if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
    echo "Error: skill/SKILL.md not found at $SKILL_DIR" >&2
    exit 1
fi

validate_sources

DEFAULT_REFERENCES=("${CORE_REFERENCES[@]}")
DEFAULT_LABEL="lean"
if [ "$LINK_MODE" = "self-contained" ]; then
    DEFAULT_REFERENCES=("${ALL_REFERENCES[@]}")
    DEFAULT_LABEL="lean (self-contained)"
fi

echo "Building lean and full dist/ artifacts from skill/..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

build_flattened "$DIST_DIR/AGENTS.md" "$DEFAULT_LABEL" "$LINK_MODE" "${DEFAULT_REFERENCES[@]}"
build_flattened "$DIST_DIR/AGENTS.full.md" "full" "self-contained" "${ALL_REFERENCES[@]}"
build_system_prompt
build_cursor "$DIST_DIR/$SKILL_NAME.cursor.mdc" "$DEFAULT_LABEL Cursor" "$LINK_MODE" "${DEFAULT_REFERENCES[@]}"
build_cursor "$DIST_DIR/$SKILL_NAME.full.cursor.mdc" "full Cursor" "self-contained" "${ALL_REFERENCES[@]}"
build_zip
validate_artifacts
# Publish the trust marker only after every generated artifact has passed validation.
# A rejected build therefore cannot look current to install.sh.
printf '%s\n' "$SOURCE_FINGERPRINT" > "$DIST_DIR/.source-fingerprint"

echo ""
echo "Done. Artifacts:"
ls -1 "$DIST_DIR"
