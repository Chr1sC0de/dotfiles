import { Plugin } from "@opencode/plugin"
import { spawn } from "node:child_process"
import { fileURLToPath } from "node:url"
import { run } from "./shell"

const hook = fileURLToPath(new URL("../bin/opencode-nvim-hook", import.meta.url))

export default Plugin.define({
  id: "dotfiles.nvim",
  async setup(ctx) {
    const textOnly = ctx.options.text_only === true
    const readOnly = ctx.options.read_only === true
    const tandem = ctx.options.tandem as { command: string, root: string, editor: string, state_home?: string } | undefined
    const shellEnv: Record<string, string> = tandem ? {
      TANDEM_ROOT: tandem.root, TANDEM_EDITOR: tandem.editor, TANDEM_BIN: tandem.command,
      ...(tandem.state_home ? { XDG_STATE_HOME: tandem.state_home } : {}),
    } : {}
    const allowed = new Set(textOnly ? [] : [
      "read", "glob", "grep", "webfetch", "websearch", "question",
      "nvim_shell",
    ])
    // Apply the session's tool set on every registry rebuild.
    await ctx.tool.transform((editor) => {
      for (const tool of editor.list()) if (!allowed.has(tool.id)) editor.remove(tool.id)
      if (!textOnly) editor.add({
        name: "nvim_shell",
        options: { codemode: false },
        description: readOnly
          ? "Run a read-only Linux shell command for inspection. Filesystem writes and network access are unavailable."
          : "Run a Linux shell command with the user's normal permissions, including filesystem writes, networking, and Docker access. Use for tests, builds, package installs, Git, and filesystem operations. Prefer Tandem for source edits to coordinate with Neovim buffers.",
        input: { type: "object", properties: {
          command: { type: "string" },
          timeout: { type: "integer", minimum: 1, maximum: 120000 },
        }, required: ["command"], additionalProperties: false },
        execute: async (input, context) => {
          const { command, timeout } = input as { command: string, timeout?: number }
          return { content: await run(command, ctx.location.directory, context.signal, timeout, readOnly, shellEnv) }
        },
      })
    })
    await ctx.session.hook("context", async (event) => {
      for (const name of Object.keys(event.tools)) if (!allowed.has(name)) delete event.tools[name]
      event.system.push({ type: "text", text: textOnly
        ? "Generate only the requested text. Do not use tools."
        : `Tandem project: ${ctx.options.root}. Use paths relative to this root. ` +
          'Invoke the CLI directly through nvim_shell as "$TANDEM_BIN"; TANDEM_ROOT and TANDEM_EDITOR select this workspace and editor. ' +
          (readOnly ? "Analysis-only session. Do not modify files or buffers, including through Tandem. The filesystem shell is read-only and network-isolated, but Tandem writes are not technically blocked. " :
            "Shell commands have the user's normal filesystem and network permissions, including Docker access. " +
            "Use the shell for tests, builds, package installs, Git, and filesystem operations. " +
            "Prefer Tandem for source edits. ") +
          'Use "$TANDEM_BIN" buffers, read PATH (or read --buffer ID), then write PATH --expect REVISION --content-file - with full replacement text on stdin. ' +
          "Reads include unsaved edits; writes merge compatible concurrent changes and leave buffers unsaved. Do not save without user authorization. Disk tools, tests and Git only see saved content. " +
          "On merge_conflict or snapshot_expired reread and reconsider; never attach a fresh revision to stale content. " +
          'On outcome_unknown run "$TANDEM_BIN" outcome ATTEMPT_ID and inspect the buffer; never blindly replay the write. ' +
          "Reading a path loads its Neovim buffer if needed. If unavailable, report it and suggest :TandemStatus."
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
