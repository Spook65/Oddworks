# ODDWORKS
ODDWORKS is a Roblox Studio + Luau social collection/workshop game developed through Codex, Git, Rojo, and Roblox Studio integration.

Current status: pre-production / vertical-slice foundation. The current keycard/core arena is temporary toolchain-validation content, not the intended production game.

## Development Architecture
The repository root is the canonical ODDWORKS Roblox project. Use `default.project.json` in this directory as the Rojo project file, and use `src/**` in this directory as the canonical filesystem source for Rojo-managed Luau.

Roblox Studio should be synced against this root project only. Rojo-managed scripts should be edited through the filesystem so Studio and Git do not drift apart.

## Production Contracts
Read the relevant contracts before significant implementation work:

- [Game Direction](docs/GAME_DIRECTION.md)
- [Art Direction](docs/ART_DIRECTION.md)
- [Security Contract](docs/SECURITY_CONTRACT.md)
- [Monetization Contract](docs/MONETIZATION_CONTRACT.md)
- [Codex Workflow](docs/CODEX_WORKFLOW.md)

## Getting Started
To build the place from scratch, use:

```bash
rojo build -o "ODDWORKS.rbxlx"
```

Next, open `ODDWORKS.rbxlx` in Roblox Studio and start the Rojo server:

```bash
rojo serve
```

For more help, check out [the Rojo documentation](https://rojo.space/docs).
