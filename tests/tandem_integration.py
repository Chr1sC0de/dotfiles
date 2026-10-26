"""Real OpenCode V2 -> MCP -> Tandem -> Neovim/Conform integration.

Only model responses are deterministic. No credentials or live model required.
Herdr launch contracts are unit-tested separately from the interactive smoke test.
"""

import hashlib
import http.server
import json
import os
import pathlib
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
    def __init__(self):
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
            assert not ({"shell", "patch", "write", "edit", "subagent", "execute"} & tools), tools
            assert "tandem_tandem_read_file" in tools, tools
            readonly = "Analysis-only Tandem session" in system
            assert ("tandem_tandem_write_file" in tools) != readonly, tools
            self.calls.append({"readonly": readonly, "tools": sorted(tools)})
            if readonly:
                return {"content": "QUERY_DONE: use the shared helper"}
            if "CONTINUE_TEST" in user:
                assert "FOLLOWUP_DONE" in json.dumps(messages), "resumed history lost"
                return {"content": "CONTINUE_DONE"}
            followup = "FOLLOWUP_TEST" in user
            if followup:
                assert "QUERY_DONE" in user, "query-to-edit history lost"
            outputs = {m["tool_call_id"]: m["content"] for m in messages if m["role"] == "tool"}
            if "native-write" not in outputs:
                return {"tool_calls": [{"id": "native-write", "type": "function", "function": {
                    "name": "nvim_shell", "arguments": json.dumps({"command": "cat a.py; printf forbidden > native-forbidden.txt"})}}]}
            native = str(outputs["native-write"])
            assert "value" in native and ("Read-only file system" in native or "Permission denied" in native), native
            prefix = "followup" if followup else "initial"
            read_id, write_id = prefix + "-read", prefix + "-write"

            def call(id_, name, args):
                return {"tool_calls": [{"id": id_, "type": "function", "function": {
                    "name": "tandem_tandem_" + name, "arguments": json.dumps(args)}}]}

            if read_id not in outputs:
                self.read.set()
                return call(read_id, "read_file", {"path": "a.py"})
            current = tandem_result(outputs[read_id])
            assert current and current["ok"], outputs[read_id]
            if write_id not in outputs:
                if not followup:
                    assert self.release.wait(30), "human edit was not delivered"
                return call(write_id, "write_file", {"path": "a.py",
                    "content": "value=3\n" if followup else "value=2\n",
                    "expected_revision": current["revision"]})
            saved = tandem_result(outputs[write_id])
            assert saved is not None, outputs[write_id]
            if not saved["ok"]:
                assert saved["error"]["code"] == "stale_revision", saved
                if "retry-read" not in outputs:
                    return call("retry-read", "read_file", {"path": "a.py"})
                fresh = tandem_result(outputs["retry-read"])
                assert fresh and fresh["ok"]
                if "retry-write" not in outputs:
                    return call("retry-write", "write_file", {"path": "a.py", "content": "value=2\n",
                        "expected_revision": fresh["revision"]})
                saved = tandem_result(outputs["retry-write"])
                assert saved and saved["ok"], outputs["retry-write"]
            expected = "value = 3\n" if followup else "value = 2\n"
            assert saved["revision"] == hashlib.sha256(expected.encode()).hexdigest(), saved
            return {"content": "FOLLOWUP_DONE" if followup else "EDIT_DONE"}
        except Exception as error:
            self.error = repr(error)
            return {"content": "FIXTURE_FAILED: " + repr(error)}


