# AGENT.md

Global rules for AI coding agents.

## Before coding

- Verify dependencies before using them (`go.mod`, `package.json`, imports, etc.).
- If requirements or scope are ambiguous, ask before making changes.
- State assumptions explicitly. Surface multiple interpretations rather than picking silently.
- If a simpler approach exists, say so. Push back when warranted.
- Don't hide confusion — name what is unclear and ask first.

<!-- context7 -->
Use the `ctx7` CLI to fetch current documentation whenever the user asks about a library, framework, SDK, API, CLI tool, or cloud service — even well-known ones like React, Next.js, Prisma, Express, Tailwind, Django, or Spring Boot. This includes API syntax, configuration, version migration, library-specific debugging, setup instructions, and CLI tool usage. Use even when you think you know the answer — your training data may not reflect recent changes. Prefer this over web search for library docs.

Do not use for: refactoring, writing scripts from scratch, debugging business logic, code review, or general programming concepts.

## Steps

1. Resolve library: `npx ctx7@latest library <name> "<what to look up>"` — use the official library name with proper punctuation (e.g., "Next.js" not "nextjs", "Customer.io" not "customerio", "Three.js" not "threejs")
2. Pick the best match (ID format: `/org/project`) by: exact name match, description relevance, code snippet count, source reputation (High/Medium preferred), and benchmark score (higher is better). If results don't look right, try alternate names or queries (e.g., "next.js" not "nextjs", or rephrase the question)
3. Fetch docs: `npx ctx7@latest docs <libraryId> "<what to look up>"` — run a separate `docs` command per distinct concept if the question spans multiple topics, unless it's about how they interact
4. Answer using the fetched documentation

You MUST call `library` first to get a valid ID unless the user provides one directly in `/org/project` format. Be specific about what to look up in the library's documentation — specific and detailed queries return better results than vague single words, but keep each query to a single concept unless the question is about how concepts interact; combined multi-topic queries dilute ranking and return shallow results for each topic. Do not run more than 3 commands per question. Do not include sensitive information (API keys, passwords, credentials) in queries.

For version-specific docs, use `/org/project/version` from the `library` output (e.g., `/vercel/next.js/v14.3.0`).

If a command fails with a quota error, inform the user and suggest `npx ctx7@latest login` or setting `CONTEXT7_API_KEY` env var for higher limits. Do not silently fall back to training data.
<!-- context7 -->

## Coding

- Match existing style and conventions, even if you'd do it differently.
- Choose the simplest implementation that fully meets the requirements. No speculative abstractions, configurability, or error handling for impossible cases. Do not preserve backward compatibility — remove obsolete paths instead of adding compatibility layers, fallbacks, or migrations.
- Reuse existing project libraries and patterns first. Check a library's docs and types before assuming it lacks a capability. Prefer established, well-documented libraries over custom implementations unless there's a clear reason.
- Keep functions focused.
- Never ignore errors.
- Briefly explain non-obvious language or framework idioms.
- Ask: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### Surgical changes

- Touch only what the task requires. Every changed line must trace to the request.
- Don't "improve" adjacent code, comments, or formatting. Don't refactor things that aren't broken.
- If you notice unrelated dead code, mention it — don't delete it. Remove only orphans your own changes created.

## Architecture

- Grow the system in layers: start from the smallest version that works end-to-end, then add each capability on top of a working product. Never trade a working product for unfinished complexity.
- Keep components modular with clearly separated concerns.
- Make architectural decisions for the long term. Do not accept stopgaps meant to be replaced later.

## Execution

Define success criteria up front:

- "Add validation" → "Write tests for invalid inputs, then make them pass."
- "Fix the bug" → "Write a test that reproduces it, then make it pass."
- "Refactor X" → "Ensure tests pass before and after."

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```

- New behavior requires tests. Bug fixes require regression tests.
- Before finishing, run the project's lint and test commands. If they fail or don't exist, report it instead of substituting another command.

## Output

- Show code/diff first, then a brief explanation.
- Keep explanations concise.
- Mention tradeoffs only when they materially affect the implementation.

## Git

- Follow Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`).
- Keep commits atomic (one logical change per commit).
- Ensure tests/build pass before committing.
- Never commit secrets, debug code, or directly to `main`.
