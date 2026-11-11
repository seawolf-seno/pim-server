-- mod_pim_classtime: away during class, unless the teacher opens a class chat.
--
-- While a class is in session (school.json's schedule and classes, from
-- pim-seed), the server rewrites the presence a student or teacher in that
-- class sends to everyone: <show>away</show> and a status such as
-- "In Biology · Block 2". When the period ends their own presence comes back.
-- The class's teacher can run the ad-hoc command "Open class chat" during the
-- period; then the class shows as available with "class chat open" until the
-- period ends or the teacher runs "Close class chat".
--
-- The server, not the client, does this, so a student can't change it and any
-- XMPP client shows it the same way. The school's time zone is the server's
-- local time (set TZ for prosody).
--
-- Config (on the VirtualHost):
--   pim_school_file = "/var/lib/pim/school.json"
--   pim_classtime_interval = 30  -- seconds between checks for a period change

local json = require "util.json";
local st = require "util.stanza";
local jid_split = require "util.jid".split;

local schedule = module:require("pim_schedule");

local school_file = module:get_option_path("pim_school_file", nil, "data");
local interval = module:get_option_number("pim_classtime_interval", 30);

local school;
-- Shared so a reload keeps opened chats, and so mod_pim_classroom (the MUC
-- side, planned) can read the same state: { [period_key] = true }.
local open_chats = module:shared("open_chats");

local function load_school()
	if not school_file then
		module:log("error", "pim_school_file is not set; class time is off");
		return nil;
	end
	local f, err = io.open(school_file, "r");
	if not f then
		module:log("error", "Can't read pim_school_file: %s", err);
		return nil;
	end
	local text = f:read("*a");
	f:close();
	local data, decode_err = json.decode(text);
	if type(data) ~= "table" or type(data.schedule) ~= "table" or type(data.classes) ~= "table" then
		module:log("error", "pim_school_file is not a pim-seed school.json: %s", tostring(decode_err));
		return nil;
	end
	-- Counts only: names never go in the log.
	module:log("info", "Loaded school: %d classes", #data.classes);
	return data;
end

school = load_school();
module:hook_global("config-reloaded", function() school = load_school(); end);

-- Dev and demos only: pin the clock, as "YYYY-MM-DD HH:MM" (bin/pim-dev sets it
-- from PIM_FAKE_NOW). Never set on the school server.
local fake_now = module:get_option_string("pim_classtime_fake_now");
local fake_offset;
if fake_now then
	local y, mo, d, h, mi = fake_now:match("^(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d)$");
	if y then
		local pinned = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
			hour = tonumber(h), min = tonumber(mi), sec = 0 });
		fake_offset = pinned - os.time();
		module:log("warn", "Clock pinned to %s for testing (pim_classtime_fake_now)", fake_now);
	else
		module:log("error", "pim_classtime_fake_now must be \"YYYY-MM-DD HH:MM\"; ignoring it");
	end
end

-- The fake clock keeps running from the pinned time, so periods still end.
local function now()
	return os.date("*t", os.time() + (fake_offset or 0));
end

-- The override for a session right now, and a key that changes when it does.
local function override_for(username)
	if not school then return nil, ""; end
	local o = schedule.status_for(school, username, now(), open_chats);
	if not o then return nil, ""; end
	return o, (o.show or "available") .. "\0" .. o.status;
end

local function apply(stanza, o)
	stanza:remove_children("show");
	stanza:remove_children("status");
	if o.show then stanza:tag("show"):text(o.show):up(); end
	stanza:tag("status"):text(o.status):up();
	return stanza;
end

-- A client's own broadcast presence (no "to") arrives as pre-presence/bare
-- with to_self set, before mod_presence sends it to the buddy list.
module:hook("pre-presence/bare", function(event)
	local origin, stanza = event.origin, event.stanza;
	if not event.to_self or origin.type ~= "c2s" or stanza.attr.type ~= nil then return; end
	if origin.pim_reposting then return; end
	-- Keep what the person chose, to restore it when the period ends.
	origin.pim_presence = st.clone(stanza);
	local o, key = override_for(origin.username);
	origin.pim_applied = key;
	if o then apply(stanza, o); end
end, 10);

-- Re-send each session's presence when its override changes (a period starts
-- or ends, or a chat opens or closes).
local function refresh(only_username)
	local host_sessions = prosody.hosts[module.host].sessions;
	for username, user in pairs(host_sessions) do
		if not only_username or only_username == username then
			for _, session in pairs(user.sessions or {}) do
				if session.pim_presence and session.presence then
					local o, key = override_for(username);
					if key ~= session.pim_applied then
						local p = st.clone(session.pim_presence);
						session.pim_applied = key;
						if o then apply(p, o); end
						session.pim_reposting = true;
						local ok, err = pcall(prosody.core_post_stanza, session, p, true);
						session.pim_reposting = nil;
						if not ok then module:log("warn", "Couldn't refresh a presence: %s", err); end
					end
				end
			end
		end
	end
end

module:add_timer(interval, function()
	refresh();
	return interval;
end);

-- Opened chats end with their period: forget keys that no longer match a
-- class in session. (They'd stop applying anyway; this keeps the table small.)
module:add_timer(300, function()
	local today = schedule.date_string(now());
	for key in pairs(open_chats) do
		if key:sub(1, #today) ~= today then open_chats[key] = nil; end
	end
	return 300;
end);

-- Ad-hoc commands for the teacher of the class happening now.
module:depends("adhoc");
local adhoc_new = module:require("adhoc").new;

local function teaching_now(jid)
	local username, host = jid_split(jid);
	if host ~= module.host or not school then return nil; end
	local class, as = schedule.class_now(school, username, now());
	if as ~= "teacher" then return nil; end
	return class, username;
end

local function set_chat(open)
	return function(_, data)
		local class = teaching_now(data.from);
		if not class then
			return { status = "completed", error = { message = "You aren't teaching a class right now." } };
		end
		local key = schedule.period_key(class, now());
		open_chats[key] = open or nil;
		module:log("info", "Class chat %s for %s", open and "opened" or "closed", class.id);
		refresh();
		local verb = open and "opened" or "closed";
		return { status = "completed", info = class.name .. " class chat " .. verb .. " for this period." };
	end
end

module:provides("adhoc", adhoc_new("Open class chat", "pim#open-class-chat", set_chat(true), "local_user"));
module:provides("adhoc", adhoc_new("Close class chat", "pim#close-class-chat", set_chat(false), "local_user"));
