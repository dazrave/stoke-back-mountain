#!/usr/bin/env bash
#
# Turn an approved draft into a GitHub issue. This is the triage gate: a human
# runs it on the drafts they've decided are worth building.
#
#   web/promote.sh submissions/pending/20260724-smoke-screen.md
#
# The draft is a markdown file with YAML front matter: title, labels, from.
set -euo pipefail

REPO="${REPO:-dazrave/stoke-back-mountain}"
DRAFT="${1:?usage: promote.sh <draft.md>}"

[[ -f "$DRAFT" ]] || { echo "no such draft: $DRAFT" >&2; exit 1; }

# --- pull the front matter out ---
front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$DRAFT")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$DRAFT")"

title="$(printf '%s\n' "$front" | sed -n 's/^title:[[:space:]]*//p' | sed 's/^"//; s/"$//')"
labels="$(printf '%s\n' "$front" | sed -n 's/^labels:[[:space:]]*\[\(.*\)\]/\1/p' | tr -d ' ')"

[[ -n "$title" ]] || { echo "draft has no title in front matter" >&2; exit 1; }

label_args=()
IFS=',' read -ra parts <<< "$labels"
for l in "${parts[@]}"; do [[ -n "$l" ]] && label_args+=(--label "$l"); done

echo "==> creating issue: $title"
url="$(gh issue create --repo "$REPO" --title "$title" --body "$body" "${label_args[@]}")"
echo "    $url"

# --- archive the draft so it isn't promoted twice ---
done_dir="$(dirname "$DRAFT")/../promoted"
mkdir -p "$done_dir"
mv "$DRAFT" "$done_dir/"
echo "==> archived draft to promoted/"
