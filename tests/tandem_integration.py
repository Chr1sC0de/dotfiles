"""Real Codex + Tandem + Neovim + the dotfiles' Conform/launcher integration.

The model endpoint is a deterministic local Responses API fixture. No account,
API key, or model call is used. Codex itself executes the requested tools, with
its real native sandbox and real MCP client. Herdr argument checks are separate
from a native Herdr GUI session, which this test does not simulate or claim.
"""
import hashlib
import http.server
import json
import os
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import tomllib


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def tandem_result(value):
    """Find the MCP server's JSON inside Codex's text/content wrappers."""
    if isinstance(value, str):
        if "\nOutput:\n" in value:
            value = value.split("\nOutput:\n", 1)[1]
        try:
            return tandem_result(json.loads(value))
        except (ValueError, TypeError):
            return None
    if isinstance(value, dict):
        if isinstance(value.get("ok"), bool):
            return value
        for item in value.values():
            found = tandem_result(item)
            if found is not None:
                return found
    if isinstance(value, list):
        for item in value:
            found = tandem_result(item)
            if found is not None:
                return found
    return None


def tool_definitions(body):
    def visit(items, namespace=None):
        for item in items:
            if item.get("type") == "namespace":
                yield from visit(item.get("tools", []), item["name"])
            else:
                yield namespace, item
    return list(visit(body.get("tools", [])))


class ModelFixture:
    def __init__(self, root):
        self.root = root
        self.ready_for_human = threading.Event()
        self.human_changed = threading.Event()
        self.error = None
        self.trace = []
        self.counter = 0
        self.native_shell_checked = False
        self.native_patch_checked = False

    def record(self, event, **values):
        self.trace.append({"event": event, **values})

    def call(self, call_id, name, arguments, namespace="mcp__tandem", custom=False):
        item = {"type": "custom_tool_call" if custom else "function_call",
                "call_id": call_id, "name": name}
        if namespace:
            item["namespace"] = namespace
        item["input" if custom else "arguments"] = arguments if custom else json.dumps(arguments)
        self.record("tool_requested", call_id=call_id, name=name, namespace=namespace)
        return item

    def answer(self, body):
        self.counter += 1
        assert self.counter <= 20, "unexpected repeated model requests"
        assert body["model"] == "gpt-6-astra", "the launcher changed the selected model"
        inputs = body.get("input", [])
        outputs = {item.get("call_id"): item.get("output") for item in inputs
                   if item.get("type") in ("function_call_output", "custom_tool_call_output")}
        readonly = "TANDEM_READONLY_TEST" in json.dumps(inputs)
        if readonly:
            if "readonly-write" not in outputs:
                return self.call("readonly-write", "tandem_write_file", {
                    "path": "readonly-forbidden.txt", "expected_revision": "missing", "content": "bad\n"})
            assert not (self.root / "readonly-forbidden.txt").exists()
            denied = str(outputs["readonly-write"]).lower()
            assert any(term in denied for term in ("unknown", "not found", "not available", "read.only", "read_only", "unsupported", "unrecognized", "disabled")), denied
            self.record("read_only_writer_rejected")
            return {"type": "message", "role": "assistant", "id": "readonly-done",
                    "content": [{"type": "output_text", "text": "READONLY_DONE"}]}

        definitions = tool_definitions(body)
        if self.counter == 1:
            self.record("tool_catalogue", tools=body.get("tools", []))
        if not self.native_shell_checked:
            definition = next(((ns, item) for ns, item in definitions
                               if item.get("name") in ("exec_command", "shell_command", "shell")), None)
            assert definition, "native shell tool must be exposed to verify its sandbox: " + str([(ns, item.get('name'), item.get('type')) for ns, item in definitions])
            if "native-shell" not in outputs and definition:
                namespace, item = definition
                name = item["name"]
                command = "cat a.py; printf 'native write must fail\\n' > native-shell.txt"
                if name == "exec_command":
                    args = {"cmd": command, "workdir": str(self.root), "max_output_tokens": 1000}
                elif name == "shell_command":
                    args = {"command": command, "workdir": str(self.root)}
                else:
                    args = {"command": ["/bin/sh", "-c", command], "workdir": str(self.root)}
                return self.call("native-shell", name, args, namespace=namespace)
            if "native-shell" in outputs:
                result = str(outputs["native-shell"]).lower()
                assert "value=0" in result, "native shell failed to read before the write probe: " + result
                assert any(term in result for term in ("permission denied", "read-only", "not permitted", "rejected", "denied", "write access")), result
                self.record("native_shell_write_rejected", output=outputs["native-shell"])
            else:
                self.record("native_shell_not_exposed")
            assert not (self.root / "native-shell.txt").exists()
            self.native_shell_checked = True

        if not self.native_patch_checked:
            definition = next(((ns, item) for ns, item in definitions if item.get("name") == "apply_patch"), None)
            if "native-patch" not in outputs:
                namespace, item = definition or ("functions", {"type": "custom"})
                patch = "*** Begin Patch\n*** Add File: native-patch.txt\n+native write must fail\n*** End Patch\n"
                assert item.get("type") == "custom", item
                return self.call("native-patch", "apply_patch", patch, namespace=namespace, custom=True)
            if "native-patch" in outputs:
                result = str(outputs["native-patch"]).lower()
                assert any(term in result for term in ("permission denied", "read-only", "not permitted", "rejected", "denied", "write access", "unknown", "unrecognized", "unsupported")), result
                self.record("native_patch_write_rejected", output=outputs["native-patch"])
            else:
                self.record("native_patch_not_exposed")
            assert not (self.root / "native-patch.txt").exists()
            self.native_patch_checked = True

        if "read-base" not in outputs:
            return self.call("read-base", "tandem_read_file", {"path": "a.py"})
        base = tandem_result(outputs["read-base"])
        assert base and base["ok"] and base["content"] == "value=0\n", outputs["read-base"]
        if "write-stale" not in outputs:
            self.ready_for_human.set()
            assert self.human_changed.wait(25), "test controller did not edit the buffer"
            return self.call("write-stale", "tandem_write_file", {
                "path": "a.py", "expected_revision": base["revision"], "content": "value = 99\n"})
        stale = tandem_result(outputs["write-stale"])
        assert stale and stale["error"]["code"] == "stale_revision", outputs["write-stale"]
        if "read-fresh" not in outputs:
            self.record("stale_proposal_rejected", code=stale["error"]["code"])
            return self.call("read-fresh", "tandem_read_file", {"path": "a.py"})
        fresh = tandem_result(outputs["read-fresh"])
        assert fresh and fresh["content"] == "value = 1\n", outputs["read-fresh"]
        assert fresh["revision"] == digest("value = 1\n")
        if "write-fresh" not in outputs:
            return self.call("write-fresh", "tandem_write_file", {
                "path": "a.py", "expected_revision": fresh["revision"], "content": "value=2\n"})
        saved = tandem_result(outputs["write-fresh"])
        assert saved and saved["ok"] and saved["revision"] == digest("value = 2\n"), outputs["write-fresh"]
        self.record("fresh_edit_formatted_and_saved", revision=saved["revision"])
        return {"type": "message", "role": "assistant", "id": "edit-done",
                "content": [{"type": "output_text", "text": "EDIT_DONE"}]}


