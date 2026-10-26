import { Plugin } from "@opencode/plugin"
import { spawn } from "node:child_process"
import { fileURLToPath } from "node:url"
import { inspect } from "./shell"

const hook = fileURLToPath(new URL("../bin/opencode-nvim-hook", import.meta.url))

export default Plugin.define({
  id: "dotfiles.nvim",
  async setup(ctx) {
    const textOnly = ctx.options.text_only === true
    const readOnly = ctx.options.read_only === true
    if (ctx.options.gateway) await ctx.mcp.transform(editor => editor.set("tandem", ctx.options.gateway as any))
    if (ctx.options.gateway) await ctx.session.hook("prompt", async () => {
      const deadline = Date.now() + 15000
      while (true) {
        const tools = await ctx.tool.list()
        if (tools.some(tool => tool.id === "tandem_tandem_read_file")) break
        if (Date.now() >= deadline) throw new Error("Tandem MCP did not become ready; check :TandemStatus")
        await new Promise(resolve => setTimeout(resolve, 50))
      }
    })
    const allowed = new Set(textOnly ? [] : [
      "read", "glob", "grep", "webfetch", "websearch", "question",
      "nvim_shell",
      "tandem_tandem_read_file", "tandem_tandem_status",
      ...(readOnly ? [] : ["tandem_tandem_write_file"]),
    ])
    // Apply on every registry rebuild, including deferred MCP discovery. This
    // also prevents other MCP writers, subagents and shell tools bypassing Tandem.
    await ctx.tool.transform((editor) => {
      for (const tool of editor.list()) if (!allowed.has(tool.id)) editor.remove(tool.id)
      if (!textOnly) editor.add({
        name: "nvim_shell",
        options: { codemode: false },
        description: "Run a read-only Linux shell command for inspection. Filesystem writes and network access are unavailable. Use Tandem for edits.",
        input: { type: "object", properties: {
          command: { type: "string" },
          timeout: { type: "integer", minimum: 1, maximum: 120000 },
        }, required: ["command"], additionalProperties: false },
        execute: async (input, context) => {
          const { command, timeout } = input as { command: string, timeout?: number }
          return { content: await inspect(command, ctx.location.directory, context.signal, timeout) }
        },
      })
    })
    await ctx.session.hook("context", async (event) => {
      for (const name of Object.keys(event.tools)) if (!allowed.has(name)) delete event.tools[name]
      event.system.push({ type: "text", text: textOnly
        ? "Generate only the requested text. Do not use tools."
        : `Tandem project: ${ctx.options.root}. Use paths relative to this root. ` +
          (readOnly ? "Analysis-only Tandem session. Do not modify files. " :
            "For every edit use tandem_read_file then tandem_write_file with full content and expected_revision. ") +
          "Wait for unsaved human buffers. On busy retry after the human saves. " +
          "On stale_revision reread and regenerate; never attach a fresh revision to stale content. " +
          "On outcome_unknown reread before retrying. Native writes are unavailable; shell is read-only. " +
          "If Tandem is unavailable, report it and suggest :TandemStatus or :TandemReconnect."
      })
    })

    // Only managed interactive launches carry routing information. The route
    // file is reread by the hook on each event, allowing Neovim reattachment.
    if (textOnly || (!process.env.OPENCODE_NVIM_SERVER && !process.env.OPENCODE_NVIM_STATE_FILE)) return
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