def main():
    repo = pathlib.Path(__file__).resolve().parents[1]
    plugin = pathlib.Path(os.environ.get("TANDEM_NVIM", pathlib.Path.home() / ".local/share/nvim/lazy/tandem.nvim"))
    conform = pathlib.Path(os.environ.get("TANDEM_CONFORM", pathlib.Path.home() / ".local/share/nvim/lazy/conform.nvim"))
    binary = os.environ.get("TANDEM_BIN", str(pathlib.Path.home() / ".local/share/nvim/tandem/bin/tandem"))
    evidence = pathlib.Path(os.environ.get("TANDEM_EVIDENCE_DIR", repo / "artifacts/tandem"))
    evidence.mkdir(parents=True, exist_ok=True)
    nvim = shutil.which("nvim")
    assert nvim and shutil.which("opencode") and shutil.which("ruff")
    assert pathlib.Path(binary).is_file(), "Install the pinned Tandem CLI or set TANDEM_BIN"
    report = {"result": "FAIL", "checks": [], "versions": {}}

    def passed(name):
        report["checks"].append(name)
        print("PASS: " + name, flush=True)

    with tempfile.TemporaryDirectory(prefix="td-open-", dir=os.environ.get("TANDEM_TEST_TMPDIR", "/tmp/opencode")) as tmp:
        base = pathlib.Path(tmp)
        root = base / "project"
        root.mkdir()
        subprocess.run(["git", "init", "--quiet", str(root)], check=True)
        source = root / "a.py"
        source.write_text("value=0\n")
        (root / "AGENTS.md").write_text("HOST_GUIDANCE_MARKER: preserve host instructions.\n")
        env = {k: v for k, v in os.environ.items() if not k.startswith(("OPENCODE_", "HERDR_"))}
        for key in ("HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_CONFIG_HOME"):
            env[key] = str(base / key)
            pathlib.Path(env[key]).mkdir()
        env["PWD"] = str(root)
        env["TERM"] = "xterm-256color"
        fixture = Fixture()
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler_for(fixture.answer))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        env["OPENCODE_CONFIG_CONTENT"] = json.dumps(config(server.server_port))
        opts = {"command": binary, "root": str(root), "state_home": env["XDG_STATE_HOME"]}
        init = base / "init.lua"
        init.write_text("\n".join([
            f"vim.opt.runtimepath:append({json.dumps(str(p))})" for p in [repo / "config/nvim", plugin, conform]
        ] + [
            "vim.opt.swapfile = false",
            'vim.cmd("filetype plugin indent on")',
            f'dofile({json.dumps(str(repo / "config/nvim/lua/plugins/conform.lua"))}).config()',
            f"vim.cmd.edit({json.dumps(str(source))})",
            f"local opts = vim.json.decode({json.dumps(json.dumps(opts))})",
            'require("opencode.tandem").configure(opts)',
            'require("tandem").setup(opts)',
            'require("config.opencode").setup()',
        ]))
        socket = str(base / "nvim.sock")
        log = (evidence / "process.log").open("w")
        editor = subprocess.Popen([nvim, "--headless", "--listen", socket, "-u", str(init)],
                                  cwd=root, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log)

        def expr(expression):
            output = subprocess.check_output([nvim, "--server", socket, "--remote-expr",
                "luaeval(" + json.dumps("vim.json.encode(" + expression + ")") + ")"],
                cwd=root, env=env, text=True, stderr=log, timeout=5)
            return json.loads(output)

        def lua(code):
            return expr("(function() " + code + "; return true end)()")

        def cli(*args):
            return json.loads(subprocess.check_output([binary, "--root", str(root), "--state-home",
                env["XDG_STATE_HOME"], *args], text=True, env=env, timeout=10))

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
            lua(f'require("opencode.ephemeral.jobs").run({json.dumps(action)}, require("opencode.context.targets").build_file(), {json.dumps(instruction)})')
            return expr('require("opencode.state").next_ephemeral_job_id - 1')

        def job(id_):
            return expr(f'require("opencode.state").ephemeral_jobs[{id_}]')

        def finish(id_, expected):
            until(lambda: job(id_).get("finished_at"), expected)
            record = job(id_)
            assert record["status"] == "success", record
            assert expected in "\n".join(record["answer_lines"]), record
            assert record["thread_id"].startswith("ses_"), record
            return record

        try:
            for name, command in {"opencode": ["opencode", "--version"], "tandem": [binary, "--version"],
                                  "neovim": [nvim, "--version"], "ruff": ["ruff", "--version"]}.items():
                report["versions"][name] = subprocess.check_output(command, text=True, env=env).splitlines()[0]
            until(lambda: expr('require("tandem").status().connected'), "editor connection")
            passed("real Tandem daemon and editor connected")
            first = launch("edit", "EDIT_TEST")
            until(fixture.read.is_set, "first MCP read")
            # The model pauses after its first read, so the human's draft must
            # block its write and then force a fresh-revision retry after save.
            lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, {"value=1"})')
            until(lambda: len(expr('require("tandem").status().dirty')) == 1, "dirty claim")
            fixture.release.set()
            until(lambda: cli("status")["waiting"] > 0, "writer waits for human")
            assert expr('vim.api.nvim_buf_get_lines(0, 0, -1, false)') == ["value=1"]
            lua('vim.cmd("write")')
            finish(first, "EDIT_DONE")
            assert source.read_text() == "value = 2\n"
            assert expr('vim.api.nvim_buf_get_lines(0, 0, -1, false)') == ["value = 2"]
            passed("agent waits for unsaved buffer, retries stale revision, and writes through Conform")
            query = launch("query", "QUERY_TEST")
            finish(query, "QUERY_DONE")
            assert source.read_text() == "value = 2\n"
            passed("query exposes read-only MCP and no native writers")
            lua(f'assert(require("opencode.ephemeral.jobs").follow_up(require("opencode.state").ephemeral_jobs[{query}], "FOLLOWUP_TEST", {{action="edit"}}))')
            follow = expr('require("opencode.state").next_ephemeral_job_id - 1')
            promoted = finish(follow, "FOLLOWUP_DONE")
            assert source.read_text() == "value = 3\n"
            passed("query-to-edit promotion preserves discussion and grants only Tandem writes")
            lua(f'assert(require("opencode.ephemeral.jobs").follow_up(require("opencode.state").ephemeral_jobs[{follow}], "CONTINUE_TEST"))')
            resumed = finish(expr('require("opencode.state").next_ephemeral_job_id - 1'), "CONTINUE_DONE")
            assert promoted["thread_id"] == resumed["thread_id"]
            passed("follow-up resumes the same native OpenCode session")
            lua('require("opencode.backend").generate("Generate a commit subject", vim.fn.getcwd(), function(code, text) vim.g.generated = {code=code,text=text} end)')
            until(lambda: expr("vim.g.generated") is not None, "text generation")
            assert expr("vim.g.generated") == {"code": 0, "text": "test: migrate editor integration"}
            passed("tool-free text generation returns clean model output")
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
            log.close()
            (evidence / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
