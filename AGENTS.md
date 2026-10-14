# HUD variants

- International MythicRankHUD and regional QFXMythicRankHUD share runtime Lua and media. Only their TOC, localization and SavedVariables differ. Use tools/build_release.ps1 to build both variants.
- Tag-triggered publishing uploads only MythicRankHUD to CurseForge project 1616156 and GitHub; keep the regional ZIP local.
- Do not increment versions for local fixes; only an explicitly requested formal release permits a version increment.
- Before game sync, back up changed files outside the game and preserve player SavedVariables.
- Runtime changes must also be synchronized to the maintained regional source. Follow its AGENTS.md for integration synchronization unless the user explicitly defers that work.
