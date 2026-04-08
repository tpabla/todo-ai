#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  deriveStateDir,
  getNvimSocket,
  nvimExec,
  nvimEval,
  findLineForSearch,
} from "./nvim.js";

const server = new McpServer({
  name: "todo-ai-neovim",
  version: "1.0.0",
});

server.tool(
  "neovim_open_file",
  "Open a file in the connected Neovim editor at a specific line or search pattern. Use this when referencing specific code so the user can see it in their editor.",
  {
    path: z.string().describe("File path to open (absolute or relative to cwd)"),
    line: z.number().int().positive().optional().describe("Line number to jump to"),
    search: z.string().optional().describe("Pattern to search for (overrides line if found — more reliable than line numbers)"),
  },
  async ({ path, line, search }) => {
    const socket = getNvimSocket();
    if (!socket) {
      return { content: [{ type: "text", text: "Neovim not connected" }] };
    }

    let targetLine = line || 1;
    if (search) {
      const found = findLineForSearch(path, search);
      if (found) targetLine = found;
    }

    try {
      const safePath = path.replace(/'/g, "\\'");
      nvimExec(socket, `require('todo-ai').remote_open('${safePath}', ${targetLine})`);
      return { content: [{ type: "text", text: `Opened ${path} at line ${targetLine}` }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }] };
    }
  }
);

server.tool(
  "neovim_diff_review",
  "Trigger a git diff review in Neovim using DiffviewOpen. Use only when the user asks to see the diff.",
  {},
  async () => {
    const socket = getNvimSocket();
    if (!socket) {
      return { content: [{ type: "text", text: "Neovim not connected" }] };
    }
    try {
      nvimExec(socket, "require('todo-ai').remote_diff_review()");
      return { content: [{ type: "text", text: "Opened diff review in Neovim" }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }] };
    }
  }
);

server.tool(
  "neovim_get_context",
  "Get current Neovim editor state: active file, cursor position, open buffers, LSP diagnostics. Call this at the start of a task to understand what the user is looking at.",
  {},
  async () => {
    const socket = getNvimSocket();
    if (!socket) {
      return { content: [{ type: "text", text: "Neovim not connected" }] };
    }
    try {
      const json = nvimEval(socket, "require('todo-ai').remote_get_context()");
      return { content: [{ type: "text", text: json }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }] };
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Fatal MCP server error:", err);
  process.exit(1);
});
