-- pim_rooms: the class and activity rooms, and who may post in them. Pure Lua
-- with no Prosody dependencies (tests/test_rooms.lua). mod_pim_classroom loads
-- it with module:require("pim_rooms").
--
-- Rooms come from pim-seed's school.json: one per class (the teacher owns it,
-- students are members) and one per activity (the leader owns it, members are
-- members). The room's local part is the class or activity id.

local M = {}

local function index(school)
	if school._pim_index then return school._pim_index end
	local by_id = {}
	for _, class in ipairs(school.classes or {}) do
		by_id[class.id] = { kind = "class", class = class, owner = class.teacher, members = class.students }
	end
	for _, activity in ipairs(school.activities or {}) do
		by_id[activity.id] = { kind = "activity", activity = activity, owner = activity.leader, members = activity.members }
	end
	school._pim_index = by_id
	return by_id
end

-- Every room the server keeps: { id, jid, name, kind, owners = {jid}, members = {jid} }.
function M.rooms(school)
	local out = {}
	local function add(id, name, kind, owner, members)
		local member_jids = {}
		for _, login in ipairs(members or {}) do
			member_jids[#member_jids + 1] = login .. "@" .. school.domain
		end
		out[#out + 1] = {
			id = id, jid = id .. "@" .. school.rooms_domain, name = name, kind = kind,
			owners = { owner .. "@" .. school.domain }, members = member_jids,
		}
	end
	for _, class in ipairs(school.classes or {}) do
		add(class.id, class.name, "class", class.teacher, class.students)
	end
	for _, activity in ipairs(school.activities or {}) do
		add(activity.id, activity.name, "activity", activity.leader, activity.members)
	end
	return out
end

-- The name a person must use in rooms: their name in the school file.
function M.nick_for(school, login)
	local person = (school.people or {})[login]
	return person and person.name or nil
end

-- May `login` post in room `room_id` at `now`? Returns true, or false and a
-- message to show them.
--   schedule:    the pim_schedule library
--   open_chats:  { [period_key] = true } (mod_pim_classtime's shared table)
--   outside:     "open" (students may post outside their class period) or "closed"
function M.can_post(school, schedule, room_id, login, now, open_chats, outside)
	local room = index(school)[room_id]
	if not room then return false, "This isn't a school room." end
	if login == room.owner then return true end
	local member = false
	for _, m in ipairs(room.members or {}) do
		if m == login then member = true; break end
	end
	if not member then return false, "You aren't in this room." end
	if room.kind == "activity" then return true end

	local class = room.class
	if schedule.in_session(school.schedule, class, now) then
		if open_chats and open_chats[schedule.period_key(class, now)] then return true end
		return false, class.name .. " class chat is closed during class. Your teacher can open it."
	end
	if outside == "closed" then
		return false, class.name .. " class chat is open only when your teacher opens it."
	end
	return true
end

return M
