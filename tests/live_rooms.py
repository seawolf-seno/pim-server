"""Live test of class and activity rooms against the dev server.

Same setup as tests/live_classtime.py (dev server pinned to Monday 10:00, during
Biology; slixmpp):

    PIM_FAKE_NOW="2026-11-09 10:00" bin/pim-dev up
    /tmp/pimvenv/bin/python tests/live_rooms.py

Run it on a freshly started server: it opens and closes Biology's class chat.
Fictional accounts only.
"""

import asyncio
import importlib.util
import logging
import sys
from pathlib import Path

import slixmpp

spec = importlib.util.spec_from_file_location("live_common", Path(__file__).with_name("live_common.py"))
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
Client, ROOMS, wait_for, run_command = common.Client, common.ROOMS, common.wait_for, common.run_command

BIOLOGY = slixmpp.JID(f"biology@{ROOMS}")
ROBOTICS = slixmpp.JID(f"robotics@{ROOMS}")


async def join(client, room, nick):
    await client.plugin["xep_0045"].join_muc_wait(room, nick, maxstanzas=0, timeout=common.TIMEOUT)


async def refused(client, room, nick):
    """Try to join; return the error condition, or None if the join worked.

    Not join_muc_wait: it only notices errors that echo the <x/> MUC element,
    and Prosody's own refusals (members-only, room creation) don't.
    """
    reply = asyncio.get_running_loop().create_future()

    def on_presence(p):
        if p["from"].bare == room.bare and not reply.done():
            reply.set_result(p)

    client.add_event_handler("presence", on_presence)
    try:
        client.plugin["xep_0045"].join_muc(room, nick)
        p = await asyncio.wait_for(reply, common.TIMEOUT)
    finally:
        client.del_event_handler("presence", on_presence)
    if p["type"] == "error":
        return p["error"]["condition"]
    client.plugin["xep_0045"].leave_muc(room, nick)
    return None


def said(client, room, body):
    return any(r == room.bare and b == body for r, _, b in client.room_messages)


def post(client, room, body):
    client.send_message(mto=room, mbody=body, mtype="groupchat")


async def main():
    rowan = Client("rteague29")  # Biology student, Robotics member
    okafor = Client("okafor")  # teaches Biology
    kenji = Client("kosei30")  # not in Biology
    daniel = Client("dpark28")  # Robotics member
    clients = [rowan, okafor, kenji, daniel]
    await common.connect_all(*clients)
    results = []

    def ok(name):
        common.ok(name, results)

    items = await rowan.plugin["xep_0030"].get_items(jid=ROOMS, timeout=common.TIMEOUT)
    mine = {i[0] for i in items["disco_items"]["items"]}
    assert mine == {f"biology@{ROOMS}", f"english-10@{ROOMS}", f"robotics@{ROOMS}"}, mine
    ok("my rooms lists exactly my classes and activities")

    assert await refused(rowan, BIOLOGY, "Mr. Okafor") == "not-acceptable"
    ok("you can't join under someone else's name")

    assert await refused(kenji, BIOLOGY, "Kenji Osei") == "registration-required"
    ok("someone not in the class can't join its room")

    assert await refused(rowan, slixmpp.JID(f"secret-club@{ROOMS}"), "Rowan Teague") in ("not-allowed", "item-not-found")
    ok("students can't make their own rooms")

    await join(rowan, BIOLOGY, "Rowan Teague")
    await join(okafor, BIOLOGY, "Mr. Okafor")
    ok("class members join with their school names")

    post(rowan, BIOLOGY, "can we start the lab?")
    await wait_for("Rowan's post refused", lambda: any("closed during class" in (t or "") for _, _, t in rowan.errors),
                   lambda: f"errors {rowan.errors}")
    await asyncio.sleep(0.5)
    assert not said(okafor, BIOLOGY, "can we start the lab?"), "the closed post must not reach the room"
    ok("during class a student's post is refused until class chat opens")

    post(okafor, BIOLOGY, "Read section 4.2 first.")
    await wait_for("Rowan gets the teacher's post", lambda: said(rowan, BIOLOGY, "Read section 4.2 first."))
    ok("the teacher can post during class")

    await run_command(okafor, "pim#open-class-chat")
    await wait_for("open notice", lambda: said(rowan, BIOLOGY, "Class chat is open for this period."))
    post(rowan, BIOLOGY, "done with 4.2")
    await wait_for("Mr. Okafor gets Rowan's post", lambda: said(okafor, BIOLOGY, "done with 4.2"))
    ok("open class chat: a notice, then students can post")

    await run_command(okafor, "pim#close-class-chat")
    await wait_for("close notice", lambda: said(rowan, BIOLOGY, "Class chat is closed."))
    rowan.errors.clear()
    post(rowan, BIOLOGY, "one more thing")
    await wait_for("refused again", lambda: rowan.errors, lambda: f"errors {rowan.errors}")
    ok("closed again: a notice, and students' posts are refused")

    rowan.errors.clear()
    rowan.send_message(mto=slixmpp.JID(f"biology@{ROOMS}/Mr. Okafor"), mbody="psst", mtype="chat")
    await wait_for("private message refused", lambda: rowan.errors, lambda: f"errors {rowan.errors}")
    ok("no private messages through a room")

    await join(rowan, ROBOTICS, "Rowan Teague")
    await join(daniel, ROBOTICS, "Daniel Park")
    post(rowan, ROBOTICS, "meeting after school?")
    await wait_for("Daniel gets it", lambda: said(daniel, ROBOTICS, "meeting after school?"))
    ok("activity rooms are open to members during class time")

    for c in clients:
        c.disconnect()
    print(f"{len(results)} live checks passed")


if __name__ == "__main__":
    logging.basicConfig(level=logging.CRITICAL)
    try:
        asyncio.run(main())
    except AssertionError as e:
        print(f"FAIL {e}")
        sys.exit(1)
