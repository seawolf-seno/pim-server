# pim plan

pim is an instant messenger for StudentOS in the spirit of AIM: a buddy list, away
messages, IM windows and chat rooms, built for a school. Two repos:

| Repo | What |
|---|---|
| [`seawolf-seno/pim`](https://github.com/seawolf-seno/pim) | The client. A fork of [timlittle/omamessenger](https://github.com/timlittle/omamessenger) (Omarchy plugin: QML UI + Go helper) with an XMPP connector, presence and buddy list, and a school build. |
| `seawolf-seno/pim-server` (this repo) | The school's XMPP server (Prosody): config, modules for class time and messaging rules, `pim-seed` for accounts and buddy lists, and the policy. |

## Decisions

- 2026-11-10 (seno): build on timlittle/omamessenger instead of from scratch; fork for the
  client, separate repo for the server.
- 2026-11-10 (seno): name **pim**, an homage to AIM.
- 2026-11-10 (seno): messaging rule is rooms plus logged 1:1 (`policy.md`).
- 2026-11-10 (seno): start with the AIM feel: buddy list, and away by default during
  class unless the teacher opens a class chat.
- 2026-11-10 (seno): student devices are the system of record through OmaLocker; pim is
  one more input to each student's Locker.
- 2026-11-10 (seno): the Locker gets messages with staff, teacher announcements and the
  student's own messages; never other students' words ("pim and OmaLocker").
- XMPP with Prosody: buddy lists (rosters), presence and away messages, rooms and a
  message archive are all standard, so the school owns an open protocol on its own server.
- Class time is enforced by the server (`mod_pim_classtime`), not the client.
- One schedule format for the school: OmaMastery's `schedule.toml`.

## Phases

1. **Server foundation** (this repo), in progress:
   - [x] Fictional school and schedule (`fixtures/school/`)
   - [x] `pim-seed`: checks the files; writes buddy-list groups, `school.json`, accounts
   - [x] `pim_schedule` (pure Lua, tested) and `mod_pim_classtime`: away during class,
         "Open class chat" / "Close class chat" for the teacher
   - [x] `pim-dev`: local Prosody as yourself, localhost only
   - [x] Run it against Prosody 13.0.7: buddy lists, away in class, class chat open and
         close, and status restored at the bell (`tests/live_classtime.py`)
   - [x] Class and activity rooms (`mod_pim_classroom`): made and kept in step with the
         school file, members-only, school names, no room PMs, "my rooms" list, students
         post during class only while class chat is open, open/close notices
         (`tests/live_rooms.py`, 11 checks)
2. **Client: XMPP connector** (pim fork): `backend/internal/connector/xmpp`, passing the
   upstream conformance suite; 1:1 messages and rooms through the existing UI.
3. **Client: the AIM feel**: an optional presence capability on the connector; the
   buddy list (groups from the server, online/away dots, away messages); set your own
   away message; door-open/close-style sounds that are pim's own, not AOL's.
4. **Rules**: `mod_pim_policy` for 1:1 limits and hours, held notifications in class,
   test mode, the Report button, and an archive-reader access log.
5. **School build and pacos**: only the XMPP connector compiled in (no Telegram or
   WhatsApp, no GPL code), server address in `/etc/pim/`, packaged with no runtime
   download; pacos adds the package, its data folder to `student/writable`, and a key.
6. **pim and OmaLocker** (below).
7. **Pilot**: staff first; students after the policy is approved.

## pim and OmaLocker

The student's device is the system of record. pim writes a filtered export on the device;
OmaLocker turns it into notes, the way `omalocker import pacterminus` works:

1. pim writes `~/.local/share/pim/locker-export/` (format defined in the pim fork).
2. `omalocker import pim` (built in the omalocker repo; proposed there as
   `docs/pim.md`, not changed from here) writes notes inside its own block.
3. Notes are private by default: only the student and their own AI tools. They reach a
   parent, teacher or advisor view only if the student shares them.

What reaches the Locker (decided by seno, 2026-11-10):
- messages between the student and teachers or staff
- teacher announcements in class and activity rooms
- the student's own messages, in rooms and 1:1
- never other students' words, and never the other side of a student-to-student 1:1
  conversation, because they would become context for one student's AI about another

Open: Graphify over pim notes reverses OmaLocker's "Graphify only on curriculum files"
decision and needs seno's sign-off, plus the AI-on-student-data gate.

## Open decisions

1. Chat sign-in: a separate pim password for the pilot, or automatic sign-in from the
   pacos login (needs provisioning in pacos).
2. Where the school server runs (one of the pilot servers?), and its time zone (the
   server's local time is the school's).
3. Where class lists come from for real: Blackbaud on the server, or OmaMastery.
4. Safety archive: retention, parent requests, age 18, report path (`policy.md`).
