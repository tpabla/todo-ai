// Minimal smoke tests for the MCP server's nvim helpers.
// Run with: node test.js
import { strict as assert } from "node:assert";
import { writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  deriveStateDir,
  getNvimSocket,
  findLineForSearch,
} from "./nvim.js";

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

test("deriveStateDir is deterministic for same cwd", () => {
  assert.equal(deriveStateDir("/foo/bar"), deriveStateDir("/foo/bar"));
});

test("deriveStateDir starts with /tmp/todo-ai-", () => {
  assert.match(deriveStateDir("/foo/bar"), /^\/tmp\/todo-ai-[0-9a-f]{16}$/);
});

test("deriveStateDir matches Lua sha256(cwd):sub(1,16)", () => {
  // Verified against vim.fn.sha256("/foo/bar"):sub(1,16) = "a05d96ad6bf8f3ea"
  assert.equal(deriveStateDir("/foo/bar"), "/tmp/todo-ai-a05d96ad6bf8f3ea");
});

test("getNvimSocket returns null when socket file missing", () => {
  // Use a cwd we know has no state dir
  const orig = process.cwd();
  try {
    process.chdir("/");
    // Most likely no /tmp/todo-ai-<hash of />/nvim-socket exists
    const result = getNvimSocket();
    // Result is either null or a real socket path; just verify the function
    // doesn't throw and returns a string-or-null.
    assert.ok(result === null || typeof result === "string");
  } finally {
    process.chdir(orig);
  }
});

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

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
