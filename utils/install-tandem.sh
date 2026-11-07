#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${TANDEM_SOURCE:-}" ]]; then
  cargo install --locked --force --path "$TANDEM_SOURCE"
else
  tandem_ref="${TANDEM_REF:-f1b43baec4a4d13f8e76eb85eba16a2f5f0d575b}"
  cargo install --locked --force --git https://github.com/Chr1sC0de/tandem.git --rev "$tandem_ref"
fi
