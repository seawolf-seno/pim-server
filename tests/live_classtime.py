"""Live test of buddy lists and away-during-class against the dev server.

Needs the dev server with the clock pinned to Monday during Biology, and slixmpp:

    PIM_FAKE_NOW="2026-11-09 10:00" bin/pim-dev up
    python3 -m venv /tmp/pimvenv && /tmp/pimvenv/bin/pip install slixmpp
    /tmp/pimvenv/bin/python tests/live_classtime.py

Not part of `make test` (it needs a running server). Fictional accounts only.
"""

import asyncio
import logging
import sys

import slixmpp

DOMAIN = "pim.test"
PASSWORD = "pim-dev"
SERVER = ("127.0.0.1", 5222)
TIMEOUT = 10


class Client(slixmpp.ClientXMPP):
    def __init__(self, login, status=None):
        super().__init__(f"{login}@{DOMAIN}", PASSWORD)
        self.login = login
        self.own_status = status
        self.seen = {}  # bare jid -> (show, status), as this client sees them
        self.ready = asyncio.Event()
        self.enable_starttls = False
        self.enable_direct_tls = False
        self.enable_plaintext = True
        # The dev server is plain localhost. SCRAM never sends the password itself.
        self.plugin["feature_mechanisms"].unencrypted_scram = True
        self.register_plugin("xep_0030")
        self.register_plugin("xep_0050")
        self.add_event_handler("session_start", self.on_start)
        # Every presence: slixmpp splits them into presence_away, presence_dnd, etc.
        self.add_event_handler("presence", self.on_presence)

    async def on_start(self, _):
        await self.get_roster()
        self.send_presence(pstatus=self.own_status)
        self.ready.set()

    def on_presence(self, p):
        if p["type"] in ("subscribe", "subscribed", "unsubscribe", "unsubscribed", "probe", "error"):
            return
        if p["type"] == "unavailable":
            self.seen[p["from"].bare] = ("offline", "")
        else:
            self.seen[p["from"].bare] = (p["show"] or "available", p["status"])

    def groups(self):
        out = {}
        for jid in self.client_roster:
            for g in self.client_roster[jid]["groups"]:
                out.setdefault(g, set()).add(jid.split("@")[0])
        return out


async def wait_for(what, check, detail=None):
    for _ in range(TIMEOUT * 10):
        if check():
            return
        await asyncio.sleep(0.1)
    raise AssertionError(f"timed out waiting for: {what}{('; ' + detail()) if detail else ''}")


def jid(login):
    return f"{login}@{DOMAIN}"


async def run_command(client, node):
    session = await client.plugin["xep_0050"].send_command(slixmpp.JID(DOMAIN), node)
    return session["command"]["notes"]


async def main():
    rowan = Client("rteague29", status="studying")  # Biology, block 2 on A days
    kenji = Client("kosei30", status="free period")  # English 10 with Rowan, not Biology
    okafor = Client("okafor")  # teaches Biology
    clients = [rowan, kenji, okafor]
    for c in clients:
        c.connect(*SERVER)
    await asyncio.wait_for(asyncio.gather(*(c.ready.wait() for c in clients)), TIMEOUT)
    results = []

    def ok(name):
        results.append(name)
        print(f"ok  {name}")

    groups = rowan.groups()
    assert {"Biology", "English 10", "Robotics Club"} <= set(groups), groups
    assert "okafor" in groups["Biology"] and "lvance29" in groups["Biology"], groups
    assert "amensah28" not in set().union(*groups.values()), "Ama shares nothing with Rowan"
    assert "Teachers" not in groups, "students don't get the staff group"
    ok("buddy list groups come from classes and activities")

    away = ("away", "In Biology · Block 2")
    await wait_for("Kenji sees Rowan away in Biology", lambda: kenji.seen.get(jid("rteague29")) == away, lambda: f"Kenji sees {kenji.seen}")
    ok("a student in class shows away with the class and block")

    teaching = ("away", "Teaching Biology · Block 2")
    await wait_for("Rowan sees Mr. Okafor teaching", lambda: rowan.seen.get(jid("okafor")) == teaching)
    ok("the teacher shows as teaching")

    await wait_for("Rowan sees Kenji's own status", lambda: rowan.seen.get(jid("kosei30")) == ("available", "free period"))
    ok("someone not in class keeps their own status")

    notes = await run_command(okafor, "pim#open-class-chat")
    assert any("opened" in text for _, text in notes), notes
    open_ = ("available", "In Biology · class chat open")
    await wait_for("Rowan available with class chat open", lambda: kenji.seen.get(jid("rteague29")) == open_)
    ok("opening class chat makes the class available")

    notes = await run_command(okafor, "pim#close-class-chat")
    await wait_for("Rowan away again", lambda: kenji.seen.get(jid("rteague29")) == away, lambda: f"Kenji sees {kenji.seen}")
    ok("closing class chat puts the class back to away")

    notes = await run_command(kenji, "pim#open-class-chat")
    assert any("aren't teaching" in text for _, text in notes), notes
    ok("a student can't open class chat")

    for c in clients:
        c.disconnect()
    print(f"{len(results)} live checks passed")


if __name__ == "__main__":
    logging.basicConfig(level=logging.ERROR)
    try:
        asyncio.run(main())
    except AssertionError as e:
        print(f"FAIL {e}")
        sys.exit(1)
