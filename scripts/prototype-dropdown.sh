#!/bin/sh
# PROTOTYPE, throwaway: installs this branch like install.sh does, then
# relaunches Pacemark with the dropdown prototype on. A normal launch, such as
# the login item, shows the normal dropdown again.
set -eu

cd "$(dirname "$0")/.."

scripts/install.sh
pkill -x Pacemark || true
while pgrep -x Pacemark >/dev/null; do
    sleep 0.1
done
open /Applications/Pacemark.app --args -PrototypeDropdown YES
echo "Pacemark runs with the dropdown prototype: switch layouts with the pink bar or ← →"
