# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-page IT project-management Kanban board for an internal "UOB IT PMO" demo/training tool.
The entire application is one file: `index.html` (~1300 lines: markup, one `<style>` block, one `<script>` block).

There is no package.json, no build step, no test runner, no linter, and no dependencies. The repository
contains exactly one source file.

## Running and verifying changes

Run it by opening the file directly — `file:///…/index.html` in a browser, or double-clicking it.
There is no dev server, and adding one is not necessary.

Since there is no test suite, verify behaviour changes by driving the page in a real browser. Chromium is
available at `/opt/pw-browsers/chromium-*/chrome-linux/chrome`; `npm i playwright-core` into a scratch
directory (never into this repo) and script against `file:///home/user/IT-PMO-Kanban-board/index.html`.
Route-abort `https://formsubmit.co/**` so the notification failure path is exercised deterministically
instead of sending real email.

Worth asserting after any change to the board: per-column `.count-badge` values, `.card` count,
drag-and-drop and the `Move ▸` menu both changing a card's column, inline delete confirm, form validation
messages, that filters narrow the board, that `getComputedStyle(board).gridTemplateColumns` collapses to
one column below 768px, and that `localStorage.length` is still 0.

To syntax-check the script without a browser, extract the `<script>` block to a `.js` file and run
`node --check` on it.

## Hard constraints

These are product requirements, not stylistic preferences. Violating any of them breaks the deliverable:

- **Vanilla only.** No React/Vue/jQuery/Tailwind, no bundler, no npm dependency in the shipped file.
- **One file.** All markup, CSS and JS stay in `index.html`. Do not split into `app.js` / `styles.css`.
- **No external resources.** No CDN scripts, web fonts, or image files — system font stack, and inline SVG
  or Unicode glyphs for icons. The only outbound request in the whole app is the FormSubmit call.
- **No persistence of any kind.** `localStorage`, `sessionStorage`, IndexedDB and cookies are all off-limits.
  A refresh resetting the board to seed data is intended behaviour, and the yellow `.demo-note` in `<main>`
  tells the user so. If persistence is ever added, that note has to change with it.
- **No native `alert()` / `confirm()` / `prompt()`.** Validation surfaces as inline `.error` text; delete
  confirmation is the inline "Delete? Yes / No" block inside the card.
- **No `!important` in the CSS.**
- **Branding.** Text wordmark and corporate blue palette only — no real logos, trademarks, or imitation of
  an official system.

## Architecture

The script is divided into numbered comment sections (SECTION 1–13). Keep new code inside the section it
belongs to and keep the numbering intact.

**Single source of truth.** `state = { tasks, filters, ui }` holds everything. `state.tasks` is the board;
`state.filters` mirrors the filter bar; `state.ui` holds transient view state — `draggingId`, `moveMenuFor`,
`confirmDeleteFor`, and `focusSelector`.

**Render-from-state, never patch the DOM.** `renderBoard()` rebuilds the whole board's `innerHTML` from
`state` on every change; `renderCard()` returns the HTML string for one card. Card contents are never
mutated outside these two functions. Every mutation follows the same shape: change `state`, then call
`renderBoard()`. `addTask()`, `moveTask()` and `deleteTask()` are the only mutators, which is also why
adding persistence would only need hooks at those three seams plus `init()`.

Because the board is rebuilt wholesale, per-card open/closed state cannot live in the DOM — that is what
`state.ui.moveMenuFor` and `state.ui.confirmDeleteFor` are for. For the same reason, keyboard focus is lost
on every render: a mutator that should move focus sets `state.ui.focusSelector` to a CSS selector, and
`restoreFocus()` applies and clears it at the end of `renderBoard()`.

**Event delegation.** Listeners are attached once in `wireEvents()` to the `#board` container, never to
individual cards (which are destroyed on each render). Card controls declare `data-action` plus
`data-task-id`, and `handleBoardClick()` dispatches on them. New card controls should follow that pattern.

**Escaping.** Every user-supplied string interpolated into an HTML string must go through `escapeHtml()` —
this is the only thing standing between the app and XSS, since rendering is string concatenation into
`innerHTML`. Toast text uses `textContent` instead and needs no escaping.

**Dates.** Due dates are `YYYY-MM-DD` strings compared lexically. Use `todayISO()` rather than
`toISOString()` for "today" — the latter is UTC and drifts across the date boundary. `dateOffset(n)` exists
so seed data stays plausibly dated relative to whenever the demo is opened; seeds deliberately include past
dates so the Overdue badge has something to show.

**Column list.** `COLUMNS` drives column rendering, the Move menu, the summary strip and status validation.
Adding or renaming a column is a one-place edit there plus the matching `<option>` list and the
`.column[data-status="…"]` header-colour rules in the CSS.

## FormSubmit integration

`FORMSUBMIT_ENDPOINT` at the top of the script (SECTION 1) is the single place the notification address
appears; it must stay a clearly-marked config constant with its activation comment. FormSubmit needs a
one-time activation per address — the first submission triggers a confirmation email, and nothing delivers
until its link is clicked.

`notifyNewTask()` posts JSON to the AJAX endpoint so the page never navigates. It is fire-and-forget from
the board's perspective: `handleSubmit()` adds the card optimistically first, then awaits the call inside a
`try/catch` that degrades to a warning toast. A FormSubmit failure must never block or break the board, and
the email address must never be sent anywhere else.

## Git

Development happens on `claude/uob-it-pmo-kanban-t1mg4p`; push with `git push -u origin <branch>`.
