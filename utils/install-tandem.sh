#!/usr/bin/env bash
set -euo pipefail
source_dir="${TANDEM_SOURCE:-$HOME/GitHub/tandem}"
cargo install --locked --force --path "$source_dir"
