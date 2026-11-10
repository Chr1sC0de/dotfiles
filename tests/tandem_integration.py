"""Real OpenCode V2 -> shell -> Tandem CLI -> Neovim/Conform integration.

Only model responses are deterministic. No credentials or live model required.
Herdr launch contracts are unit-tested separately from the interactive smoke test.
"""

import http.server
import json
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, str(pathlib.Path(__file__).parent / "support"))
from opencode_fixture import config, handler_for


def tandem_result(value):
    if isinstance(value, str):
        try:
            return tandem_result(json.loads(value))
        except ValueError:
            start = value.find("{")
            if start >= 0:
                try:
                    return json.JSONDecoder().raw_decode(value[start:])[0]
                except ValueError:
                    pass
            return None
    if isinstance(value, dict):
        if isinstance(value.get("ok"), bool):
            return value
        value = list(value.values())
    if isinstance(value, list):
        for item in value:
            found = tandem_result(item)
            if found is not None:
                return found
    return None


class Fixture:
    def __init__(self, backend="opencode"):
        self.shell = "bash" if backend == "pi" else "shell"
        self.error = None
        self.read = threading.Event()
        self.release = threading.Event()
        self.calls = []

    def answer(self, body):
        try:
            messages = body["messages"]
            system = json.dumps([m for m in messages if m["role"] == "system"])
            user = json.dumps([m for m in messages if m["role"] == "user"])
            tools = {t["function"]["name"] for t in body.get("tools", [])}
            # Automatic title generation is a separate, tool-free request.
            if "Generate only the requested text" in system or not tools:
                return {"content": "test: migrate editor integration"}
            assert "HOST_GUIDANCE_MARKER" in system, "host instructions lost"
            assert self.shell in tools and {"patch", "write", "edit"} & tools, tools
            assert "Tandem editor integration" in system, "Tandem instructions lost"
            assert not any(name.startswith("tandem_") for name in tools), tools
            readonly = "Analysis-only session" in system
            if "INTERACTIVE_TEST" in user:
                return {"content": "INTERACTIVE_DONE"}
            self.calls.append({"readonly": readonly, "tools": sorted(tools)})
            if readonly:
                outputs = {
                    m["tool_call_id"]: m["content"]
                    for m in messages
                    if m["role"] == "tool"
                }
                if "query-read" not in outputs:
                    return {
                        "tool_calls": [
                            {
                                "id": "query-read",
                                "type": "function",
                                "function": {
                                    "name": self.shell,
                                    "arguments": json.dumps(
                                        {"command": '"$TANDEM_BIN" read a.py'}
                                    ),
                                },
                            }
                        ]
                    }
                assert tandem_result(outputs["query-read"])["ok"], outputs
                return {"content": "QUERY_DONE: use the shared helper"}
            if "CONTINUE_TEST" in user:
                assert "FOLLOWUP_DONE" in json.dumps(messages), "resumed history lost"
                return {"content": "CONTINUE_DONE"}
            followup = "FOLLOWUP_TEST" in user
            if followup:
                assert "QUERY_DONE" in user, "query-to-edit history lost"
            outputs = {
                m["tool_call_id"]: m["content"] for m in messages if m["role"] == "tool"
            }
            prefix = "followup" if followup else "initial"
            read_id, write_id = prefix + "-read", prefix + "-write"

            def call(id_, command):
                return {
                    "tool_calls": [
                        {
                            "id": id_,
                            "type": "function",
                            "function": {
                                "name": self.shell,
                                "arguments": json.dumps({"command": command}),
                            },
                        }
                    ]
                }

            if read_id not in outputs:
                return call(read_id, '"$TANDEM_BIN" read a.py')
            current = tandem_result(outputs[read_id])
            assert current and current["ok"], outputs[read_id]
            self.read.set()
            if write_id not in outputs:
                if not followup:
                    assert self.release.wait(30), "human edit was not delivered"
                content = "value=3\n" if followup else "value=2\n"
                return call(
                    write_id,
                    "printf %s "
                    + shlex.quote(content)
                    + ' | "$TANDEM_BIN" write a.py --expect '
                    + shlex.quote(current["revision"])
                    + " --content-file -",
                )
            saved = tandem_result(outputs[write_id])
            assert saved is not None, outputs[write_id]
            assert saved["ok"] and saved["revision"], saved
            return {"content": "FOLLOWUP_DONE" if followup else "EDIT_DONE"}
        except Exception as error:
            self.error = repr(error)
            return {"content": "FIXTURE_FAILED: " + repr(error)}


