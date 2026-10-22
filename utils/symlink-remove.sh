#!/usr/bin/env bash

. "utils/common.sh"
resolve_target "${1:-}" || exit 1
if link_matches; then
    rm -- "$LINK_DESTINATION"
elif [[ -e $LINK_DESTINATION || -L $LINK_DESTINATION ]]; then
    printf 'Keeping unrelated target: %s\n' "$LINK_DESTINATION" >&2
fi
