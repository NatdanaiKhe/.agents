---
name: quiz-me
description: Generate an interactive HTML quiz that tests the user's understanding of code or changes a coding agent (Claude Code, Cursor, Copilot, etc.) just produced — used to catch up when the agent moved faster than the user could follow. Trigger ONLY when the user explicitly types the trigger phrase "/quiz" (or an unambiguous variant like "quiz me" / "quiz me on this"). Do NOT trigger automatically after code changes, and do NOT trigger on generic requests to "explain this code" — those should be answered directly instead.
---

# Quiz Me

Turns recent coding-agent output into a short, self-gradable HTML quiz so the user can check whether they actually understood what got built, instead of passively accepting it.

## When this fires

Only on the explicit trigger phrase `/quiz` (or clear equivalents: "quiz me", "quiz me on this", "quiz me on what we just did"). If the user asks to "explain" or "walk through" code, that's a normal explanation request, not this skill.

## Step 1: Determine scope

Default scope: the most recent substantive coding-agent output visible in the conversation — the last diff, set of file edits, or generated code block(s), plus whatever the agent said about *why* it made those choices.

- If there's no code visible in the conversation yet (e.g. user opens with `/quiz` cold), ask them to paste the code/diff or point to the file.
- If multiple distinct changes happened recently, default to the most recent one, but you can ask "quiz me on the whole session or just the last change?" if it's genuinely ambiguous — don't ask if there's an obvious single answer.

## Step 2: Extract quiz-worthy material

Don't target a fixed question count — target *coverage*. First, inventory every distinct "unit" the agent touched: each new function/method, each non-trivial config or schema change, each new dependency or pattern introduced, each notable decision point (why this approach over the obvious alternative). A small one-file tweak might yield 4 questions; a multi-file feature (new endpoint + service + guard + migration) should yield 12–20+. Scale to the actual diff, not the other way around.

For each unit, pull from two categories — don't skew all-code or all-concept, and don't skip a touched file/function just to keep the quiz short:

1. **Code specifics** — what a particular function/line/config actually does, what would happen if you changed X, what a specific variable/return value represents, how two pieces (e.g. a guard and a decorator) interact.
2. **Concepts & rationale** — why this pattern/library/approach was chosen over an obvious alternative, what problem it solves, what would break if you used the naive approach instead.

Favor questions that expose things a user could plausibly *not* have noticed if they were skimming fast — that's the whole point of this skill. Don't ask trivial questions (e.g. "what language is this in"), but don't merge two distinct things into one question just to save space either — if the agent touched 5 files, the quiz should make that legible, not compress it into a handful of generic questions.

If the change is large enough that a flat list would feel unwieldy (roughly 12+ questions), group questions under a subheading per file/module in the HTML so the user can see which part of the change each section covers.

## Step 3: Draft questions

Mix of two types, roughly balanced:

- **Multiple choice** — 4 options, 1 correct. Distractors should be plausible mistakes (common misconceptions, off-by-one logic, a nearby-but-wrong API), not silly throwaways.
- **Short answer** — open text for "why" / "what would happen if" questions. Write a model answer (2–3 sentences) for each — this gets revealed next to the user's own answer, since free text can't be reliably auto-graded in static HTML/JS.

Every question needs a 1–2 sentence explanation of the correct answer, shown after checking — this is the actual learning moment, not just the score.

## Step 4: Build the HTML artifact

Build a single self-contained HTML file (inline `<style>` and `<script>`, no external dependencies) and save it with `create_file` to `/mnt/user-data/outputs/` so it renders as an artifact. Then call `present_files`.

Requirements for the HTML:

- Clean, minimal quiz UI — question number, question text, then either radio buttons (MC) or a `<textarea>` (short answer).
- If questions are grouped by file/module (see Step 2), add a section heading above each group so the user can tell which part of the change it covers.
- A single "Check Answers" button at the bottom (not per-question) — the user should attempt everything before seeing feedback, to preserve actual recall effort.
- On check: MC questions highlight correct/incorrect inline and show the explanation. Short-answer questions reveal the model answer directly beneath the user's own typed answer (side-by-side or stacked) plus the explanation, so they can self-judge.
- A score summary at the top after checking, but score only the MC portion numerically (e.g. "3/5 multiple choice correct") — don't fake-score short answers.
- No external font/JS/CSS CDN calls — everything inline, since this should work as a standalone file.
- Keep visual design simple and readable: generous spacing, clear right/wrong color coding (e.g. green/red left border), no clutter.

## Step 5: Wrap-up

After presenting the file, do NOT re-explain the quiz content in chat — the artifact is the deliverable. A one-line intro like "Here's a quiz on the auth middleware you just added" is enough.
