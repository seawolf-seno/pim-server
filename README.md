# pim-server

The school server for [pim](https://github.com/seawolf-seno/pim), an instant messenger
for StudentOS in the spirit of AIM: buddy lists by class, away messages, IM and chat
rooms. It's [Prosody](https://prosody.im) (XMPP) plus a few school modules.

- **Buddy lists from the school:** every class, activity and the staff are a group on
  everyone's list (`pim-seed` writes Prosody's `groups.txt`).
- **Away during class:** while a class is in session, its students and teacher show
  away with "In Biology · Block 2". The teacher can open a class chat for the period.
  Enforced by the server (`server/modules/mod_pim_classtime.lua`).
- **Class and activity rooms:** one per class and activity, kept in step with the school
  file. During class only the teacher posts until they open class chat
  (`server/modules/mod_pim_classroom.lua`).
- **Policy:** rooms plus logged 1:1, see [docs/policy.md](docs/policy.md) (draft).
- **Plan:** [docs/plan.md](docs/plan.md).

Fictional data only in this repo. No real student uses pim until leadership approves
the policy.

## Try it locally

Needs `prosody` (`sudo pacman -S prosody`). It runs as you, on 127.0.0.1 only, with its
data in `.dev/`; the system service isn't used.

```sh
bin/pim-dev up      # seed the fictional school, create accounts, start Prosody
bin/pim-dev log     # follow the log
bin/pim-dev down
bin/pim-dev reset   # delete .dev/
```

Class time follows the server's clock. To try it outside school hours, pin the clock
(dev only; it keeps running from there, so periods still end):

```sh
PIM_FAKE_NOW="2026-11-09 10:00" bin/pim-dev up   # Monday, Biology in session
```

Sign in from any XMPP client as, for example, `rteague29@pim.test` (password `pim-dev`,
server `127.0.0.1`, port 5222). The dev server requires TLS, like the school server,
with a self-signed certificate `pim-dev` makes: trust `.dev/certs/pim.test.crt`. People and classes are in
`fixtures/school/school.toml`; times in `fixtures/school/schedule.toml` (OmaMastery's format).

## The school file and schedule

```sh
bin/pim-seed build --school school.toml --schedule schedule.toml --out DIR
```

Checks both files (logins follow pacos: ending in a graduation year means student;
teachers must be staff) and writes `groups.txt`, `school.json` and `accounts.txt` to
`DIR`, readable only by you. It refuses a school file not marked `fictional = true`
unless `--real`, and refuses `--real` inside a git repository. It prints counts, never names.

## Tests

```sh
make test   # pim-seed (Python), class schedule and room rules (Lua 5.4)
```

`tests/live_classtime.py` and `tests/live_rooms.py` sign in fictional students and
teachers against the dev server (pinned as above, freshly started) and check buddy-list
groups, away in class, class chat, and the rooms' rules. They need `slixmpp` (see the
files' docstrings).
