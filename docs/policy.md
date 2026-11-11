# pim messaging policy (draft)

Status: **draft for leadership.** Nothing here is approved. No real student uses pim
until leadership approves this policy and a parent consent/AI-use policy, the same
gate as every StudentOS tool.

The server enforces every rule below. The client only shows what the server allows,
so a student can't turn a rule off.

## Who can message whom

Decided by seno, 2026-11-10: **rooms plus logged 1:1.**

| From → to | Allowed | Notes |
|---|---|---|
| Staff → staff | Always | |
| Teacher → student | Always | Archived; visible to archive readers. No unmonitored teacher–student messaging. |
| Student → teacher | Their own teachers, activity leaders and advisor | Archived the same way. |
| Student → student, 1:1 | Only students who share a class or activity, during set hours | Archived for safety; read only as below. |
| Class room | The class's students and teacher | Teacher moderates. Students post during class only when the teacher opens class chat. |
| Activity room | Members and leader | Leader moderates. |

Built: buddy lists by class, activity and staff (`groups.txt`), away during class
(`mod_pim_classtime`), and class and activity rooms (`mod_pim_classroom`). Not built yet:
the 1:1 limits and hours (planned `mod_pim_policy`).

### Rooms

- The school makes the rooms: one per class (teacher owns it, students are members) and
  one per activity (leader owns it). They follow the school file: someone who leaves a
  class leaves its room on the next reload. Nobody else can create rooms.
- Rooms are members-only and unlisted. Each person's room list shows only their own.
- Everyone uses their school name in a room and can't change it.
- No private messages through a room: every 1:1 message goes through the 1:1 rules.
- Class room during its class: only the teacher posts, until the teacher opens class
  chat. Outside the class period students may post (default; `pim_classroom_outside_class
  = "closed"` keeps the room teacher-only unless class chat is open). Open for leadership:
  which default the school wants, and quiet hours for rooms.
- Activity rooms are open to members at any time (subject to quiet hours, planned).

## During class

- Everyone in a class in session shows **away**, with "In Biology · Block 2" (or
  "Teaching Biology · Block 2" for the teacher). Their own status comes back when the
  period ends.
- The teacher can **open class chat** for the period. The class then shows as available
  ("class chat open"), and the class room is open to students. It closes when the
  period ends or the teacher closes it.
- Planned: hold 1:1 notifications for a student in class (delivered after the period).
- Planned: **test mode**, no messaging at all during an assessment, switched on the same
  way as "AI off, scheduled" in the StudentOS deck.

## Two records, two purposes

1. **The student's own record: their Locker** (OmaLocker). The device is the system of
   record. pim keeps message history on the student's device, and a filtered part of it
   goes into their Locker (see `plan.md`, "pim and OmaLocker"). The student owns it.
2. **The safety archive: the server.** Every message is archived on the server (XMPP
   message archive) for safety only. It isn't the student's record and feeds no AI.

## Who can read the safety archive

- Named **archive readers** only (`archive_readers` in the school file), never all staff.
- Only for a report, a safety concern, or a legal request. Every open is logged with
  who, when and why.
- Students and families are told plainly, in the app and in the handbook, that
  messages are archived and who can read them.
- Open for leadership: retention length (dev server: 1 week), whether parents may
  request their child's messages (FERPA may treat them as education records), rights at
  age 18, and how a report reaches a mandated reporter.

## What pim never does

- Federation with other servers: only this school's accounts.
- Self-registration: accounts come from the school's records.
- Message text, names or rosters in logs (the server logs counts only).
- Real names or rosters in this repository.
