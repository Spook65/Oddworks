# ODDWORKS Agent Guide

## Project

ODDWORKS is a Roblox / Luau game developed with Rojo and Wally. Development is portfolio-first and launch-aware. Prefer small, testable changes over broad speculative architecture.

The repository root is canonical: use `default.project.json` and edit Rojo-managed Luau through `src/` on the filesystem. Keep Studio synchronized with that source.

## Authority and Trust

- Server owns authoritative gameplay state; clients submit intent and present results.
- Treat client-provided gameplay data as untrusted. Never trust client-supplied ownership, reward, RNG, capability, permission, or state results.
- Presentation state must never become gameplay authority or corrupt valid ownership when presentation fails.

## State and Lifetime

- Keep persistent, session, recovery-generation, possession-scoped, derived, and presentation state distinct when relevant.
- Delayed or asynchronous work must revalidate the generation/version/state it belongs to before mutating current state.
- When shared state requires an atomic final transition, do not yield between final validation and commit.

## System Design

- Before substantial architecture changes, inspect the implementation, identify the responsible system, preserve boundaries, and prefer existing proven patterns when they fit.
- Avoid generic frameworks and hypothetical future architecture until repeated evidence justifies them.
- Read relevant repository contracts before significant work. Surface conflicts with the current task; historical milestone text does not authorize new work.

## Product Experiments

Technical correctness does not imply product usefulness. Prefer reversible experiments: hypothesis -> narrow implementation -> human test -> keep, revise, or remove based on evidence. Failed product experiments should not remain substantial active complexity without justification.

## Existing ODDWORKS Principles

- Kinetic is currently beginner / PvP-safe; Furnace is the advanced contested recovery.
- Secured persistent progress is protected from PvP.
- Construct capabilities should create different approaches to problems rather than mandatory equipment gates.
- Rarity should not automatically equal linear power.
- New mechanics should strengthen the coherent recovery / economy / build loop rather than become unrelated minigames.

## Repository Safety

- Inspect `git status` before significant work; preserve unrelated edits and do not mix unrelated changes.
- Do not automatically commit, merge, push, reset, or rewrite history unless explicitly requested.
- Do not modify persistence schemas unless explicitly requested.
- Do not modify documentation unless the task requests it.
- Do not introduce production cheat/debug remotes.

## Verification

Use applicable repository checks before reporting implementation completion: `wally install`, `rojo build`, XML validation, JSON validation, `git diff --check`, and Studio parsing/bootstrap when applicable.

`rojo build` does not by itself prove Luau syntax correctness. Human multiplayer/game-feel verification remains required when the task depends on multiplayer behavior or product judgment. Report only checks actually performed and plainly identify anything unverified; developer-harness bypasses do not prove the skipped production mechanic.

## Agent Workflow

- Implementation agents may edit only within their assigned task. Read-only reviewers must not modify repository files.
- For explicit reviews, report findings before suggesting changes.
- Human approval remains the final product and merge gate.

## Guide Maintenance

Keep this guide stable across milestones. Do not add temporary test values, branch names, one-off reproductions, milestone requirements/results, or implementation plans; those belong in task prompts or Git history. Keep one root guide until real directory-specific conflicts justify nested instructions.
