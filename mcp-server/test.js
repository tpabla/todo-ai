// Minimal smoke tests for the MCP server's nvim helpers.
// Run with: node test.js
import { strict as assert } from "node:assert";
import { writeFileSync, mkdtempSync, mkdirSync, symlinkSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { findLineForSearch } from "./nvim.js";
import {
  normalize,
  toAbsolute,
  isAncestor,
  listEditors,
  resolveEditor,
  REGISTRY_DIR,
} from "../shared/pairing.js";

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ok  ${name}`);
    passed++;
  } catch (e) {
    console.log(`  FAIL ${name}`);
    console.log(`       ${e.message}`);
    failed++;
  }
}

console.log("nvim helpers");

test("findLineForSearch finds matching line", () => {
  const dir = mkdtempSync(join(tmpdir(), "mcp-test-"));
  const file = join(dir, "sample.txt");
  try {
    writeFileSync(file, "first\nsecond\ntarget line\nfourth\n");
    assert.equal(findLineForSearch(file, "target"), 3);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("findLineForSearch returns null on no match", () => {
  const dir = mkdtempSync(join(tmpdir(), "mcp-test-"));
  const file = join(dir, "sample.txt");
  try {
    writeFileSync(file, "nothing\nto see\nhere\n");
    assert.equal(findLineForSearch(file, "absent"), null);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("findLineForSearch returns null on missing file", () => {
  assert.equal(findLineForSearch("/nonexistent/file.txt", "x"), null);
});

// Registry sandbox: a temp registry dir with TODO_AI_SOCKET / TMUX_PANE under
// test control, so a test run inside a real tmux pane cannot skew the result.
function withRegistry(env, fn) {
  const saved = {};
  for (const key of ["TODO_AI_SOCKET", "TMUX_PANE"]) {
    saved[key] = process.env[key];
    if (env[key] === undefined) delete process.env[key];
    else process.env[key] = env[key];
  }
  const dir = mkdtempSync(join(tmpdir(), "reg-"));
  try {
    return fn(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function writeEditor(dir, id, entry) {
  mkdirSync(join(dir, id), { recursive: true });
  writeFileSync(join(dir, id, "editor.json"),
    JSON.stringify({ pid: process.pid, ...entry }));
}

console.log("\npairing");

test("toAbsolute resolves against the agent cwd, not the editor cwd", () => {
  assert.equal(toAbsolute("src/foo.lua", "/proj/thing"), "/proj/thing/src/foo.lua");
});

test("toAbsolute passes absolute paths through", () => {
  assert.equal(toAbsolute("/etc/hosts", "/proj/thing"), "/etc/hosts");
});

test("isAncestor respects component boundaries", () => {
  assert.equal(isAncestor("/a/b", "/a/b/c"), true);
  assert.equal(isAncestor("/a/b", "/a/b"), true);
  assert.equal(isAncestor("/a/b", "/a/bc"), false);
  assert.equal(isAncestor("/a/b/c", "/a/b"), false);
});

test("resolveEditor prefers an explicit TODO_AI_SOCKET pin over ancestry", () => {
  const prev = process.env.TODO_AI_SOCKET;
  process.env.TODO_AI_SOCKET = "/tmp/pinned.sock";
  try {
    assert.equal(resolveEditor("/proj/thing").socket, "/tmp/pinned.sock");
  } finally {
    if (prev === undefined) delete process.env.TODO_AI_SOCKET;
    else process.env.TODO_AI_SOCKET = prev;
  }
});

test("resolveEditor returns null when the registry is empty", () => {
  const prev = process.env.TODO_AI_SOCKET;
  delete process.env.TODO_AI_SOCKET;
  const dir = mkdtempSync(join(tmpdir(), "reg-empty-"));
  try {
    assert.equal(resolveEditor("/proj/thing", dir), null);
  } finally {
    rmSync(dir, { recursive: true, force: true });
    if (prev !== undefined) process.env.TODO_AI_SOCKET = prev;
  }
});

test("resolveEditor ignores an editor outside the agent's tree", () => {
  // Opening files in an unrelated project's editor is worse than none.
  const prev = process.env.TODO_AI_SOCKET;
  delete process.env.TODO_AI_SOCKET;
  const dir = mkdtempSync(join(tmpdir(), "reg-unrelated-"));
  try {
    mkdirSync(join(dir, "300"), { recursive: true });
    writeFileSync(join(dir, "300", "editor.json"), JSON.stringify({
      socket: "/tmp/other.sock", cwd: "/somewhere/else", pid: process.pid,
    }));
    assert.equal(resolveEditor("/proj/thing", dir), null);
  } finally {
    rmSync(dir, { recursive: true, force: true });
    if (prev !== undefined) process.env.TODO_AI_SOCKET = prev;
  }
});

test("resolveEditor matches across a symlinked path", () => {
  const prev = process.env.TODO_AI_SOCKET;
  delete process.env.TODO_AI_SOCKET;
  const base = mkdtempSync(join(tmpdir(), "reg-link-"));
  const dir = join(base, "registry");
  try {
    mkdirSync(join(base, "actual", "repo-b"), { recursive: true });
    symlinkSync(join(base, "actual"), join(base, "link"));
    mkdirSync(join(dir, "400"), { recursive: true });
    writeFileSync(join(dir, "400", "editor.json"), JSON.stringify({
      socket: "/tmp/linked.sock",
      cwd: join(base, "actual", "repo-b"),
      pid: process.pid,
    }));
    // Agent reports the symlinked spelling; the editor reports the real one.
    assert.equal(resolveEditor(join(base, "link"), dir).socket, "/tmp/linked.sock");
  } finally {
    rmSync(base, { recursive: true, force: true });
    if (prev !== undefined) process.env.TODO_AI_SOCKET = prev;
  }
});

test("resolveEditor picks the nearest related editor", () => {
  const prev = process.env.TODO_AI_SOCKET;
  delete process.env.TODO_AI_SOCKET;
  const dir = mkdtempSync(join(tmpdir(), "reg-near-"));
  try {
    // Agent sits at /proj/thing; two editors below it, one deeper than the other.
    mkdirSync(join(dir, "100"), { recursive: true });
    mkdirSync(join(dir, "200"), { recursive: true });
    writeFileSync(join(dir, "100", "editor.json"), JSON.stringify({
      socket: "/tmp/far.sock", cwd: "/proj/thing/repo-b/deep/deeper", pid: process.pid,
    }));
    writeFileSync(join(dir, "200", "editor.json"), JSON.stringify({
      socket: "/tmp/near.sock", cwd: "/proj/thing/repo-b", pid: process.pid,
    }));
    assert.equal(resolveEditor("/proj/thing/repo-b", dir).socket, "/tmp/near.sock");
  } finally {
    rmSync(dir, { recursive: true, force: true });
    if (prev !== undefined) process.env.TODO_AI_SOCKET = prev;
  }
});

test("resolveEditor prefers the editor connected to this pane over a nearer one", () => {
  withRegistry({ TMUX_PANE: "%7" }, (dir) => {
    writeEditor(dir, "100", { socket: "/tmp/near.sock", cwd: "/proj/thing/repo-b" });
    writeEditor(dir, "200", { socket: "/tmp/joined.sock", cwd: "/proj/thing", pane: "%7" });
    assert.equal(resolveEditor("/proj/thing/repo-b", dir).socket, "/tmp/joined.sock");
  });
});

test("resolveEditor honours a pane connection from an unrelated directory", () => {
  // The whole point of an explicit connect: the user picked this editor by
  // hand, so ancestry -- which would drop it as UNRELATED -- does not apply.
  withRegistry({ TMUX_PANE: "%7" }, (dir) => {
    writeEditor(dir, "100", { socket: "/tmp/joined.sock", cwd: "/somewhere/else", pane: "%7" });
    assert.equal(resolveEditor("/proj/thing", dir).socket, "/tmp/joined.sock");
  });
});

test("resolveEditor prefers a TODO_AI_SOCKET pin over a pane connection", () => {
  withRegistry({ TODO_AI_SOCKET: "/tmp/pinned.sock", TMUX_PANE: "%7" }, (dir) => {
    writeEditor(dir, "100", { socket: "/tmp/joined.sock", cwd: "/proj/thing", pane: "%7" });
    assert.equal(resolveEditor("/proj/thing", dir).socket, "/tmp/pinned.sock");
  });
});

test("resolveEditor falls back to ancestry when no editor claims this pane", () => {
  withRegistry({ TMUX_PANE: "%7" }, (dir) => {
    writeEditor(dir, "100", { socket: "/tmp/near.sock", cwd: "/proj/thing" });
    writeEditor(dir, "200", { socket: "/tmp/other.sock", cwd: "/proj/thing", pane: "%9" });
    assert.equal(resolveEditor("/proj/thing", dir).socket, "/tmp/near.sock");
  });
});

test("resolveEditor ignores pane connections when not running under tmux", () => {
  withRegistry({}, (dir) => {
    writeEditor(dir, "100", { socket: "/tmp/joined.sock", cwd: "/somewhere/else", pane: "%7" });
    writeEditor(dir, "200", { socket: "/tmp/near.sock", cwd: "/proj/thing" });
    assert.equal(resolveEditor("/proj/thing", dir).socket, "/tmp/near.sock");
  });
});

test("resolveEditor skips a dead editor holding this pane", () => {
  withRegistry({ TMUX_PANE: "%7" }, (dir) => {
    // pid 1 is alive but not ours; use a pid that cannot exist instead.
    writeEditor(dir, "100", { socket: "/tmp/dead.sock", cwd: "/proj/thing", pane: "%7", pid: 2 ** 31 - 1 });
    writeEditor(dir, "200", { socket: "/tmp/live.sock", cwd: "/proj/thing" });
    assert.equal(resolveEditor("/proj/thing", dir).socket, "/tmp/live.sock");
  });
});

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
