#!/usr/bin/env bash
# Loaded by picker.sh after common.sh. Configuration is data, never shell code.
# SEARCH_ROOTS and SEARCH_DEPTHS are consumed by picker.sh.
# shellcheck disable=SC2034
load_search_config() {
	local config_file="$HOME/.config/herdr-sessionizer/config.toml" config_json
	SEARCH_ROOTS=() SEARCH_DEPTHS=()
	if ! config_json=$(
		uv run --no-project --no-config --isolated --python '>=3.11' python - "$config_file" <<'PY'
import json
import sys
import tomllib
from pathlib import Path


def read_roots(config_file: Path) -> list[dict[str, str | int]]:
    if not config_file.exists():
        return []
    data = tomllib.loads(config_file.read_text(encoding="utf-8"))
    roots = data.get("search_roots", [])
    if not isinstance(roots, list):
        raise ValueError("search_roots must be an array of tables")
    result: list[dict[str, str | int]] = []
    for index, root in enumerate(roots, start=1):
        label = f"search_roots[{index}]"
        if not isinstance(root, dict):
            raise ValueError(f"{label} must be a table with path and depth")
        path = root.get("path")
        depth = root.get("depth")
        if not isinstance(path, str) or path == "" or "\0" in path:
            raise ValueError(f"{label}.path must be a nonempty path without NUL characters")
        if path.startswith("~/"):
            path = str(Path.home() / path[2:])
        if not Path(path).is_absolute():
            raise ValueError(f"{label}.path must be absolute or start with ~/")
        if depth != "recursive" and not (type(depth) is int and depth >= 0):
            raise ValueError(f"{label}.depth must be a nonnegative integer or \"recursive\"")
        result.append({"path": path, "depth": depth})
    return result


config_file = Path(sys.argv[1])
try:
    print(json.dumps(read_roots(config_file)))
except (OSError, ValueError) as error:
    print(f"herdr picker: {config_file}: {error}", file=sys.stderr)
    sys.exit(1)
PY
	); then
		return 1
	fi
	# NUL delimiters preserve whitespace and shell metacharacters in paths.
	mapfile -d '' -t SEARCH_ROOTS < <(jq -j '.[] | .path, "\u0000"' <<<"$config_json")
	mapfile -t SEARCH_DEPTHS < <(jq -r '.[].depth' <<<"$config_json")
}
load_search_config