def main():
    backend = os.environ.get("AGENT_TEST_BACKEND", "opencode")
    assert backend in ("opencode", "pi")
    repo = pathlib.Path(__file__).resolve().parents[1]
    conform = pathlib.Path(
        os.environ.get(
            "TANDEM_CONFORM",
            pathlib.Path.home() / ".local/share/nvim/lazy/conform.nvim",
        )
    )
    binary = os.environ.get("TANDEM_BIN") or shutil.which("tandem")
    evidence = pathlib.Path(
        os.environ.get(
            "TANDEM_EVIDENCE_DIR",
            repo / ("artifacts/tandem-pi" if backend == "pi" else "artifacts/tandem"),
        )
    )
    evidence.mkdir(parents=True, exist_ok=True)
    nvim = shutil.which("nvim")
    assert nvim and shutil.which(backend) and shutil.which("ruff")
    assert binary and pathlib.Path(binary).is_file(), (
        "Run bash utils/install-tandem.sh or set TANDEM_BIN"
    )
    report = {"result": "FAIL", "checks": [], "versions": {}}

    def passed(name):
        report["checks"].append(name)
        print("PASS: " + name, flush=True)

    with tempfile.TemporaryDirectory(
        prefix="td-open-", dir=os.environ.get("TANDEM_TEST_TMPDIR", "/tmp/opencode")
    ) as tmp:
        base = pathlib.Path(tmp)
        root = base / "project"
        root.mkdir()
        subprocess.run(["git", "init", "--quiet", str(root)], check=True)
        source = root / "a.py"
        source.write_text("value=0\n")
        (root / "AGENTS.md").write_text(
            "HOST_GUIDANCE_MARKER: preserve host instructions.\n"
        )
        env = {
            k: v
            for k, v in os.environ.items()
            if not k.startswith(("OPENCODE_", "HERDR_"))
        }
        wrappers = (repo / "config/nvim/libexec/opencode-herdr").resolve()
        env["PATH"] = os.pathsep.join(
            p
            for p in env["PATH"].split(os.pathsep)
            if pathlib.Path(p).resolve() != wrappers
        )
        env.pop("PI_REAL_BIN", None)
        for key in (
            "HOME",
            "XDG_DATA_HOME",
            "XDG_STATE_HOME",
            "XDG_CACHE_HOME",
            "XDG_CONFIG_HOME",
        ):
            env[key] = str(base / key)
            pathlib.Path(env[key]).mkdir()
        env["PWD"] = str(root)
        env["TERM"] = "xterm-256color"
        fixture = Fixture(backend)
        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), handler_for(fixture.answer)
        )
        threading.Thread(target=server.serve_forever, daemon=True).start()
        env["OPENCODE_CONFIG_CONTENT"] = json.dumps(config(server.server_port))
        if backend == "pi":
            agent_dir = base / "pi-agent"
            agent_dir.mkdir()
            env["PI_CODING_AGENT_DIR"] = str(agent_dir)
            env["PI_OFFLINE"] = "1"
            env["PI_TELEMETRY"] = "0"
            (agent_dir / "models.json").write_text(
                json.dumps(
                    {
                        "providers": {
                            "fixture": {
                                "baseUrl": f"http://127.0.0.1:{server.server_port}/v1",
                                "api": "openai-completions",
                                "apiKey": "fixture",
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
            (agent_dir / "settings.json").write_text(
                json.dumps({"defaultProvider": "fixture", "defaultModel": "test"})
            )
        opts = {
            "command": binary,
            "root": str(root),
            "state_home": env["XDG_STATE_HOME"],
        }
        init = base / "init.lua"
        init.write_text(
            "\n".join(
                [
                    f"vim.opt.runtimepath:append({json.dumps(str(p))})"
                    for p in [repo / "config/nvim", conform]
                ]
                + [
                    "vim.opt.swapfile = false",
                    'vim.cmd("filetype plugin indent on")',
                    f"dofile({json.dumps(str(repo / 'config/nvim/lua/plugins/conform.lua'))}).config()",
                    f"vim.cmd.edit({json.dumps(str(source))})",
                    f"local opts = vim.json.decode({json.dumps(json.dumps(opts))})",
                    'require("agents.tandem").setup(opts)',
                    'require("config.agents").setup()',
                    f'require("agents.selection").set({json.dumps(backend)})',
                ]
            )
        )
        socket = str(base / "nvim.sock")
        log = (evidence / "process.log").open("w")
        daemon_args = [
            binary,
            "--root",
            str(root),
            "--state-home",
            env["XDG_STATE_HOME"],
            "serve",
        ]
        daemon = subprocess.Popen(daemon_args, env=env, stdout=log, stderr=log)
        deadline = time.monotonic() + 10
        while not list(
            pathlib.Path(env["XDG_STATE_HOME"]).glob("tandem/*/daemon.sock")
        ):
            assert daemon.poll() is None and time.monotonic() < deadline, (
                "daemon failed to start"
            )
            time.sleep(0.02)
        editor = subprocess.Popen(
            [nvim, "--headless", "--listen", socket, "-u", str(init)],
            cwd=root,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=log,
        )

        def expr(expression):
            output = subprocess.check_output(
                [
                    nvim,
                    "--server",
                    socket,
                    "--remote-expr",
                    "luaeval("
                    + json.dumps("vim.json.encode(" + expression + ")")
                    + ")",
                ],
                cwd=root,
                env=env,
                text=True,
                stderr=log,
                timeout=5,
            )
            return json.loads(output)

        def lua(code):
            return expr("(function() " + code + "; return true end)()")

        def cli(*args, content=None, ok=True):
            result = subprocess.run(
                [
                    binary,
                    "--root",
                    str(root),
                    "--state-home",
                    env["XDG_STATE_HOME"],
                    *args,
                ],
                input=content,
                capture_output=True,
                text=True,
                env=env,
                timeout=10,
            )
            data = json.loads(result.stdout)
            assert data["ok"] == ok and (result.returncode == 0) == ok, (
                data,
                result.stderr,
            )
            return data

        def until(predicate, label, timeout=60):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if fixture.error:
                    raise AssertionError(fixture.error)
                assert editor.poll() is None, "Neovim exited; see process.log"
                try:
                    if predicate():
                        return
                except (subprocess.SubprocessError, ValueError):
                    pass
                time.sleep(0.05)
            raise AssertionError("Timed out: " + label)

        def launch(action, instruction):
            lua(
                f'require("agents.ephemeral.jobs").run({json.dumps(action)}, require("agents.context.targets").build_file(), {json.dumps(instruction)})'
            )
            return expr('require("agents.state").next_ephemeral_job_id - 1')

        def job(id_):
            return expr(f'require("agents.state").ephemeral_jobs[{id_}]')

        def finish(id_, expected):
            until(lambda: job(id_).get("finished_at"), expected)
            record = job(id_)
            assert record["status"] == "success", record
            assert expected in "\n".join(record["answer_lines"]), record
            assert record["thread_id"] and record["backend"] == backend, record
            return record

        try:
            for name, command in {
                backend: [backend, "--version"],
                "tandem": [binary, "--version"],
                "neovim": [nvim, "--version"],
                "ruff": ["ruff", "--version"],
            }.items():
                report["versions"][name] = subprocess.check_output(
                    command, text=True, env=env
                ).splitlines()[0]
            until(
                lambda: expr('require("agents.tandem").status().connected'),
                "editor connection",
            )
            passed("real Tandem daemon and editor connected")
            first = launch("edit", "EDIT_TEST")
            until(fixture.read.is_set, "first CLI read")
            # Compatible human insertion must survive the agent's replacement.
            lua('vim.api.nvim_buf_set_lines(0, 0, 0, false, {"# human draft"})')
            fixture.release.set()
            finish(first, "EDIT_DONE")
            assert source.read_text() == "value=0\n"
            assert expr("vim.api.nvim_buf_get_lines(0, 0, -1, false)") == [
                "# human draft",
                "value=2",
            ]
            passed("CLI edit merges a live human draft without saving")
            lua('vim.cmd("write")')
            assert source.read_text() == "# human draft\nvalue = 2\n"
            passed("explicit save runs Conform")
            query = launch("query", "QUERY_TEST")
            finish(query, "QUERY_DONE")
            assert source.read_text() == "# human draft\nvalue = 2\n"
            passed(
                "query receives analysis-only instructions with native tools available"
            )
            lua(
                f'assert(require("agents.ephemeral.jobs").follow_up(require("agents.state").ephemeral_jobs[{query}], "FOLLOWUP_TEST", {{action="edit"}}))'
            )
            follow = expr('require("agents.state").next_ephemeral_job_id - 1')
            promoted = finish(follow, "FOLLOWUP_DONE")
            assert source.read_text() == "value = 3\n"
            assert expr("vim.api.nvim_buf_get_lines(0, 0, -1, false)") == ["value = 3"]
            assert expr("vim.bo.modified") is False
            passed("clean agent edit automatically saves through Conform")
            passed("query-to-edit promotion preserves discussion and edits live buffer")
            lua(
                f'assert(require("agents.ephemeral.jobs").follow_up(require("agents.state").ephemeral_jobs[{follow}], "CONTINUE_TEST"))'
            )
            resumed = finish(
                expr('require("agents.state").next_ephemeral_job_id - 1'),
                "CONTINUE_DONE",
            )
            assert promoted["thread_id"] == resumed["thread_id"]
            passed(f"follow-up resumes the same native {backend} session")
            lua(
                'require("agents.backend").generate("Generate a commit subject", vim.fn.getcwd(), function(code, text) vim.g.generated = {code=code,text=text} end)'
            )
            until(lambda: expr("vim.g.generated") is not None, "text generation")
            assert expr("vim.g.generated") == {
                "code": 0,
                "text": "test: migrate editor integration",
            }
            passed("tool-free text generation returns clean model output")
            editor_id = expr('require("agents.tandem").status().editor')
            snapshot = cli("--editor", editor_id, "read", "a.py")
            lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, {"value=human"})')
            conflict = cli(
                "--editor",
                editor_id,
                "write",
                "a.py",
                "--expect",
                snapshot["revision"],
                "--content-file",
                "-",
                content="value=agent\n",
                ok=False,
            )
            assert conflict["error"]["code"] == "merge_conflict", conflict
            assert expr("vim.api.nvim_buf_get_lines(0, 0, -1, false)") == [
                "value=human"
            ]
            passed("overlapping edits conflict without modifying the human draft")
            fresh = cli("--editor", editor_id, "read", "a.py")
            applied = cli(
                "--editor",
                editor_id,
                "write",
                "a.py",
                "--expect",
                fresh["revision"],
                "--content-file",
                "-",
                content="value=resolved\n",
            )
            outcome = cli("--editor", editor_id, "outcome", applied["attempt"])
            assert outcome["outcome"]["state"] == "applied", outcome
            passed("write attempt can be inspected through the CLI outcome command")
            # Restart our owned daemon: the startup timer must recover the same
            # editor, while the old daemon's snapshots must no longer work.
            daemon.terminate()
            daemon.wait(timeout=5)
            daemon = subprocess.Popen(daemon_args, env=env, stdout=log, stderr=log)
            until(
                lambda: any(
                    item["editor"] == editor_id
                    for item in cli("editor", "list")["editors"]
                ),
                "registration recovery",
            )
            expired = cli(
                "--editor",
                editor_id,
                "write",
                "a.py",
                "--expect",
                fresh["revision"],
                "--content-file",
                "-",
                content="value=obsolete\n",
                ok=False,
            )
            assert expired["error"]["code"] == "snapshot_expired", expired
            passed(
                "daemon restart recovers the same editor and expired snapshots are rejected"
            )
            second_socket = str(base / "second.sock")
            second = subprocess.Popen(
                [
                    nvim,
                    "--headless",
                    "--listen",
                    second_socket,
                    "-u",
                    "NONE",
                    "-i",
                    "NONE",
                    str(source),
                ],
                cwd=root,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=log,
            )
            try:
                until(
                    lambda: pathlib.Path(second_socket).exists(), "second editor socket"
                )
                other = cli("editor", "register", "--socket", second_socket)["editor"]
                assert other != editor_id
                assert (
                    cli("--editor", editor_id, "read", "a.py")["content"]
                    == "value=resolved\n"
                )
                assert (
                    cli("--editor", other, "read", "a.py")["content"]
                    == source.read_text()
                )
                passed("explicit editor IDs isolate two editors in one workspace")
            finally:
                second.terminate()
                second.wait(timeout=5)
                if "other" in locals():
                    cli("editor", "unregister", other)
            if backend == "pi":
                source_buf = expr("vim.api.nvim_get_current_buf()")
                lua(
                    'assert(require("agents.chat").new()); vim.g.pi_chat_buf = vim.api.nvim_get_current_buf()'
                )
                chat_buf = expr("vim.g.pi_chat_buf")
                until(
                    lambda: (
                        expr(f'require("agents.chat").session({chat_buf}).hook_seen')
                        is True
                    ),
                    "Pi interactive readiness hook",
                )
                lua(
                    'assert(require("agents.chat").paste("INTERACTIVE_TEST")); '
                    'vim.api.nvim_chan_send(require("agents.chat").active_session().job_id, "\\r")'
                )
                until(
                    lambda: (
                        expr(f'require("agents.chat").session({chat_buf}).task_status')
                        == "DONE"
                    ),
                    "Pi interactive settled hook",
                )
                assert expr(
                    f'require("agents.chat").session({chat_buf}).native_session_id'
                )
                lua('require("agents.selection").set("opencode")')
                assert expr('require("agents.chat").active_bufnr()') is None
                lua(
                    f'assert(require("agents.chat").switch_backend("pi")); assert(vim.api.nvim_get_current_buf() == {chat_buf})'
                )
                assert expr(f'require("agents.chat").is_running({chat_buf})') is True
                passed(
                    "real Pi terminal readiness, prompt paste, final-idle status and backend restoration"
                )
                lua(
                    f'assert(require("agents.chat").delete_buffer({chat_buf})); vim.api.nvim_set_current_buf({source_buf})'
                )
            report["result"] = "PASS"
        except Exception as error:
            report["error"] = repr(error)
            raise
        finally:
            for path in pathlib.Path(env["XDG_DATA_HOME"]).rglob("*.log"):
                shutil.copyfile(path, evidence / ("opencode-" + path.name))
            fixture.release.set()
            try:
                lua('vim.cmd("qa!")')
            except Exception:
                pass
            try:
                editor.wait(timeout=5)
            except subprocess.TimeoutExpired:
                editor.terminate()
                editor.wait(timeout=5)
            server.shutdown()
            daemon.terminate()
            daemon.wait(timeout=5)
            log.close()
            (evidence / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
