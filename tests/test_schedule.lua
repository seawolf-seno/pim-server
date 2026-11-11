-- Tests for server/modules/pim_schedule.lib.lua. Run: lua5.4 tests/test_schedule.lua
-- The school here mirrors fixtures/school (fictional).

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local S = dofile(here .. "/../server/modules/pim_schedule.lib.lua")

local school = {
	schedule = {
		first_day = "2026-08-19", last_day = "2027-05-20",
		a_days = { "Mon", "Wed" }, b_days = { "Tue", "Thu" },
		blocks = {
			{ number = 1, start = "08:00", ["end"] = "09:25" },
			{ number = 2, start = "09:35", ["end"] = "11:00" },
			{ number = 3, start = "11:40", ["end"] = "13:05" },
			{ number = 4, start = "13:15", ["end"] = "14:40" },
		},
		fridays = { ["2026-11-13"] = "A", ["2026-11-20"] = "B" },
		off = { { from = "2026-11-23", to = "2026-11-27", label = "Thanksgiving Break" } },
	},
	classes = {
		{ id = "biology", name = "Biology", day = "A", block = 2, teacher = "okafor",
		  students = { "jmarchetti29", "lvance29", "rteague29" } },
		{ id = "english-10", name = "English 10", day = "B", block = 1, teacher = "haddad",
		  students = { "jmarchetti29", "kosei30", "rteague29" } },
	},
}

-- 2026-11-09 is a Monday (wday 2).
local function at(day, wday, hour, min)
	return { year = 2026, month = 11, day = day, wday = wday, hour = hour, min = min }
end
local MON, TUE, FRI, SAT = 2, 3, 6, 7

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

test("day types", function()
	eq(S.day_type(school.schedule, at(9, MON, 10, 0)), "A", "Monday")
	eq(S.day_type(school.schedule, at(10, TUE, 10, 0)), "B", "Tuesday")
	eq(S.day_type(school.schedule, at(20, FRI, 10, 0)), "B", "listed Friday")
	eq(S.day_type(school.schedule, at(6, FRI, 10, 0)), nil, "unlisted Friday is never guessed")
	eq(S.day_type(school.schedule, at(14, SAT, 10, 0)), nil, "Saturday")
	eq(S.day_type(school.schedule, at(23, MON, 10, 0)), nil, "day off")
end)

test("out of the school year", function()
	local summer = { year = 2027, month = 6, day = 7, wday = MON, hour = 10, min = 0 }
	eq(S.day_type(school.schedule, summer), nil, "June")
end)

test("block edges", function()
	eq(S.block_at(school.schedule, at(9, MON, 9, 34)), nil, "passing period")
	eq(S.block_at(school.schedule, at(9, MON, 9, 35)), 2, "start is inside")
	eq(S.block_at(school.schedule, at(9, MON, 10, 59)), 2, "last minute")
	eq(S.block_at(school.schedule, at(9, MON, 11, 0)), nil, "end is outside")
end)

test("student away in class", function()
	local s = S.status_for(school, "rteague29", at(9, MON, 10, 0), {})
	eq(s.show, "away", "show")
	eq(s.status, "In Biology · Block 2", "status")
	eq(s.class, "biology", "class")
end)

test("teacher away while teaching", function()
	local s = S.status_for(school, "okafor", at(9, MON, 10, 0), {})
	eq(s.show, "away", "show")
	eq(s.status, "Teaching Biology · Block 2", "status")
end)

test("not in class means no override", function()
	eq(S.status_for(school, "kosei30", at(9, MON, 10, 0), {}), nil, "different class")
	eq(S.status_for(school, "rteague29", at(9, MON, 11, 20), {}), nil, "lunch")
	eq(S.status_for(school, "rteague29", at(14, SAT, 10, 0), {}), nil, "weekend")
end)

test("class chat open makes the class available", function()
	local now = at(9, MON, 10, 0)
	local open = { [S.period_key(school.classes[1], now)] = true }
	local s = S.status_for(school, "rteague29", now, open)
	eq(s.show, nil, "available")
	eq(s.status, "In Biology · class chat open", "status")
	eq(S.status_for(school, "okafor", now, open).status, "Teaching Biology · class chat open", "teacher")
end)

test("an opened chat ends with its period", function()
	local monday = at(9, MON, 10, 0)
	local open = { [S.period_key(school.classes[1], monday)] = true }
	local wednesday = { year = 2026, month = 11, day = 11, wday = 4, hour = 10, min = 0 }
	eq(S.status_for(school, "rteague29", wednesday, open).show, "away", "next Biology is away again")
end)

print(string.format("%d tests, %d failed", count, failures))
os.exit(failures == 0 and 0 or 1)
