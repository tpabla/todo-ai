import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { execFileSync } from "node:child_process";
import { readFileSync, unlinkSync, existsSync, mkdirSync } from "node:fs";
// Pairing/path logic is shared with the Claude Code MCP server so the two
// harness integrations cannot drift apart.
import { resolveEditor, toAbsolute, tagPane } from "../shared/pairing.js";

interface NeovimContext {
  current_file?: string;
  cursor_line?: number;
  open_files: string[];
  diagnostics?: Array<{
    line: number;
    severity: string;
    message: string;
  }>;
}

export default function (pi: ExtensionAPI) {
  const tag = process.env.TODO_AI_TAG || "AGENT";

  // Tag this pane so the Neovim plugin can offer it in the connect picker.
  tagPane({ agent: "pi", name: process.env.TODO_AI_NAME });

  // Pair with an editor by ancestry: it may be in a subdirectory of this
  // agent's cwd (a worktree) rather than the same directory.
  let editor = resolveEditor();
  let nvim: string | null = process.env.NVIM || (editor ? editor.socket : null);

  // Prompts are dropped in the editor's own session dir.
  let sessionDir: string | null =
    process.env.TODO_AI_SESSION_DIR || (editor ? editor.dir : null);
  if (sessionDir) {
    try {
      mkdirSync(sessionDir, { recursive: true });
    } catch {}
  }

  function nvimExec(luaCode: string): void {
    if (!nvim) throw new Error("Neovim not connected");
    const escaped = luaCode.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    execFileSync(
      "nvim",
      ["--server", nvim, "--remote-expr", `execute("lua ${escaped}")`],
      { timeout: 5000 }
    );
  }

  function nvimEval(luaExpr: string): string {
    if (!nvim) throw new Error("Neovim not connected");
    const escaped = luaExpr.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    return execFileSync(
      "nvim",
      ["--server", nvim, "--remote-expr", `luaeval("${escaped}")`],
      { timeout: 3000, encoding: "utf-8" }
    ).trim();
  }

  function getContext(): NeovimContext | null {
    try {
      return JSON.parse(nvimEval("require('todo-ai').remote_get_context()"));
    } catch {
      return null;
    }
  }

  // Session context for status updates outside event handlers
  let sessionCtx: {
    ui: {
      setStatus: (id: string, text: string) => void;
      notify: (msg: string, level: string) => void;
    };
  } | null = null;

  // Poll for editor changes (reconnection/disconnect) and prompt files
  const poll = setInterval(() => {
    // 1. Re-resolve the editor — detect (re)connect / disconnect
    editor = resolveEditor();
    const socket = editor ? editor.socket : null;
    if (socket !== nvim) {
      nvim = socket;
      sessionDir = editor ? editor.dir : sessionDir;
      sessionCtx?.ui.setStatus("nvim", nvim ? "🟢 nvim" : "🔴 nvim");
    }

    // 2. Prompt file — process prompts sent from Neovim
    const promptFile = sessionDir ? `${sessionDir}/prompt.md` : null;
    if (promptFile && existsSync(promptFile)) {
      try {
        const text = readFileSync(promptFile, "utf-8").trim();
        unlinkSync(promptFile);
        if (text === "__SCAN__") {
          const output = grepTag(tag);
          if (output) {
            pi.sendUserMessage(
              `Resolve these ${tag}: comments:\n\n${output}`
            );
          }
        } else if (text) {
          pi.sendUserMessage(text);
        }
      } catch {}
    }
  }, 500);
  poll.unref();

  // Inject editor state and workflow rules before every prompt
  pi.on("before_agent_start", async (event) => {
    if (!nvim) return;

    const ctx = getContext();
    if (!ctx) return;

    const parts: string[] = [];

    if (ctx.current_file) {
      parts.push(
        `Current file: ${ctx.current_file} (line ${ctx.cursor_line || 1})`
      );
    }

    if (ctx.open_files.length > 0) {
      parts.push(
        `Open buffers:\n${ctx.open_files.map((f) => `  ${f}`).join("\n")}`
      );
    }

    if (ctx.diagnostics && ctx.diagnostics.length > 0) {
      parts.push(
        `LSP diagnostics:\n${ctx.diagnostics
          .map((d) => `  Line ${d.line}: [${d.severity}] ${d.message}`)
          .join("\n")}`
      );
    }

    if (parts.length === 0) return;

    const workflow = [
      "Use open_file only when referencing specific code during conversation.",
      "Use diff_review only when the user asks to see the diff.",
      "Do NOT commit changes (no git commit). The user reviews the diff and commits themselves.",
    ].join("\n");

    return {
      systemPrompt:
        event.systemPrompt +
        `\n\n<neovim_editor_state>\n${parts.join("\n\n")}\n</neovim_editor_state>` +
        `\n\n<neovim_workflow>\n${workflow}\n</neovim_workflow>`,
    };
  });

  // Tool: open files and trigger diff review in Neovim
  pi.registerTool({
    name: "neovim",
    label: "Neovim",
    description:
      "Interact with the host Neovim editor. Open files at specific lines or trigger a diff review of all changes.",
    promptGuidelines: [
      "Use open_file when referencing specific code during conversation.",
      "Use diff_review only when the user asks to see the diff.",
      "Do NOT git commit. The user commits after reviewing the diff.",
    ],
    parameters: Type.Object({
      action: Type.String({ description: "'open_file' or 'diff_review'" }),
      path: Type.Optional(
        Type.String({ description: "File path, absolute or relative to this agent's cwd (for open_file)" })
      ),
      line: Type.Optional(
        Type.Number({ description: "Line number (for open_file)" })
      ),
      search: Type.Optional(
        Type.String({
          description:
            "Pattern to search for after opening (jumps to first match, more reliable than line numbers)",
        })
      ),
    }),
    async execute(toolCallId, params) {
      if (!nvim) return ok("Neovim not connected");
      try {
        if (params.action === "open_file") {
          if (!params.path) return ok("Error: path required");
          // The editor may sit in a different directory, so it refuses
          // relative paths -- resolve against this agent's cwd first.
          const absPath = toAbsolute(params.path)!;
          const safePath = absPath.replace(/'/g, "\\'");
          let line = params.line || 1;

          // Search for pattern to find accurate line number
          if (params.search) {
            try {
              const out = execFileSync(
                "grep",
                ["-n", "-m", "1", "-F", params.search, absPath],
                { encoding: "utf-8", timeout: 3000 }
              );
              const match = out.match(/^(\d+):/);
              if (match) line = parseInt(match[1], 10);
            } catch {}
          }

          nvimExec(
            `require('todo-ai').remote_open('${safePath}', ${line})`
          );
          return ok(`Opened ${absPath} at line ${line}`);
        }

        if (params.action === "diff_review") {
          nvimExec("require('todo-ai').remote_diff_review()");
          return ok("Opened diff review in Neovim");
        }

        return ok(`Unknown action: ${params.action}`);
      } catch (e: any) {
        return ok(`Error: ${e.message || e}`);
      }
    },
  });

  // Auto-reload buffers after pi edits files
  pi.on("tool_execution_end", async (event) => {
    if (!nvim) return;
    if (event.toolName === "edit" || event.toolName === "write") {
      try {
        nvimExec("vim.cmd('checktime')");
      } catch {}
    }
  });

  // /scan — find AGENT: comments and resolve them
  pi.registerCommand("scan", {
    description: `Find ${tag}: comments in the project and resolve them`,
    handler: async (args, ctx) => {
      const output = grepTag(tag);
      if (output) {
        pi.sendUserMessage(`Resolve these ${tag}: comments:\n\n${output}`);
      } else {
        ctx.ui.notify(`No ${tag}: comments found`, "info");
      }
    },
  });

  pi.on("session_start", async (event: any, ctx) => {
    sessionCtx = ctx;
    // Re-tag with the session id now that it is known, so the editor's
    // picker can show which conversation a pane holds.
    tagPane({
      agent: "pi",
      sessionId: event?.sessionId ?? event?.session?.id,
      name: process.env.TODO_AI_NAME,
    });
    ctx.ui.setStatus("nvim", nvim ? "🟢 nvim" : "🔴 nvim");
  });
}

// Prefer rg (respects .gitignore), fall back to grep
function grepTag(tag: string): string {
  const pattern = `${tag}:`;
  try {
    return execFileSync("rg", ["-n", pattern, "."], {
      timeout: 10000,
      encoding: "utf-8",
    }).trim();
  } catch (e: any) {
    if (e.code !== "ENOENT") return ""; // rg exists but no matches
  }
  try {
    return execFileSync(
      "grep",
      ["-rn", pattern, ".", "--exclude-dir=node_modules", "--exclude-dir=.git"],
      { timeout: 10000, encoding: "utf-8" }
    ).trim();
  } catch {
    return "";
  }
}

function ok(text: string) {
  return { content: [{ type: "text" as const, text }], details: {} };
}
