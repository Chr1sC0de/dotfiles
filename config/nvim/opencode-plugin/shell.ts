import { spawn } from "node:child_process"

// Coding sessions use the user's normal shell permissions. Analysis sessions
// stay sandboxed; never fall back to an unrestricted shell if Bubblewrap fails.
export function run(command: string, cwd: string, signal: AbortSignal, timeout = 120000, readOnly = false): Promise<string> {
  return new Promise((resolve, reject) => {
    const executable = readOnly ? "bwrap" : "/bin/sh"
    const args = readOnly ? [
      "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc",
      "--unshare-pid", "--unshare-net", "--die-with-parent", "--new-session",
      "--chdir", cwd, "--", "/bin/sh", "-c", command,
    ] : ["-c", command]
    const child = spawn(executable, args, {
      cwd, signal, timeout: Math.min(Math.max(timeout, 1), 120000), stdio: ["ignore", "pipe", "pipe"],
    })
    let output = ""
    const append = (chunk: Buffer) => { output = (output + chunk.toString()).slice(-51200) }
    child.stdout.on("data", append)
    child.stderr.on("data", append)
    child.on("error", reject)
    child.on("close", (code, killed) => resolve(`Exit code: ${code ?? killed}\n${output}`))
  })
}
