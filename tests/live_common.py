"""Shared pieces of the live tests (tests/live_*.py). Fictional accounts only."""

import asyncio
from pathlib import Path

import slixmpp

DOMAIN = "pim.test"
ROOMS = "rooms.pim.test"
PASSWORD = "pim-dev"
SERVER = ("127.0.0.1", 5222)
TIMEOUT = 10
CERT = Path(__file__).resolve().parent.parent / ".dev" / "certs" / f"{DOMAIN}.crt"


def jid(login):
    return f"{login}@{DOMAIN}"


class Client(slixmpp.ClientXMPP):
    """A signed-in fictional person who remembers what they've seen."""

    def __init__(self, login, status=None):
        super().__init__(jid(login), PASSWORD)
        self.login = login
        self.own_status = status
        self.seen = {}  # bare jid -> (show, status)
        self.room_messages = []  # (room, nick, body)
        self.errors = []  # (from, condition, text) of message errors
        self.ready = asyncio.Event()
        # STARTTLS, trusting only the dev server's own self-signed certificate.
        self.enable_direct_tls = False
        self.ca_certs = str(CERT)
        for plugin in ("xep_0030", "xep_0045", "xep_0050"):
            self.register_plugin(plugin)
        self.add_event_handler("session_start", self.on_start)
        # Every presence: slixmpp splits them into presence_away, presence_dnd, etc.
        self.add_event_handler("presence", self.on_presence)
        self.add_event_handler("groupchat_message", self.on_groupchat)
        self.add_event_handler("message_error", self.on_message_error)

    async def on_start(self, _):
        await self.get_roster()
        self.send_presence(pstatus=self.own_status)
        self.ready.set()

    def on_presence(self, p):
        if p["type"] in ("subscribe", "subscribed", "unsubscribe", "unsubscribed", "probe", "error"):
            return
        if p["from"].domain == ROOMS:
            return
        if p["type"] == "unavailable":
            self.seen[p["from"].bare] = ("offline", "")
        else:
            self.seen[p["from"].bare] = (p["show"] or "available", p["status"])

    def on_groupchat(self, m):
        self.room_messages.append((m["from"].bare, m["from"].resource, m["body"]))

    def on_message_error(self, m):
        self.errors.append((str(m["from"]), m["error"]["condition"], m["error"]["text"]))

    def groups(self):
        out = {}
        for item in self.client_roster:
            for g in self.client_roster[item]["groups"]:
                out.setdefault(g, set()).add(item.split("@")[0])
        return out


async def connect_all(*clients):
    for c in clients:
        c.connect(*SERVER)
    await asyncio.wait_for(asyncio.gather(*(c.ready.wait() for c in clients)), TIMEOUT)


async def wait_for(what, check, detail=None):
    for _ in range(TIMEOUT * 10):
        if check():
            return
        await asyncio.sleep(0.1)
    raise AssertionError(f"timed out waiting for: {what}{('; ' + detail()) if detail else ''}")


async def run_command(client, node):
    session = await client.plugin["xep_0050"].send_command(slixmpp.JID(DOMAIN), node)
    return session["command"]["notes"]


def ok(name, results):
    results.append(name)
    print(f"ok  {name}")
