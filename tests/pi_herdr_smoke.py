"""Opt-in real Herdr/Pi launch regression; creates and closes one owned pane.

No model request is made. Run inside Herdr: python3 -B tests/pi_herdr_smoke.py
"""

import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path


def main():
    assert os.environ.get("HERDR_ENV") == "1", "Run inside Herdr"
    repo = Path(__file__).resolve().parents[1]
    wrappers = repo / "config/nvim/libexec/opencode-herdr"
    # Resolve outside the managed wrappers, including symlinked config paths.
    native_path = os.pathsep.join(
        p
        for p in os.environ["PATH"].split(os.pathsep)
        if Path(p).resolve() != wrappers.resolve()
    )
    pi = shutil.which("pi", path=native_path)
    assert pi, "Pi is not installed"

    def herdr(*args, check=True):
        return subprocess.run(
            ["herdr", *args], text=True, capture_output=True, check=check, timeout=35
        )

    with tempfile.TemporaryDirectory(
        prefix="pi-herdr-smoke-", dir="/tmp/opencode"
    ) as tmp:
        base = Path(tmp)
        # An unreachable fixture endpoint ensures this test cannot use paid
        # credentials or submit a real request even if startup behavior changes.
        (base / "models.json").write_text(
            json.dumps(
                {
                    "providers": {
                        "fixture": {
                            "api": "openai-completions",
                            "baseUrl": "http://127.0.0.1:1/v1",
                            "apiKey": "unused",
                            "models": [
                                {
                                    "id": "test",
                                    "contextWindow": 128000,
                                    "maxTokens": 4096,
                                }
                            ],
                        }
                    }
                }
            )
        )
        (base / "settings.json").write_text(
            json.dumps({"defaultProvider": "fixture", "defaultModel": "test"})
        )
        env = {
            "PATH": str(wrappers) + os.pathsep + native_path,
            "PI_REAL_BIN": pi,
            "OPENCODE_REAL_BIN": shutil.which("opencode", path=native_path)
            or "opencode",
            "OPENCODE_HERDR_BIN": shutil.which("herdr"),
            "PI_CODING_AGENT_DIR": tmp,
            "PI_OFFLINE": "1",
            "PI_TELEMETRY": "0",
        }
        args = [
            "pane",
            "split",
            "--current",
            "--direction",
            "down",
            "--cwd",
            str(repo),
            "--no-focus",
        ]
        for key, value in env.items():
            args.extend(["--env", key + "=" + value])
        pane = json.loads(herdr(*args).stdout)["result"]["pane"]["pane_id"]
        try:
            for _ in range(100):
                info = json.loads(herdr("pane", "process-info", "--pane", pane).stdout)[
                    "result"
                ]["process_info"]
                if info.get("shell_pid") == info.get("foreground_process_group_id"):
                    break
                time.sleep(0.1)
            else:
                raise AssertionError("Owned pane did not reach its shell prompt")
            result = herdr(
                "agent",
                "start",
                "pi-smoke-" + str(os.getpid()),
                "--kind",
                "pi",
                "--pane",
                pane,
                "--timeout",
                "15000",
                "--",
                "--offline",
                "--model",
                "fixture/test",
                "--extension",
                str(repo / "config/nvim/pi-extension/index.ts"),
                check=False,
            )
            assert result.returncode == 0, result.stderr or result.stdout
            agent = json.loads(herdr("agent", "get", pane).stdout)["result"]["agent"]
            assert agent["agent"] == "pi", agent
            info = json.loads(herdr("pane", "process-info", "--pane", pane).stdout)[
                "result"
            ]["process_info"]
            parents = [p for p in info["foreground_processes"] if p["name"] == "bash"]
            assert any(
                Path(p["argv"][1]).name == "lifecycle"
                for p in parents
                if len(p["argv"]) > 1
            ), info
            assert not any(
                Path(p["argv"][1]).name == "opencode"
                for p in parents
                if len(p["argv"]) > 1
            ), info
            print(
                "PASS: real managed Pi launch is detected as Pi with backend-neutral lifecycle cleanup",
                flush=True,
            )
        finally:
            herdr("pane", "close", pane, check=False)


if __name__ == "__main__":
    main()
