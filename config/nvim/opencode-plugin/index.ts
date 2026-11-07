import { Plugin } from "@opencode/plugin"
import { spawn } from "node:child_process"
import { fileURLToPath } from "node:url"

const hook = fileURLToPath(new URL("../bin/opencode-nvim-hook", import.meta.url))

export default Plugin.define({
  id: "dotfiles.nvim",
  async setup(ctx) {
    // Only managed interactive launches carry routing information. The route
    // file is reread by the hook on each event, allowing Neovim reattachment.
    if (!process.env.OPENCODE_NVIM_SERVER && !process.env.OPENCODE_NVIM_STATE_FILE) return
    let notifications = Promise.resolve()
    const notify = (event: { hook_event_name: string, [key: string]: unknown }) => {
      notifications = notifications.then(() => new Promise<void>((resolve) => {
        const status = event.hook_event_name === "PermissionRequest" ? "waiting"
          : ["Stop", "Error"].includes(event.hook_event_name) ? "done" : "working"
        const child = spawn("bash", [hook, status], { stdio: ["pipe", "ignore", "ignore"], timeout: 3000 })
        child.on("error", () => resolve())
        child.on("close", () => resolve())
        child.stdin.on("error", () => {})
        child.stdin.end(JSON.stringify(event))
      }))
      return notifications
    }
    const sessions = new Set<string>()
    const lastText = new Map<string, string>()
    await ctx.session.hook("prompt", async (event) => {
      sessions.add(event.sessionID)
      lastText.delete(event.sessionID)
      await notify({ hook_event_name: "UserPromptSubmit", session_id: event.sessionID })
    })
    const controller = new AbortController()
    void (async () => {
      for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
        const data = event.data as Record<string, any>
        const id = data.sessionID ?? data.form?.sessionID ?? data.request?.sessionID
        if (!sessions.has(id)) continue
        const base = { session_id: id, turn_id: event.id }
        if (event.type === "session.text.ended") lastText.set(id, data.text)
        if (event.type === "session.execution.succeeded" || event.type === "session.execution.interrupted")
          await notify({ ...base, hook_event_name: "Stop", last_assistant_message: lastText.get(id) ?? "" })
        if (event.type === "session.execution.failed")
          await notify({ ...base, hook_event_name: "Error", error: JSON.stringify(data.error) })
        if (event.type === "permission.asked" || event.type === "form.created")
          await notify({ ...base, hook_event_name: "PermissionRequest", tool_name: data.title ?? data.form?.title ?? "input" })
        if (event.type === "permission.replied" || event.type === "form.replied")
          await notify({ ...base, hook_event_name: "PostToolUse" })
      }
    })().catch(() => {})
    return () => controller.abort()
  },
})
