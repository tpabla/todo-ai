---
name: neovim
description: Show code in the user's Neovim and read what they are looking at or have selected. Use when the user says "this", "here", "the selection", asks what some code does, or when walking them through code.
allowed-tools: "Bash(todo-ai:*)"
---

The user pairs with you from Neovim. `todo-ai` drives their editor.

- `todo-ai context` — their current file, cursor, last visual selection (with its line range), open buffers, diagnostics. Run it when they refer to code without naming it ("this", "here", "the selection").
- `todo-ai open <path>[:a[-b]]` — show a file, highlighting lines a..b. Run it before you explain or change specific code, so they see what you mean.
- `todo-ai diff` — open the diff review. Only when they ask to see the diff.
- `todo-ai slides <deck.md>` — show a deck in a split above the code; each slide shows its code below. Use it for overviews and architecture; use `open` for one-off questions.

When walking through code, show one stop per turn: `open` the location with a range covering everything you are about to explain, explain it, then stop. Wait for the user to say to move on before opening the next stop. Never chain several `open` calls in one turn.

## Slides

Write the deck to a markdown file outside the repo (e.g. /tmp). Separate slides with a `---` line. A slide names its code with `<!-- code: path:a-b -->` (relative to your cwd). Keep each slide short: a heading, a few lines, often a diagram. The user moves with `l`/`h` and closes with `q`; do not narrate ahead of them.

````markdown
## How todo-ai finds the editor
<!-- code: lua/todo-ai/cli.lua:80-120 -->

```mermaid
flowchart LR
  A[attached]:::focus --> B[same tab] --> C[cwd] --> D[error]:::error
```

Step 1 trusts the editor that ran :TodoAI, if it is still alive.
````

## Diagrams

Mermaid blocks render as colour-coded diagrams in the user's markdown. Colours are applied automatically: sequence participants, classes and states each get their own. In flowcharts, tag nodes by role so colour carries meaning:

`:::user` people · `:::service` systems we own · `:::container` apps · `:::component` parts of an app · `:::store` databases, files, caches · `:::queue` events, async · `:::external` outside our control · `:::error` failures · `:::ok` success · `:::focus` the thing being explained

C4 diagrams colour by element type (`Person`, `System`, `ContainerDb`, `System_Ext`, …) with no tagging.

If `todo-ai` reports more than one editor, tell the user to run `:TodoAI` in the editor they want.

Never run `git commit` or any git write command. The user reviews the diff and commits.
