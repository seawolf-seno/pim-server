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
- 2026-11-10: verified live on Prosody 13.0.7 (seno's machine): `tests/live_classtime.py`
  7 checks pass (groups, away in class, teacher teaching, others untouched, open/close
  class chat, students can't open it); status restored at the bell (pinned 10:59, back to
  the student's own status at 11:00). `PIM_FAKE_NOW` pins the clock for tests and demos.
  Gotchas: Prosody 13 has no `prosodyctl user list` (pim-dev checks account files);
  `prosody --version` starts a server with the system config; the lua-unbound warning is
  harmless (no s2s); slixmpp needs `unencrypted_scram` on localhost and reports away as
  `presence_away`, not `presence_available`.
- 2026-11-10: class and activity rooms: `mod_pim_classroom` (MUC component) makes one room
  per class/activity, syncs owners/members with school.json on start and config reload
  (verified: a dropped student loses the affiliation), members-only, unlisted, school-name
  nicks, no room PMs, users can't create rooms, disco#items on the service = "my rooms".
  During class students post only while class chat is open; open/close notices via the
  `pim-class-chat` global event from mod_pim_classtime. Shared libs: `pim_school`,
  `pim_clock`, `pim_rooms` (6 tests). `tests/live_rooms.py` 11 checks pass;
  `tests/live_common.py` holds the shared test client.
  Gotchas: Prosody's own MUC join errors don't echo `<x xmlns=muc/>`, so slixmpp's
  join_muc_wait times out on them (our refusals echo it; the test watches presence
  instead). Use `module:on_ready()` for work that needs the server up.
- Next: the XMPP connector in `../pim` (see docs/plan.md phase 2).
