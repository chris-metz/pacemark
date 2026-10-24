#!/bin/sh
# Prints the release notes for the merges into the current branch since TAG:
# one bullet per first-parent merge commit, by its title, followed by the
# requirements from the README. Without TAG, use "First release." instead.
# Runs in the current directory's repo.
# Usage: scripts/release-notes.sh [TAG]
set -eu

TAG=${1:-}

requirements() {
    cat <<'EOF'
Requirements:

- macOS 27
- For Claude monitoring: Claude Code 2.1.283 or later, installed and logged in
- For Codex monitoring: Codex CLI, installed and signed in with ChatGPT
- For Kimi monitoring: Kimi Code CLI, installed and logged in
EOF
}

if [ -z "$TAG" ]; then
    printf 'First release.\n\n'
    requirements
    exit
fi

# Listed first, so an unknown TAG stops the script.
MERGES="$(git rev-list --first-parent --merges --reverse "$TAG..HEAD")"
[ -n "$MERGES" ] || exit 0
for COMMIT in $MERGES; do
    TITLE="$(git log -1 --format=%s "$COMMIT")"
    case $TITLE in
        # GitHub's merge button puts the PR title in the body's first line.
        "Merge pull request #"*) TITLE="$(git log -1 --format=%b "$COMMIT" | awk 'NF { print; exit }')" ;;
        *) TITLE="$(printf '%s\n' "$TITLE" | sed -E 's/^Merge (#[0-9]+: )?//')" ;;
    esac
    printf '%s\n' "$TITLE" | awk '{ print "- " toupper(substr($0, 1, 1)) substr($0, 2) }'
done
printf '\n'
requirements
