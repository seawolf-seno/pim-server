# pim-server

The XMPP (Prosody) server for pim, the school messenger. Part of the school dev platform
initiative (see `~/.claude/CLAUDE.md`). Client: `../pim` (fork of timlittle/omamessenger).
Siblings: `../pacos`, `../omalocker`, `../omamastery`, `../omaclass`.

- **Rules live on the server.** Anything a student must not get around (class time,
  who can message whom, test mode) is a Prosody module here, never client-only.
- **Fictional data only** in this repo, fixtures and tests. Real school files stay on the
  server; `pim-seed --real` refuses to write inside a git repo.
- **No names or message text in logs or command output.** Counts only.
- Pure logic goes in `server/modules/*.lib.lua` with no Prosody dependencies, tested with
  plain `lua5.4` (`tests/`). Modules (`mod_*.lua`) are thin glue.
- One schedule format: OmaMastery's `schedule.toml`.
- Scope: work only in this repo. Changes pim, pacos or omalocker need go in a doc here
  (or in that repo's own session), not edits to those repos.
- `make test` before work is done.

## Status
- 2026-11-10: repo created. `pim-seed` (13 tests), `pim_schedule` (8 tests),
  `mod_pim_classtime` (away during class; Open/Close class chat ad-hoc commands),
  `pim-dev` and the dev Prosody config. Policy and plan drafted (`docs/`).
  `mod_pim_classtime` and `pim-dev` are **not yet run against a real Prosody**: prosody
  isn't installed on seno's machine yet.
- 2026-11-10: Locker scope decided (messages with staff, teacher announcements, own messages; never other students' words): docs/plan.md.
- Next: install prosody, run `pim-dev up`, check away-in-class with two XMPP clients;
  then class rooms + `mod_pim_classroom`; then the XMPP connector in `../pim`.
