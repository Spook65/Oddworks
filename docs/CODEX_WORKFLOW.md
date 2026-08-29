# ODDWORKS Codex Workflow

## Required Workflow For Significant Passes

Each significant implementation pass should follow:

1. Read relevant contracts.
2. Inspect current implementation.
3. State the affected system.
4. Identify client/server authority boundaries.
5. Identify attacker-controlled inputs when networking is involved.
6. Make the smallest complete change.
7. Avoid unrelated refactors.
8. Run available static/build verification.
9. Sync/test in Studio where practical.
10. Inspect Output/errors.
11. Perform adversarial tests where the change is security-sensitive.
12. Report exactly what changed.
13. Report what could not be verified.
14. Suggest one focused commit.

## Prompt And Report Shape

Future Codex prompts and reports should respect:

- Project
- Task
- Current problem
- Goal
- Allowed files
- Do not touch
- Out of scope
- Implementation requirements
- Security requirements
- Monetization/legal notes
- Verification
- Acceptance
- Output report
- Suggested commit

If a prompt conflicts with an existing contract, Codex should flag the conflict before implementing.

## Scope Discipline

Do not add new features merely because they may be useful later.

Finish the requested pass, verify it honestly, and leave future features for future prompts. Helpful ideas should be reported as recommendations, not silently implemented.

## Do Not Touch Vs Out Of Scope

DO NOT TOUCH means existing systems/files that must not be modified.

OUT OF SCOPE means functionality that must not be implemented yet.

Codex must respect both. A file can be allowed while a feature remains out of scope, and a feature can be relevant while a file remains protected.

## Truthful Verification

Codex must never claim:

- Studio testing passed
- rojo build passed
- security testing passed
- static analysis passed

unless that verification was actually performed.

If a verification step cannot be performed, Codex should say so plainly and explain why.

## Source Of Truth

Filesystem-managed Luau is canonical.

Roblox Studio is used for authoring appropriate world content, visual inspection, and testing, but Rojo-managed script changes should not diverge from root `src/**`.

Future scripts should be edited in the filesystem unless a pass explicitly involves Studio-authored objects or assets. When Studio-authored content becomes source-controlled, it should be represented clearly in the canonical root Rojo project.

## Security And Monetization Gates

Networking, economy, inventory, persistence, crafting, rewards, purchases, and ownership changes must consult the relevant contracts before implementation.

Security-sensitive passes should include adversarial tests. Monetization-sensitive passes should include policy/compliance, UX clarity, and technical-security review.
