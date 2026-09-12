#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

NEW=$(awk 'END{print $2}' .git/logs/HEAD)
printf '%s %s\n' "$NEW" "refs/heads/feature/mature-agent" > .git/packed-refs
rm -f .git/refs/heads/feature/mature-agent
git pack-refs --all
git rev-parse --verify -q HEAD
