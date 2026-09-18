// Editor pairing, shared by every harness integration (the MCP server for
// Claude Code, the pi extension). The agent's cwd and nvim's cwd may sit at
// different depths of the same tree -- agent above, nvim below in a worktree --
// so pairing is by ancestry, not by a shared sha256(cwd) hash.
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { isAbsolute, join, resolve, sep } from "node:path";
import { homedir } from "node:os";

export const REGISTRY_DIR = "/tmp/todo-ai/sessions";

// Expand ~ and collapse redundant/trailing slashes. Symlinks are left alone so
// paths stay comparable with what the editor reports.
export function normalize(p) {
  if (!p) return null;
  let out = p.startsWith("~") ? homedir() + p.slice(1) : p;
  out = out.replace(/\/{2,}/g, "/").replace(/(.)\/+$/, "$1");
  return out;
}

// Resolve p against base. Paths sent to nvim are always absolute -- nvim must
// never resolve them against its own cwd, which may be a different directory.
export function toAbsolute(p, base = process.cwd()) {
  const n = normalize(p);
  if (!n) return null;
  if (isAbsolute(n)) return n;
  return normalize(resolve(normalize(base), n));
}

// Canonical form for comparison only: resolves symlinks when the path exists,
// so a tmux-reported /var/... and an nvim-reported /private/var/... compare
// equal on darwin.
export function real(p) {
  const n = normalize(p);
  if (!n) return null;
  try {
    return normalize(realpathSync(n));
  } catch {
    return n;
  }
}

// Component-boundary containment; equal paths count as ancestors.
export function isAncestor(ancestor, descendant) {
  const a = real(ancestor);
  const d = real(descendant);
  if (!a || !d) return false;
  if (a === d) return true;
  if (a === sep) return d.startsWith(sep);
  return d.startsWith(a + sep);
}

// Components between ancestor and descendant; null when unrelated.
export function distance(ancestor, descendant) {
  if (!isAncestor(ancestor, descendant)) return null;
  const a = real(ancestor);
  const d = real(descendant);
  if (a === d) return 0;
  return d.slice(a.length + 1).split(sep).filter(Boolean).length;
}

function alive(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

// Live editor entries, pruning stale ones from disk.
export function listEditors(registryDir = REGISTRY_DIR) {
  if (!existsSync(registryDir)) return [];
  const entries = [];
  for (const name of readdirSync(registryDir)) {
    const dir = join(registryDir, name);
    try {
      const entry = JSON.parse(readFileSync(join(dir, "editor.json"), "utf-8"));
      if (alive(entry.pid)) {
        entries.push({ ...entry, dir: entry.dir || dir });
        continue;
      }
    } catch {}
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {}
  }
  return entries;
}

const EXACT = 0, DESCENDANT = 1, ANCESTOR = 2, UNRELATED = 3;

// From the agent's perspective an editor is usually *below* it, so a nearer
// descendant outranks an enclosing one.
function rank(agentCwd, editorCwd) {
  const down = distance(agentCwd, editorCwd);
  if (down === 0) return [EXACT, 0];
  if (down !== null) return [DESCENDANT, down];
  const up = distance(editorCwd, agentCwd);
  if (up !== null) return [ANCESTOR, up];
  return [UNRELATED, 0];
}

// The editor to talk to: an explicit TODO_AI_SOCKET pin always wins, then the
// editor that connected itself to this pane, then the nearest editor related to
// cwd by ancestry, else null.
export function resolveEditor(
  cwd = process.cwd(),
  registryDir = REGISTRY_DIR,
  pane = process.env.TMUX_PANE
) {
  if (process.env.TODO_AI_SOCKET) {
    return {
      socket: process.env.TODO_AI_SOCKET,
      dir: process.env.TODO_AI_SESSION_DIR || null,
      pinned: true,
    };
  }

  const editors = listEditors(registryDir);

  // An editor that named this pane was pointed here by hand, so it outranks
  // ancestry entirely -- including the UNRELATED filter below, which would
  // otherwise drop an editor sitting outside the agent's tree.
  if (pane) {
    const connected = editors.find((entry) => entry.pane && entry.pane === pane);
    if (connected) return connected;
  }

  const ranked = editors
    .map((entry) => {
      const [bucket, dist] = rank(cwd, entry.cwd);
      return { entry, bucket, dist };
    })
    // An editor outside this agent's tree is not a fallback: opening files in
    // an unrelated project's editor is worse than reporting none.
    .filter((r) => r.bucket !== UNRELATED)
    .sort((a, b) => a.bucket - b.bucket || a.dist - b.dist);

  return ranked.length ? ranked[0].entry : null;
}

// Tag the running pane so the editor can discover this agent. Best-effort:
// tagging failure must never break the agent.
export function tagPane({ agent, cwd = process.cwd(), sessionId, name }) {
  const pane = process.env.TMUX_PANE;
  if (!process.env.TMUX || !pane) return false;
  const options = {
    "@todo-ai-agent": agent,
    "@todo-ai-dir": normalize(cwd),
    "@todo-ai-session": sessionId,
    "@todo-ai-name": name,
  };
  for (const [key, value] of Object.entries(options)) {
    if (!value) continue;
    try {
      execFileSync("tmux", ["set-option", "-p", "-t", pane, key, String(value)], {
        timeout: 3000,
      });
    } catch {}
  }
  return true;
}
