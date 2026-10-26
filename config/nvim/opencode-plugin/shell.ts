import { spawn } from "node:child_process"

// The MCP writer runs outside this namespace. Shell commands retain inspection
// capabilities, while the entire host filesystem stays read-only and network
// access cannot reach a second writer. Never fall back to an unsandboxed shell.
export function inspect(command: string, cwd: string, signal: AbortSignal, timeout = 120000): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn("bwrap", [
      "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc",
      "--unshare-pid", "--unshare-net", "--die-with-parent", "--new-session",
      "--chdir", cwd, "--", "/bin/sh", "-c", command,
    ], { signal, timeout: Math.min(Math.max(timeout, 1), 120000), stdio: ["ignore", "pipe", "pipe"] })
    let output = ""
    const append = (chunk: Buffer) => { output = (output + chunk.toString()).slice(-51200) }
    child.stdout.on("data", append)
    child.stderr.on("data", append)
    child.on("error", reject)
    child.on("close", (code, killed) => resolve(`Exit code: ${code ?? killed}\n${output}`))
  })
}
