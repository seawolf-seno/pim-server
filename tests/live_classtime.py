"""Live test of buddy lists and away-during-class against the dev server.

Needs the dev server with the clock pinned to Monday during Biology, and slixmpp:

    PIM_FAKE_NOW="2026-11-09 10:00" bin/pim-dev up
    python3 -m venv /tmp/pimvenv && /tmp/pimvenv/bin/pip install slixmpp
    /tmp/pimvenv/bin/python tests/live_classtime.py

Not part of `make test` (it needs a running server). Fictional accounts only.
"""

import asyncio
import importlib.util
import logging
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("live_common", Path(__file__).with_name("live_common.py"))
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
Client, jid, wait_for, run_command = common.Client, common.jid, common.wait_for, common.run_command


async def main():
    rowan = Client("rteague29", status="studying")  # Biology, block 2 on A days
    kenji = Client("kosei30", status="free period")  # English 10 with Rowan, not Biology
    okafor = Client("okafor")  # teaches Biology
    clients = [rowan, kenji, okafor]
    await common.connect_all(*clients)
    results = []

    def ok(name):
        common.ok(name, results)

    groups = rowan.groups()
    assert {"Biology", "English 10", "Robotics Club"} <= set(groups), groups
    assert "okafor" in groups["Biology"] and "lvance29" in groups["Biology"], groups
    assert "amensah28" not in set().union(*groups.values()), "Ama shares nothing with Rowan"
    assert "Teachers" not in groups, "students don't get the staff group"
    ok("buddy list groups come from classes and activities")

    away = ("away", "In Biology · Block 2")
    seen_by_kenji = lambda: f"Kenji sees {kenji.seen}"
    await wait_for("Kenji sees Rowan away in Biology", lambda: kenji.seen.get(jid("rteague29")) == away, seen_by_kenji)
    ok("a student in class shows away with the class and block")

    teaching = ("away", "Teaching Biology · Block 2")
    await wait_for("Rowan sees Mr. Okafor teaching", lambda: rowan.seen.get(jid("okafor")) == teaching)
    ok("the teacher shows as teaching")

    await wait_for("Rowan sees Kenji's own status", lambda: rowan.seen.get(jid("kosei30")) == ("available", "free period"))
    ok("someone not in class keeps their own status")

    notes = await run_command(okafor, "pim#open-class-chat")
    assert any("opened" in text for _, text in notes), notes
    open_ = ("available", "In Biology · class chat open")
    await wait_for("Rowan available with class chat open", lambda: kenji.seen.get(jid("rteague29")) == open_, seen_by_kenji)
    ok("opening class chat makes the class available")

    await run_command(okafor, "pim#close-class-chat")
    await wait_for("Rowan away again", lambda: kenji.seen.get(jid("rteague29")) == away, seen_by_kenji)
    ok("closing class chat puts the class back to away")

    notes = await run_command(kenji, "pim#open-class-chat")
    assert any("aren't teaching" in text for _, text in notes), notes
    ok("a student can't open class chat")

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
