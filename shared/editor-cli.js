#!/usr/bin/env node
// Thin CLI over shared/pairing.js so shell hooks resolve an editor through the
// same ancestry logic as the MCP server and the pi extension, rather than
// reimplementing it in bash.
//
//   editor-cli.js socket [cwd]   -> prints the paired nvim socket, exit 1 if none
//   editor-cli.js abs <path>     -> prints the path resolved against cwd
import { resolveEditor, toAbsolute } from "./pairing.js";

const [command, ...args] = process.argv.slice(2);

if (command === "socket") {
  const editor = resolveEditor(args[0] || process.cwd());
  if (!editor || !editor.socket) process.exit(1);
  process.stdout.write(editor.socket);
} else if (command === "abs") {
  if (!args[0]) process.exit(1);
  process.stdout.write(toAbsolute(args[0], args[1]) || "");
} else {
  process.stderr.write(`unknown command: ${command}\n`);
  process.exit(2);
}
