// Helpers for talking to a running Neovim instance via --remote-expr.
// Pulled out of server.js so they can be unit-tested in isolation.
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

// Derive state dir from CWD — must match Lua's vim.fn.sha256(cwd):sub(1, 16)
export function deriveStateDir(cwd = process.cwd()) {
  const hash = createHash("sha256").update(cwd).digest("hex").slice(0, 16);
  return `/tmp/todo-ai-${hash}`;
}

export function getNvimSocket() {
  const socketFile = `${deriveStateDir()}/nvim-socket`;
  if (!existsSync(socketFile)) return null;
  const socket = readFileSync(socketFile, "utf-8").trim();
  return socket || null;
}

export function nvimExec(socket, luaCode) {
  const escaped = luaCode.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  execFileSync(
    "nvim",
    ["--server", socket, "--remote-expr", `execute("lua ${escaped}")`],
    { timeout: 5000 }
  );
}

export function nvimEval(socket, luaExpr) {
  const escaped = luaExpr.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  return execFileSync(
    "nvim",
    ["--server", socket, "--remote-expr", `luaeval("${escaped}")`],
    { timeout: 3000, encoding: "utf-8" }
  ).trim();
}

// Find first line matching `search` in `path`. Returns null on no match / error.
export function findLineForSearch(path, search) {
  try {
    const out = execFileSync("grep", ["-n", "-m", "1", "-F", search, path], {
      encoding: "utf-8",
      timeout: 3000,
    });
    const match = out.match(/^(\d+):/);
    return match ? parseInt(match[1], 10) : null;
  } catch {
    return null;
  }
}
