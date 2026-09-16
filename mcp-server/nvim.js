// Helpers for talking to a running Neovim instance via --remote-expr.
// Pairing/path logic lives in ../shared/pairing.js so the pi extension and
// this server cannot drift apart.
import { execFileSync } from "node:child_process";
import { resolveEditor } from "../shared/pairing.js";

export function getNvimSocket() {
  const editor = resolveEditor();
  return editor ? editor.socket : null;
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
