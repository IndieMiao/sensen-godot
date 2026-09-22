#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/../.."
exec node tools/dev/run_journey.mjs --journey-mining
