#!/usr/bin/env bash
# git pull i alle delrepoene.
set -u
cd "$(dirname "$0")/.." || exit 1

for d in aduck aduck.heroku aduck.sf finnarild-django sfdx; do
    if [ -d "$d/.git" ]; then
        echo "=== $d ==="
        git -C "$d" pull --ff-only
    else
        echo "=== $d: mangler (.git ikke funnet) ==="
    fi
done
