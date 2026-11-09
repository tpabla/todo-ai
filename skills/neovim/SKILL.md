---
name: neovim
description: Show code in the user's Neovim and read what they are looking at or have selected. Use when the user says "this", "here", "the selection", asks what some code does, or when walking them through code.
allowed-tools: "Bash(todo-ai:*)"
---

The user pairs with you from Neovim. `todo-ai` drives their editor.

- `todo-ai context` — their current file, cursor, last visual selection (with its line range), open buffers, diagnostics. Run it when they refer to code without naming it ("this", "here", "the selection").
- `todo-ai open <path>[:a[-b]]` — show a file, highlighting lines a..b. Run it before you explain or change specific code, so they see what you mean.
- `todo-ai diff` — open the diff review. Only when they ask to see the diff.

When walking through code, show one stop per turn: `open` the location with a range covering everything you are about to explain, explain it, then stop. Wait for the user to say to move on before opening the next stop. Never chain several `open` calls in one turn.

If `todo-ai` reports more than one editor, tell the user to run `:TodoAI` in the editor they want.

Never run `git commit` or any git write command. The user reviews the diff and commits.
