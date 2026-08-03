#!/bin/bash
# Merge upstream/hermes-agent main into fork, handling Dockerfile conflicts
# Usage: merge-upstream.sh

set -euo pipefail

# Add upstream remote and fetch
git remote add upstream https://github.com/NousResearch/hermes-agent.git
git fetch upstream main

BEHIND=$(git rev-list --count HEAD..upstream/main 2>/dev/null || echo "0")
if [ "$BEHIND" = "0" ]; then
  echo "Already up to date with upstream"
  exit 0
fi

echo "Upstream has $BEHIND new commits. Merging..."

# Try fast-forward first
if git merge upstream/main --no-edit --ff-only 2>/dev/null; then
  echo "✅ Fast-forward merge succeeded"
  exit 0
fi

# Non-fast-forward; do controlled merge
echo "⚠️  Non-fast-forward; attempting structured merge..."
git merge upstream/main --no-commit --no-ff 2>/dev/null || true

# Check for conflicted files
CONFLICTED=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
if [ -z "$CONFLICTED" ]; then
  # No conflicts, just commit
  git commit -m "chore: sync upstream $(date +%Y-%m-%d)" --no-edit
  echo "✅ Merge committed (no conflicts)"
  exit 0
fi

echo "Conflicts found in:" $CONFLICTED

# Dockerfile: take upstream + re-apply our additions
if echo "$CONFLICTED" | grep -q "^Dockerfile$"; then
  echo "Resolving Dockerfile..."
  # Accept upstream version as base
  git checkout --theirs Dockerfile

  # Re-apply: add gh to apt install line
  sed -i 's/xz-utils &&/xz-utils gh \&\&/' Dockerfile

  # Re-apply: add gws npm install (only if not already present)
  if ! grep -q "@googleworkspace/cli" Dockerfile; then
    sed -i '/^RUN npm cache clean --force$/a\
\
# Install gws (Google Workspace CLI) globally\
RUN npm install -g @googleworkspace/cli --no-audit --fetch-retries=5 \&\& \\\n    npm cache clean --force' Dockerfile
  fi

  git add Dockerfile
  echo "   ✅ Dockerfile resolved"
fi

# All other files: accept upstream's version
for f in $(echo "$CONFLICTED" | grep -v "^Dockerfile$"); do
  echo "Resolving $f: accepting upstream version"
  git checkout --theirs "$f"
  git add "$f"
done

git commit -m "chore: sync upstream $(date +%Y-%m-%d)" --no-edit
echo "✅ Merge committed with conflict resolutions"