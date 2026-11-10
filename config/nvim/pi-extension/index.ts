// Pi 1.5+: status IPC only. Editing remains the agent-neutral Tandem CLI.
import { spawn } from "node:child_process"
import { fileURLToPath } from "node:url"

const hook = fileURLToPath(new URL("../bin/opencode-nvim-hook", import.meta.url))

export default function (pi: any) {
  if (!process.env.OPENCODE_NVIM_SERVER && !process.env.OPENCODE_NVIM_STATE_FILE) return
  let notifications = Promise.resolve()
  let lastText = ""
  let error: string | undefined
  const notify = (name: string, ctx: any, extra = {}) => {
    const event = { backend: "pi", hook_event_name: name,
      session_id: ctx.sessionManager.getSessionId(), session_path: ctx.sessionManager.getSessionFile(), ...extra }
    notifications = notifications.then(() => new Promise<void>((resolve) => {
      const status = name === "PermissionRequest" ? "waiting"
        : ["Stop", "Error", "SessionStart", "SessionShutdown"].includes(name) ? "done" : "working"
      const child = spawn("bash", [hook, status], { stdio: ["pipe", "ignore", "ignore"], timeout: 3000 })
      child.on("error", () => resolve())
      child.on("close", () => resolve())
      child.stdin.on("error", () => {})
      child.stdin.end(JSON.stringify(event))
    }))
    return notifications
  }
  pi.on("session_start", async (_event: any, ctx: any) => {
    lastText = ""
    error = undefined
    await notify("SessionStart", ctx)
  })
  pi.on("agent_start", async (_event: any, ctx: any) => {
    lastText = ""
    error = undefined
    await notify("UserPromptSubmit", ctx)
  })
  pi.on("message_end", (event: any) => {
    if (event.message.role !== "assistant") return
    lastText = event.message.content.filter((part: any) => part.type === "text")
      .map((part: any) => part.text).join("\n")
    error = event.message.stopReason === "error" ? event.message.errorMessage ?? "Pi request failed" : undefined
  })
  // agent_end may precede retries, compaction and queued turns. Only settled
  // means final idle in the installed Pi API.
  pi.on("agent_settled", async (_event: any, ctx: any) => {
    await notify(error ? "Error" : "Stop", ctx, error ? { error } : { last_assistant_message: lastText })
  })
  pi.on("tool_execution_end", async (_event: any, ctx: any) => { await notify("PostToolUse", ctx) })
  pi.on("ui_prompt_start", async (event: any, ctx: any) => {
    await notify("PermissionRequest", ctx, { tool_name: event.title ?? event.kind ?? "input" })
  })
  pi.on("ui_prompt_end", async (_event: any, ctx: any) => { await notify("PostToolUse", ctx) })
  pi.on("session_shutdown", async (_event: any, ctx: any) => { await notify("SessionShutdown", ctx) })
}
