"""Check the local Linux prerequisites and Codex's actual read-only sandbox.

Requires Python 3.10+, Codex CLI (tested with 0.153.4), and system Bubblewrap.
Uses temporary canary files and an isolated child Codex configuration. No model
requests, credentials, sudo commands, or host security configuration changes.
"""
import argparse
import json
import os
import pathlib
import platform
import shutil
import subprocess
import tempfile


def run(argv, **kwargs):
    return subprocess.run(argv, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=25, **kwargs)


def check():
    report = {"platform": platform.platform(), "result": "failed"}
    try:
        if platform.system() != "Linux":
            raise RuntimeError("run this check on the Pop!_OS/Linux machine")
        release = platform.freedesktop_os_release()
        report["os_release"] = {key: release.get(key) for key in
                                ("ID", "PRETTY_NAME", "VERSION_ID", "UBUNTU_CODENAME")}
        report["kernel_settings"] = {}
        for key in ("kernel/unprivileged_userns_clone", "user/max_user_namespaces",
                    "kernel/apparmor_restrict_unprivileged_userns"):
            try:
                report["kernel_settings"][key] = pathlib.Path("/proc/sys", key).read_text().strip()
            except OSError:
                report["kernel_settings"][key] = "unavailable"
        codex = shutil.which("codex")
        bwrap = shutil.which("bwrap")
        report["bubblewrap_path"] = bwrap
        if not codex or not bwrap:
            raise RuntimeError("codex and the distribution's bubblewrap package must be on PATH")
        report["bubblewrap_version"] = run([bwrap, "--version"]).stdout.strip()
        # Codex does not create helper aliases when CODEX_HOME is under /tmp.
        cache = pathlib.Path(os.environ.get("XDG_CACHE_HOME", pathlib.Path.home() / ".cache")) / "tandem-check"
        cache.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="probe-", dir=cache) as temporary:
            base = pathlib.Path(temporary).resolve()
            project = base / "project"
            project.mkdir()
            canary = "tandem-linux-probe\n"
            (project / "readable.txt").write_text(canary)
            env = os.environ.copy()
            child_home = base / "codex"
            child_home.mkdir()
            env["CODEX_HOME"] = str(child_home)
            (child_home / "config.toml").write_text('sandbox_mode = "read-only"\napproval_policy = "never"\n')
            report["codex_version"] = run([codex, "--version"], env=env).stdout.strip()
            probe = run([codex, "-c", 'sandbox_mode="read-only"', "-c", 'approval_policy="never"',
                         "sandbox", "--", "/bin/sh", "-c",
                         "cat readable.txt; printf 'write must fail\\n' > forbidden.txt"],
                        cwd=project, env=env)
            report["probe_exit_code"] = probe.returncode
            report["probe_output"] = probe.stdout[-4000:]
            report["read_succeeded"] = canary in probe.stdout
            report["write_blocked"] = (
                probe.returncode != 0 and not (project / "forbidden.txt").exists()
                and any(message in probe.stdout.lower() for message in
                        ("permission denied", "operation not permitted", "read-only file system")))
            if not report["read_succeeded"] or not report["write_blocked"]:
                raise RuntimeError("require a successful native read and a denied write; sandbox startup failure is not a pass")
            report["result"] = "passed"
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, help="also save the JSON report to this path")
    args = parser.parse_args()
    report = check()
    encoded = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded)
    print(encoded, end="")
    raise SystemExit(0 if report["result"] == "passed" else 1)
