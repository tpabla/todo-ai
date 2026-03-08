import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  readFileSync,
  writeFileSync,
  unlinkSync,
  existsSync,
  mkdirSync,
} from "node:fs";

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

// Derive state dir from CWD (same hash as Lua's vim.fn.sha256)
function deriveStateDir(): string {
  const cwd = process.cwd();
  const hash = createHash("sha256").update(cwd).digest("hex").slice(0, 16);
  return `/tmp/todo-ai-${hash}`;
}

export default function (pi: ExtensionAPI) {
  // Auto-discover state dir: explicit env > derived from CWD
  const stateDir = process.env.TODO_AI_STATE_DIR || deriveStateDir();
  const tag = process.env.TODO_AI_TAG || "AGENT";

  // Ensure state dir exists
  try {
    mkdirSync(stateDir, { recursive: true });
  } catch {}

  // Write our tmux pane ID so Neovim can find us
  if (process.env.TMUX) {
    try {
      const paneId = execFileSync(
        "tmux",
        ["display-message", "-p", "#{pane_id}"],
        { encoding: "utf-8", timeout: 3000 }
      ).trim();
      writeFileSync(`${stateDir}/pane-id`, paneId);
    } catch {}
  }

  // Mutable — updated when Neovim (re)connects or disconnects
  let nvim: string | null = process.env.NVIM || null;

  const socketFile = `${stateDir}/nvim-socket`;
  const promptFile = `${stateDir}/prompt.md`;

  // Try state dir if no $NVIM env
  if (!nvim && existsSync(socketFile)) {
    nvim = readFileSync(socketFile, "utf-8").trim() || null;
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

  // Poll for socket changes (reconnection/disconnect) and prompt files
  const poll = setInterval(() => {
    // 1. Socket — detect (re)connect / disconnect
    if (existsSync(socketFile)) {
      try {
        const socket = readFileSync(socketFile, "utf-8").trim();
        if (socket && socket !== nvim) {
          nvim = socket;
          sessionCtx?.ui.setStatus("nvim", "🟢 nvim");
        }
      } catch {}
    } else if (nvim) {
      nvim = null;
      sessionCtx?.ui.setStatus("nvim", "🔴 nvim");
    }

    // 2. Prompt file — process prompts sent from Neovim
    if (existsSync(promptFile)) {
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
      "After ALL edits are complete, you MUST call the neovim tool with diff_review.",
      "Use open_file only when referencing specific code during conversation, not as a final step.",
      "Never skip diff_review — the user reviews changes in their editor.",
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
      "After ALL edits are complete, you MUST call neovim with diff_review.",
      "Use open_file when referencing specific code during conversation, not as a routine final step.",
      "Do NOT git commit. The user commits after reviewing the diff.",
    ],
    parameters: Type.Object({
      action: Type.String({ description: "'open_file' or 'diff_review'" }),
      path: Type.Optional(
        Type.String({ description: "File path (for open_file)" })
      ),
      line: Type.Optional(
        Type.Number({ description: "Line number (for open_file)" })
      ),
    }),
    async execute(toolCallId, params) {
      if (!nvim) return ok("Neovim not connected");
      try {
        if (params.action === "open_file") {
          if (!params.path) return ok("Error: path required");
          const safePath = params.path.replace(/'/g, "\\'");
          const line = params.line || 1;
          nvimExec(
            `require('todo-ai').remote_open('${safePath}', ${line})`
          );
          return ok(`Opened ${params.path} at line ${line}`);
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

  pi.on("session_start", async (_event, ctx) => {
    sessionCtx = ctx;
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
