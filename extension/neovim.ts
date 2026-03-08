import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { execFileSync } from "node:child_process";
import { readFileSync, unlinkSync, existsSync } from "node:fs";

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
  const nvim = process.env.NVIM;
  if (!nvim) return;

  const promptFile = process.env.TODO_AI_PROMPT;
  const tag = process.env.TODO_AI_TAG || "AGENT";

  function nvimExec(luaCode: string): void {
    const escaped = luaCode.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    execFileSync(
      "nvim",
      ["--server", nvim, "--remote-expr", `execute("lua ${escaped}")`],
      { timeout: 5000 }
    );
  }

  function nvimEval(luaExpr: string): string {
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

  // Poll for prompts sent from Neovim (visual selection, etc.)
  // Neovim does an atomic write (rename), so no partial reads.
  if (promptFile) {
    // Clean up stale file from a previous session
    if (existsSync(promptFile)) {
      try {
        unlinkSync(promptFile);
      } catch {}
    }
    const poll = setInterval(() => {
      if (!existsSync(promptFile)) return;
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
    }, 300);
    poll.unref();
  }

  // Inject live Neovim editor state before every prompt
  pi.on("before_agent_start", async (event) => {
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

    return {
      systemPrompt:
        event.systemPrompt +
        `\n\n<neovim_editor_state>\n${parts.join("\n\n")}\n</neovim_editor_state>`,
    };
  });

  // Tool: open files in Neovim editor, trigger diff review
  pi.registerTool({
    name: "neovim",
    label: "Neovim",
    description:
      "Interact with the host Neovim editor. Open files at specific lines or trigger a diff review of all changes.",
    promptGuidelines: [
      "After making file changes, call neovim with diff_review so the user can review.",
      "When referencing specific code, call neovim with open_file to show it in the editor.",
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

  // Auto-reload buffers in Neovim after pi edits files
  pi.on("tool_execution_end", async (event) => {
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
        pi.sendUserMessage(
          `Resolve these ${tag}: comments:\n\n${output}`
        );
      } else {
        ctx.ui.notify(`No ${tag}: comments found`, "info");
      }
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setStatus("nvim", "🟢 nvim");
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
