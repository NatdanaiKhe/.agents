# AGENT.md

Global rules for AI coding agents work.

## Before coding

- Verify dependencies before using them (`go.mod`, `package.json`, imports, etc.).
- If requirements or scope are ambiguous, ask before making changes.
- State assumptions explicitly. Surface multiple interpretations rather than picking silently.
- If a simpler approach exists, say so. Push back when warranted.
- Don't hide confusion — name what is unclear and ask first.

## Coding

- Match the existing style and conventions, even if you'd do it differently.
- Prefer simple, explicit code. Minimum code that solves the problem.
- Keep functions focused.
- Reuse existing project libraries and patterns.
- Don't introduce one-off abstractions. No speculative flexibility, configurability, or error handling for impossible cases.
- Never ignore errors.
- Briefly explain non-obvious language or framework idioms.
- Ask: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### Surgical changes

- Touch only what the task requires. Every changed line should trace directly to the request.
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- If you notice unrelated dead code, mention it — don't delete it.
- Remove only orphans your own changes created.

## Goal-driven execution

Define success criteria up front so you can loop independently:

- "Add validation" → "Write tests for invalid inputs, then make them pass."
- "Fix the bug" → "Write a test that reproduces it, then make it pass."
- "Refactor X" → "Ensure tests pass before and after."

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```

## Testing

- New behavior requires tests.
- Bug fixes require regression tests.

## Before finishing

- Run the project's lint and test commands.
- If they fail or don't exist, report it instead of substituting another command.

## Output

- Show code/diff first, then a brief explanation.
- Keep explanations concise.
- Mention tradeoffs only when they materially affect the implementation.

## Note on tradeoffs

These rules bias toward caution over speed. For trivial tasks, use judgment.

# Git Convention

- Follow Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`).
- Keep commits atomic (one logical change per commit).
- Ensure tests/build pass before committing.
- Never commit secrets, debug code, or directly to `main`.
