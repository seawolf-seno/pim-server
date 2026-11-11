-- Tests for server/modules/pim_rooms.lib.lua. Run: lua5.4 tests/test_rooms.lua
-- The school mirrors fixtures/school (fictional).

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local S = dofile(here .. "/../server/modules/pim_schedule.lib.lua")
local R = dofile(here .. "/../server/modules/pim_rooms.lib.lua")

local function school()
	return {
		domain = "pim.test", rooms_domain = "rooms.pim.test",
		people = {
			okafor = { name = "Mr. Okafor", role = "staff" },
			pell = { name = "Dr. Pell", role = "staff" },
			rteague29 = { name = "Rowan Teague", role = "student" },
			kosei30 = { name = "Kenji Osei", role = "student" },
			dpark28 = { name = "Daniel Park", role = "student" },
		},
		schedule = {
			first_day = "2026-08-19", last_day = "2027-05-20",
			a_days = { "Mon", "Wed" }, b_days = { "Tue", "Thu" },
			blocks = {
				{ number = 1, start = "08:00", ["end"] = "09:25" },
				{ number = 2, start = "09:35", ["end"] = "11:00" },
			},
			fridays = {}, off = {},
		},
		classes = {
			{ id = "biology", name = "Biology", day = "A", block = 2, teacher = "okafor",
			  students = { "rteague29" } },
		},
		activities = {
			{ id = "robotics", name = "Robotics Club", leader = "pell", members = { "rteague29", "dpark28" } },
		},
	}
end

local function at(hour, min) -- Monday 2026-11-09, an A day
	return { year = 2026, month = 11, day = 9, wday = 2, hour = hour, min = min }
end

local failures, count = 0, 0
local function test(name, fn)
	count = count + 1
	local ok, err = pcall(fn)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(got, want, what)
	if got ~= want then
		error(string.format("%s: got %s, want %s", what or "value", tostring(got), tostring(want)), 2)
	end
end

test("one room per class and activity", function()
	local rooms = R.rooms(school())
	eq(#rooms, 2, "count")
	eq(rooms[1].jid, "biology@rooms.pim.test", "class room jid")
	eq(rooms[1].owners[1], "okafor@pim.test", "teacher owns it")
	eq(rooms[1].members[1], "rteague29@pim.test", "student is a member")
	eq(rooms[2].name, "Robotics Club", "activity room name")
	eq(rooms[2].owners[1], "pell@pim.test", "leader owns it")
end)

test("nick is the school name", function()
	eq(R.nick_for(school(), "rteague29"), "Rowan Teague", "student")
	eq(R.nick_for(school(), "ghost29"), nil, "unknown")
end)

test("class room during class: closed until the teacher opens it", function()
	local s, now = school(), at(10, 0)
	local ok, why = R.can_post(s, S, "biology", "rteague29", now, {}, "open")
	eq(ok, false, "closed")
	assert(why:find("closed during class"), why)
	eq(R.can_post(s, S, "biology", "okafor", now, {}, "open"), true, "teacher always")
	local open = { [S.period_key(s.classes[1], now)] = true }
	eq(R.can_post(s, S, "biology", "rteague29", now, open, "open"), true, "open")
end)

test("class room outside class follows the setting", function()
	local s, now = school(), at(12, 0)
	eq(R.can_post(s, S, "biology", "rteague29", now, {}, "open"), true, "open outside class")
	local ok, why = R.can_post(s, S, "biology", "rteague29", now, {}, "closed")
	eq(ok, false, "closed outside class")
	assert(why:find("only when your teacher opens it"), why)
end)

test("not a member", function()
	local ok, why = R.can_post(school(), S, "biology", "kosei30", at(12, 0), {}, "open")
	eq(ok, false, "outsider")
	assert(why:find("aren't in this room"), why)
	eq(R.can_post(school(), S, "nowhere", "okafor", at(12, 0), {}, "open"), false, "unknown room")
end)

test("activity rooms are open to members any time", function()
	local s = school()
	eq(R.can_post(s, S, "robotics", "dpark28", at(10, 0), {}, "closed"), true, "member")
	eq(R.can_post(s, S, "robotics", "pell", at(10, 0), {}, "closed"), true, "leader")
	eq(R.can_post(s, S, "robotics", "kosei30", at(10, 0), {}, "closed"), false, "outsider")
end)

print(string.format("%d tests, %d failed", count, failures))
os.exit(failures == 0 and 0 or 1)