def handler_for(fixture):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_POST(self):
            try:
                assert self.path.endswith("/responses"), self.path
                assert not self.headers.get("Content-Encoding"), "disable request compression for the fixture"
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                item = fixture.answer(body)
                response_id = "fixture-" + str(fixture.counter)
                events = [
                    {"type": "response.created", "response": {"id": response_id}},
                    {"type": "response.output_item.done", "item": item},
                    {"type": "response.completed", "response": {"id": response_id, "usage": {
                        "input_tokens": 0, "output_tokens": 0, "total_tokens": 0}}},
                ]
                payload = "".join("event: " + event["type"] + "\ndata: " + json.dumps(event) + "\n\n" for event in events).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            except Exception as error:
                fixture.error = repr(error)
                self.send_error(500, "fixture assertion failed")
    return Handler


def main():
    dotfiles = pathlib.Path(__file__).resolve().parents[1]
    plugin = pathlib.Path(os.environ["TANDEM_NVIM"]).resolve()
    conform = pathlib.Path(os.environ["TANDEM_CONFORM"]).resolve()
    evidence = dotfiles / "artifacts/tandem"
    evidence.mkdir(parents=True, exist_ok=True)
    nvim = shutil.which("nvim")
    codex = shutil.which("codex")
    assert nvim and codex and shutil.which("cargo") and shutil.which("ruff")
    spec_path = dotfiles / "config/nvim/lua/plugins/tandem.lua"
    spec_source = spec_path.read_text()
    plugin_revision = re.search(r'commit = "([0-9a-f]{40})"', spec_source)[1]
    cli_revision = re.search(r'"--rev", "([0-9a-f]{40})"', spec_source)[1]
    assert subprocess.check_output(["git", "-C", str(plugin), "rev-parse", "HEAD"], text=True).strip() == plugin_revision
    conform_revision = json.loads((dotfiles / "config/nvim/lazy-lock.json").read_text())["conform.nvim"]["commit"]
    assert subprocess.check_output(["git", "-C", str(conform), "rev-parse", "HEAD"], text=True).strip() == conform_revision
    report = {"dotfiles_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=dotfiles, text=True).strip(),
              "tandem_revision": cli_revision, "plugin_revision": plugin_revision, "conform_revision": conform_revision,
              "model_endpoint": "deterministic local fixture; no live model or credentials", "checks": []}
    def passed(name):
        report["checks"].append(name)
        print("PASS: " + name, flush=True)

    with tempfile.TemporaryDirectory(prefix="td-dot-", dir=os.environ.get("TANDEM_TEST_TMPDIR", os.environ.get("RUNNER_TEMP", "/tmp"))) as temporary:
        base = pathlib.Path(temporary)
        root = base / "project"
        root.mkdir()
        subprocess.run(["git", "init", "--quiet", str(root)], check=True)
        file = root / "a.py"
        file.write_text("value=0\n")
        env = os.environ.copy()
        for key, directory in (("XDG_DATA_HOME", "data"), ("XDG_STATE_HOME", "state"),
                               ("XDG_CACHE_HOME", "cache"), ("XDG_CONFIG_HOME", "config"),
                               ("CODEX_HOME", "codex-test-home")):
            path = base / directory
            path.mkdir()
            env[key] = str(path)
        env["TERM"] = "xterm-256color"
        # This child's isolated Codex home contains only fixture configuration.
        fixture = ModelFixture(root)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler_for(fixture))
        threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.1}, daemon=True).start()
        model_config = '\n'.join([
            'model = "gpt-6-astra"', 'model_provider = "tandem-fixture"',
            '[features]', 'enable_request_compression = false', 'shell_snapshot = false', 'multi_agent = false',
            '[model_providers.tandem-fixture]', 'name = "Tandem integration fixture"',
            'base_url = "http://127.0.0.1:' + str(server.server_port) + '/v1"',
            'wire_api = "responses"', 'requires_openai_auth = false', 'supports_websockets = false',
            'request_max_retries = 0', 'stream_max_retries = 0',
            '[projects.' + json.dumps(str(root)) + ']', 'trust_level = "trusted"',
        ])
        (pathlib.Path(env["CODEX_HOME"]) / "config.toml").write_text(model_config)
        bootstrap = base / "install.lua"
        cli_path_file = base / "cli-path"
        bootstrap.write_text('local spec = dofile(' + json.dumps(str(spec_path)) + ')\n'
                             + 'assert(spec.enabled and spec.lazy == false)\nspec.build()\n'
                             + 'vim.fn.writefile({spec.opts.command}, ' + json.dumps(str(cli_path_file)) + ')\n')
        log_path = evidence / "process.log"
        log = log_path.open("wb")
        editor = None
        daemon_pid = None
        binary = None
        try:
            subprocess.run([nvim, "--headless", "-u", "NONE", "-l", str(bootstrap)], cwd=root,
                           env=env, stdout=log, stderr=log, timeout=600, check=True)
            binary = cli_path_file.read_text().strip()
            report["versions"] = {
                "tandem": subprocess.check_output([binary, "--version"], text=True).strip(),
                "codex": subprocess.check_output([codex, "--version"], env=env, text=True).strip(),
                "neovim": subprocess.check_output([nvim, "--version"], text=True).splitlines()[0],
                "ruff": subprocess.check_output(["ruff", "--version"], text=True).strip(),
            }
            assert report["versions"]["tandem"] == "tandem-cli 0.2.0"
            passed("actual Lazy build callback installs the pinned Rust CLI")
            socket = str(base / "nvim.sock")
            init = base / "init.lua"
            init.write_text('\n'.join([
                'vim.opt.runtimepath:append(' + json.dumps(str(dotfiles / "config/nvim")) + ')',
                'vim.opt.runtimepath:append(' + json.dumps(str(plugin)) + ')',
                'vim.opt.runtimepath:append(' + json.dumps(str(conform)) + ')',
                'vim.opt.swapfile = false', 'vim.cmd("filetype plugin indent on")',
                'dofile(' + json.dumps(str(dotfiles / "config/nvim/lua/plugins/conform.lua")) + ').config()',
                'vim.cmd.edit(' + json.dumps(str(file)) + ')',
                'require("tandem").setup(dofile(' + json.dumps(str(spec_path)) + ').opts)',
                'require("config.codex").setup()',
            ]))
            editor = subprocess.Popen([nvim, "--headless", "--listen", socket, "-u", str(init)],
                                      cwd=root, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log)

            def expr(expression):
                lua = "vim.json.encode(" + expression + ")"
                output = subprocess.check_output([nvim, "--server", socket, "--remote-expr", "luaeval(" + json.dumps(lua) + ")"],
                                                 cwd=root, env=env, text=True, stderr=log, timeout=5)
                return json.loads(output)

            def cli(*args):
                output = subprocess.check_output([binary, "--root", str(root), "--state-home", env["XDG_STATE_HOME"], *args],
                                                 env=env, text=True, stderr=log, timeout=8)
                return json.loads(output)

            def until(predicate, label, timeout=40):
                deadline = time.monotonic() + timeout
                last = None
                while time.monotonic() < deadline:
                    if fixture.error:
                        raise AssertionError(fixture.error)
                    assert editor.poll() is None, "Neovim exited; see process.log"
                    try:
                        if predicate():
                            return
                    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as error:
                        last = error
                    time.sleep(0.05)
                raise AssertionError(label + ": " + str(last))

            until(lambda: expr("require('tandem').status().connected"), "daemon connection")
            daemon_pid = cli("status")["pid"]
            assert expr("require('tandem').status().root") == str(root)
            passed("dotfiles plugin options start and attach the daemon automatically")

            def check_args(argv, read_only=False):
                assert argv[argv.index("--sandbox") + 1] == "read-only"
                config = {}
                for index, arg in enumerate(argv[:-1]):
                    if arg == "-c":
                        parsed = tomllib.loads(argv[index + 1])
                        config.update(parsed)
                assert config["approval_policy"] == "never"
                mcp = config["mcp_servers"]["tandem"]
                assert mcp["command"] == binary and mcp["required"] is True
                assert set(mcp["tools"]) == set(mcp["enabled_tools"])
                assert all(tool["approval_mode"] == "approve" for tool in mcp["tools"].values())
                assert mcp["args"][:4] == ["--root", str(root), "--state-home", env["XDG_STATE_HOME"]]
                assert ("--read-only" in mcp["args"]) == read_only
                assert ("tandem_write_file" in mcp["enabled_tools"]) != read_only

            # Use the real direct-chat function, intercepting only the terminal
            # launch so the test does not pretend to drive Codex's interactive UI.
            direct = expr("(function() local old = vim.fn.jobstart; local notify = vim.notify; local captured; "
                          "vim.notify = function(msg, level, opts) if msg ~= 'Failed to start Codex chat' then notify(msg, level, opts) end end; "
                          "vim.fn.jobstart = function(cmd, opts) "
                          "if cmd[1] == 'codex' then captured = cmd; return -1 end; return old(cmd, opts) end; "
                          "local ok, err = pcall(require('codex.chat').create); vim.fn.jobstart = old; vim.notify = notify; assert(ok, err); return captured end)()")
            check_args(direct)
            expr("(function() vim.cmd.edit(" + json.dumps(str(file)) + "); return true end)()")
            herdr = expr("require('codex.herdr').agent_start_args({cwd=" + json.dumps(str(root))
                         + ",herdr_agent_name='nvim-codex-td-test',herdr_pane_id='w1:p2',tandem_args=require('tandem').codex_args({cwd="
                         + json.dumps(str(root)) + "})})")
            check_args(herdr[herdr.index("--") + 1:])
            passed("actual direct-chat and Herdr launch paths forward the protected Codex arguments")

            def launch(action, marker):
                code = "(function() local jobs=require('codex.ephemeral.jobs'); jobs.run(" + json.dumps(action)
                code += ",{kind='file',path=" + json.dumps(str(file)) + ",modified=vim.bo.modified and 'yes' or 'no',"
                code += "context_lines={'File: a.py'},spinner_buf=vim.api.nvim_get_current_buf(),spinner_line=1,start_line=1,end_line=1},"
                code += json.dumps(marker) + "); return require('codex.state').next_ephemeral_job_id - 1 end)()"
                return expr(code)

            job_id = launch("edit", "TANDEM_EDIT_TEST: update a.py through Tandem")
            until(lambda: fixture.ready_for_human.is_set(), "Codex reaches its first real MCP read")
            assert file.read_text() == "value=0\n"
            expr("(function() vim.api.nvim_buf_set_lines(0,0,-1,false,{'value=1'}); return true end)()")
            until(lambda: bool(cli("status")["leases"]), "human edit lease")
            fixture.human_changed.set()
            until(lambda: cli("status")["waiting"] == 1, "real Codex MCP writer waits")
            assert file.read_text() == "value=0\n"
            assert expr("vim.api.nvim_buf_get_lines(0,0,-1,false)") == ["value=1"]
            passed("real Codex MCP write waits while the live human buffer stays unchanged")
            proposal = base / "other.txt"
            proposal.write_text("other agent\n")
            assert cli("write", "other.txt", "--expect", "missing", "--content-file", str(proposal))["ok"]
            assert (root / "other.txt").read_text() == "other agent\n"
            assert cli("status")["waiting"] == 1 and expr("vim.bo.modified") is True
            passed("another agent can edit another file during the human lease")
            expr("(function() vim.cmd('write'); return true end)()")
            until(lambda: expr("require('codex.state').ephemeral_jobs[" + str(job_id) + "].status") in ("success", "failed", "failed_to_start"),
                  "Codex edit job completes")
            job = expr("require('codex.state').ephemeral_jobs[" + str(job_id) + "]")
            assert job["status"] == "success", job
            assert file.read_text() == "value = 2\n"
            assert expr("vim.api.nvim_buf_get_lines(0,0,-1,false)") == ["value = 2"]
            assert expr("vim.bo.modified") is False
            passed("stale proposal is rejected; reread and regenerated edit run the actual Conform save hooks")
            assert fixture.native_shell_checked and fixture.native_patch_checked
            assert not (root / "native-shell.txt").exists() and not (root / "native-patch.txt").exists()
            passed("native patch and shell paths cannot write around Tandem")

            read_job = launch("command", "TANDEM_READONLY_TEST: demonstrate this job cannot write")
            until(lambda: expr("require('codex.state').ephemeral_jobs[" + str(read_job) + "].status") in ("success", "failed", "failed_to_start"),
                  "read-only Codex job completes")
            assert expr("require('codex.state').ephemeral_jobs[" + str(read_job) + "].status") == "success"
            assert not (root / "readonly-forbidden.txt").exists() and file.read_text() == "value = 2\n"
            passed("actual read-only Codex job cannot invoke Tandem's writer")
            report["result"] = "passed"
        except Exception as error:
            report["result"] = "failed"
            report["error"] = repr(error)
            raise
        finally:
            fixture.human_changed.set()
            if editor and editor.poll() is None:
                try:
                    report["jobs"] = expr("(function() local out = {}; for _, job in pairs(require('codex.state').ephemeral_jobs) do "
                                          "out[#out+1] = {action=job.action,status=job.status,exit_code=job.exit_code,"
                                          "stderr=job.stderr_lines,answer=job.answer_lines}; end; return out end)()")
                    if report.get("result") != "passed":
                        print(json.dumps(report["jobs"], indent=2), file=sys.stderr)
                except (OSError, ValueError, subprocess.SubprocessError):
                    pass
                editor.terminate()
                editor.communicate(timeout=10)
            if daemon_pid and binary:
                try:
                    status = json.loads(subprocess.check_output([binary, "--root", str(root), "--state-home", env["XDG_STATE_HOME"], "status"],
                                                               env=env, text=True, stderr=subprocess.DEVNULL, timeout=2))
                    if status.get("pid") == daemon_pid:
                        os.kill(daemon_pid, signal.SIGTERM)
                except (OSError, ValueError, subprocess.SubprocessError):
                    pass
            server.shutdown()
            server.server_close()
            log.close()
            report["tool_trace"] = fixture.trace
            (evidence / "results.json").write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps(report, indent=2), flush=True)
            if report.get("result") != "passed":
                print(log_path.read_text(errors="replace")[-12000:], file=sys.stderr)
    print("All Tandem dotfiles integration checks passed.", flush=True)


if __name__ == "__main__":
    main()
