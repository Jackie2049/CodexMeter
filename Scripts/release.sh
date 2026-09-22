#!/bin/bash
# Local release helper (AGENTS.md §8 runbook).
#
# Usage: ./Scripts/release.sh <version> [--local]
#   <version>  e.g. 0.1.0 — "v" prefix is added automatically
#   --local    build on this machine and create the GitHub Release here
#              (default: tag is pushed and CI builds & publishes)
#
# The canonical flow: tag push triggers .github/workflows/release.yml,
# which runs the tests, builds the app, and attaches the zip to the
# GitHub Release. This script is the one-command entry to that flow.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version> [--local] — e.g. release.sh 0.1.0}"
VERSION="${VERSION#v}"
LOCAL="${2:-}"

# Precondition checks (AGENTS.md §8: releases build from clean, converged commits)
[ -z "$(git status --porcelain)" ] || { echo "✗ working tree not clean — commit or stash first"; exit 1; }
[ "$(git branch --show-current)" = "main" ] || { echo "✗ release from main only"; exit 1; }
git fetch origin main --quiet
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "✗ main not pushed — push first"; exit 1; }

TAG="v$VERSION"
if git rev-parse -q --verify "$TAG" >/dev/null; then echo "✗ tag $TAG already exists"; exit 1; fi

echo "==> running tests"
bash Scripts/test.sh

git tag "$TAG"
echo "==> tagged $TAG"

if [ "$LOCAL" = "--local" ]; then
    bash Scripts/make_app.sh build
    (cd build && zip -qry "CodexMeter-$TAG.zip" "CodexMeter.app")
    gh release create "$TAG" "build/CodexMeter-$TAG.zip" \
        --title "CodexMeter $TAG" \
        --generate-notes \
        --notes "See AGENTS.md §8. Install: unzip, move to /Applications, run \`xattr -cr /Applications/CodexMeter.app\` (unsigned build). Requires macOS 14+."
    echo "==> release $TAG published (local build)"
else
    git push origin main
    git push origin "$TAG"
    echo "==> tag pushed. CI (.github/workflows/release.yml) builds and publishes the release."
    echo "    watch: gh run watch --exit-status \$(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
fi
