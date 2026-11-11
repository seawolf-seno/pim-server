-- mod_pim_classroom: the class and activity rooms. Load on the MUC component.
--
-- At startup (and on a config reload) the server makes one room per class and
-- activity in pim-seed's school.json, and keeps each in step with the school:
-- the teacher or leader owns it, its students or members are members, everyone
-- else is out. Rooms are members-only, unlisted and persistent; nobody else can
-- create rooms (set restrict_room_creation = true on the component).
--
-- Rules (pim_rooms.lib.lua):
--   * In a class room during that class, students post only while the teacher
--     has class chat open (mod_pim_classtime's "Open class chat"). Outside the
--     period they may post unless pim_classroom_outside_class = "closed".
--   * Activity rooms are open to their members any time.
--   * People appear under their school name (the server renames them on joining)
--     and can't change it.
--   * No private messages through a room: 1:1 messages go through the server's
--     own rules (docs/policy.md).
--
-- Config (on the MUC component):
--   pim_school_file = "/var/lib/pim/school.json"
--   pim_classroom_outside_class = "open"   -- or "closed"

local st = require "util.stanza";
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local jid_resource = require "util.jid".resource;

local schedule = module:require("pim_schedule");
local rules = module:require("pim_rooms");
local load_school = module:require("pim_school");
local now = module:require("pim_clock");

local muc = module:depends("muc");

local school_file = module:get_option_path("pim_school_file", nil, "data");
local outside = module:get_option_enum("pim_classroom_outside_class", "open", "closed");

local school, open_chats;

local function login_of(jid)
	local node, host = jid_split(jid);
	if school and host == school.domain then return node; end
	return nil;
end

-- Make every school room exist and match the school file.
local function sync_rooms()
	if not school then return; end
	local made, updated = 0, 0;
	for _, spec in ipairs(rules.rooms(school)) do
		local room = muc.get_room_from_jid(spec.jid);
		if not room then
			room = muc.create_room(spec.jid);
			made = made + 1;
		else
			updated = updated + 1;
		end
		room:set_name(spec.name);
		room:set_public(false);
		room:set_persistent(true);
		room:set_members_only(true);
		room:set_allow_member_invites(false);
		room:set_moderated(false); -- posting rules are ours (below), not voice
		room:set_changesubject(false);
		room:set_allow_pm("none");

		local want = {};
		for _, jid in ipairs(spec.owners) do want[jid] = "owner"; end
		for _, jid in ipairs(spec.members) do want[jid] = want[jid] or "member"; end
		local stale = {};
		for jid, affiliation in room:each_affiliation() do
			if want[jid] ~= affiliation then stale[#stale + 1] = jid; end
		end
		for _, jid in ipairs(stale) do
			if not want[jid] then room:set_affiliation(true, jid, nil, "No longer in this class"); end
		end
		for jid, affiliation in pairs(want) do
			if room:get_affiliation(jid) ~= affiliation then room:set_affiliation(true, jid, affiliation); end
		end
		room:save(true);
	end
	-- Counts only.
	module:log("info", "School rooms: %d created, %d checked", made, updated);
end

local function load()
	school = load_school(school_file);
	if school then
		open_chats = module:shared("/" .. school.domain .. "/pim_classtime/open_chats");
	end
end

load();
-- Rooms can only be made once the server is up: on_ready runs then, or right
-- away when the module is loaded into a running server.
module:on_ready(sync_rooms);
module:hook_global("config-reloaded", function() load(); sync_rooms(); end);

local function room_id(room)
	return (jid_split(room.jid));
end

-- Posting: before the role check (priority 50) so the reply explains why.
module:hook("muc-occupant-groupchat", function(event)
	if not school then return; end
	local login = login_of(event.stanza.attr.from);
	local ok, why = false, "Only school accounts can post here.";
	if login then
		ok, why = rules.can_post(school, schedule, room_id(event.room), login, now(), open_chats, outside);
	end
	if not ok then
		event.origin.send(st.error_reply(event.stanza, "auth", "forbidden", why, event.room.jid));
		return true;
	end
end, 60);

-- A refused join, echoing the <x/> MUC element as XEP-0045 asks, so clients
-- can tell it apart from other presence errors.
local function refuse_join(event, kind, condition, text)
	local reply = st.error_reply(event.stanza, kind, condition, text, event.room.jid):up();
	reply:tag("x", { xmlns = "http://jabber.org/protocol/muc" }):up();
	event.origin.send(reply);
	return true;
end

-- Nicknames: everyone appears under their school name. On joining, the server
-- renames the occupant to it (XEP-0045 status 210 tells the client its real
-- nickname), so a client never has to know the name in advance. Changing it
-- afterwards is refused.
local function school_nick(event)
	local login = school and login_of(event.stanza.attr.from);
	return login and rules.nick_for(school, login);
end

module:hook("muc-occupant-pre-join", function(event)
	if not school then return; end
	local want = school_nick(event);
	if not want then
		return refuse_join(event, "auth", "forbidden", "Only school accounts can join.");
	end
	event.occupant.nick = event.room.jid .. "/" .. want;
end, 5);

module:hook("muc-occupant-pre-change", function(event)
	if not school then return; end
	local want = school_nick(event);
	if jid_resource(event.dest_occupant.nick) ~= want then
		event.origin.send(st.error_reply(event.stanza, "modify", "not-acceptable",
			"Your name in rooms is your school name.", event.room.jid));
		return true;
	end
end, 5);

-- A notice in the class room when its teacher opens or closes class chat.
module:hook_global("pim-class-chat", function(event)
	if not school or event.host ~= school.domain then return; end
	local room = muc.get_room_from_jid(event.class.id .. "@" .. school.rooms_domain);
	if not room then return; end
	local text = event.open
		and "Class chat is open for this period."
		or "Class chat is closed.";
	room:broadcast_message(st.message({ type = "groupchat", from = room.jid })
		:tag("body"):text(text):up());
end);

-- Only sync_rooms makes rooms (belt and braces with restrict_room_creation = true).
module:hook("muc-room-pre-create", function(event)
	event.origin.send(st.error_reply(event.stanza, "cancel", "not-allowed", "Rooms are made by the school.", module.host));
	return true;
end, 100);

-- "My rooms": a disco#items query on the service lists the school rooms the
-- asker belongs to (rooms are unlisted, so Prosody itself lists none of them).
module:hook("host-disco-items", function(event)
	if not school then return; end
	local login = login_of(event.stanza.attr.from);
	if not login then return; end
	local from = jid_bare(event.stanza.attr.from);
	for _, spec in ipairs(rules.rooms(school)) do
		local room = muc.get_room_from_jid(spec.jid);
		if room and not room:get_public() then
			local affiliation = room:get_affiliation(from);
			if affiliation == "owner" or affiliation == "member" then
				event.reply:tag("item", { jid = room.jid, name = room:get_name() }):up();
			end
		end
	end
end, -10);
