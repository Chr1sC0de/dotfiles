"""Opt-in live Herdr smoke test; creates and cleans up only owned sibling panes."""

import http.server
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, str(Path(__file__).parent / "support"))
from opencode_fixture import config, handler_for


def main():
    assert os.environ.get("HERDR_ENV") == "1", "Run inside Herdr"
    repo = Path(__file__).resolve().parents[1]
    owned = []

    def herdr(*args):
        output = subprocess.check_output(["herdr", *args], text=True, timeout=45)
        return json.loads(output)["result"] if output.strip() else {}

    def wait(check, label):
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            try:
                if check():
                    return
            except (subprocess.SubprocessError, ValueError, KeyError):
                pass
            time.sleep(0.2)
        raise AssertionError("Timed out: " + label)

    with tempfile.TemporaryDirectory(prefix="herdr-smoke-", dir="/tmp/opencode") as tmp:
        base = Path(tmp)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler_for(lambda body: {"content": "HERDR_SMOKE_DONE"}))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        socket = str(base / "nvim.sock")
        state = base / "state"
        state.mkdir()
        init = base / "init.lua"
        opts = {"command": str(Path.home() / ".local/share/nvim/tandem/bin/tandem"),
                "root": str(repo), "state_home": str(state)}
        init.write_text("\n".join([
            f"vim.opt.runtimepath:append({json.dumps(str(p))})" for p in
            [repo / "config/nvim", Path.home() / ".local/share/nvim/lazy/tandem.nvim"]
        ] + [
            'vim.opt.swapfile = false',
            'vim.opt.shortmess:append("I")',
            'vim.opt.cmdheight = 2',
            'vim.notify = function(message) vim.g.smoke_notice = tostring(message) end',
            f'vim.env.OPENCODE_CONFIG_CONTENT = {json.dumps(json.dumps(config(server.server_port)))}',
            f'local opts = vim.json.decode({json.dumps(json.dumps(opts))})',
            'require("opencode.tandem").configure(opts)',
            'require("tandem").setup(opts)',
            'require("config.opencode").setup()',
        ]))

        def expr(code):
            return json.loads(subprocess.check_output([
                "nvim", "--server", socket, "--remote-expr",
                "luaeval(" + json.dumps("vim.json.encode(" + code + ")") + ")",
            ], text=True, stderr=subprocess.DEVNULL, timeout=5))

        def lua(code):
            return expr("(function() " + code + "; return true end)()")

        def session():
            return expr('require("opencode.chat").active_session()') or {}

        try:
            host = herdr("pane", "split", "--current", "--direction", "down", "--cwd", str(repo), "--no-focus")["pane"]["pane_id"]
            owned.append(host)
            herdr("pane", "run", host, shlex.join(["nvim", "--listen", socket, "-u", str(init), "-i", "NONE"]))
            wait(lambda: expr('require("tandem").status().connected'), "Tandem connection")
            lua('require("opencode.chat").create()')
            wait(lambda: session().get("herdr_pane_id"), "backing pane")
            pane = session()["herdr_pane_id"]
            owned.append(pane)
            wait(lambda: session().get("launch_status") == "attached", "terminal attachment")
            name = session()["herdr_agent_name"]
            herdr("agent", "prompt", name, "Reply HERDR_SMOKE_DONE")
            wait(lambda: session().get("hook_seen") and session().get("task_status") == "DONE", "completion notification")
            print("PASS: live Herdr launch, terminal attachment, and completion notification", flush=True)
            lua('require("opencode.chat").detach(require("opencode.chat").active_bufnr())')
            assert herdr("agent", "get", name)["agent"]["pane_id"] == pane
            lua('require("opencode.chat").attach_agent(' + json.dumps(name) + ')')
            wait(lambda: session().get("launch_status") == "attached", "reattachment")
            herdr("agent", "prompt", name, "Reply HERDR_SMOKE_DONE again")
            wait(lambda: session().get("hook_seen") and session().get("task_status") == "DONE", "rerouted notification")
            print("PASS: live detach, reattach, and notification routing", flush=True)
            lua('require("opencode.chat").delete_buffer(require("opencode.chat").active_bufnr())')
            wait(lambda: pane not in [p["pane_id"] for p in herdr("pane", "list")["panes"]], "pane cleanup")
            owned.remove(pane)
            print("PASS: explicit deletion closes the owned backing pane", flush=True)
        except Exception:
            for pane in owned:
                subprocess.run(["herdr", "pane", "read", pane, "--source", "recent-unwrapped", "--lines", "40"], timeout=10)
            raise
        finally:
            for pane in reversed(owned):
                subprocess.run(["herdr", "pane", "close", pane], capture_output=True, timeout=10)
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
