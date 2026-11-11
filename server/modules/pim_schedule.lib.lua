-- pim_schedule: which class a person is in right now, and what their status
-- should say. Pure Lua with no Prosody dependencies, so tests run with plain
-- lua5.4 (tests/test_schedule.lua). mod_pim_classtime loads it with
-- module:require("pim_schedule").
--
-- `school` is pim-seed's school.json, decoded. `now` is a table like
-- os.date("*t") in the school's time zone: { year, month, day, wday, hour, min }
-- where wday is 1 = Sunday ... 7 = Saturday.

local M = {}

local WEEKDAY = { [2] = "Mon", [3] = "Tue", [4] = "Wed", [5] = "Thu", [6] = "Fri" }

local function contains(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then return true end
	end
	return false
end

function M.date_string(now)
	return string.format("%04d-%02d-%02d", now.year, now.month, now.day)
end

function M.time_string(now)
	return string.format("%02d:%02d", now.hour, now.min)
end

-- "A", "B", or nil when there is no rotation today (weekend, day off, outside the
-- school year, or a Friday missing from the list, which is never guessed).
function M.day_type(schedule, now)
	local weekday = WEEKDAY[now.wday]
	if not weekday then return nil end
	local date = M.date_string(now)
	if date < schedule.first_day or date > schedule.last_day then return nil end
	for _, off in ipairs(schedule.off or {}) do
		if date >= off.from and date <= off.to then return nil end
	end
	if contains(schedule.a_days, weekday) then return "A" end
	if contains(schedule.b_days, weekday) then return "B" end
	return (schedule.fridays or {})[date]
end

-- The block number in progress at `now`, or nil between blocks. A block runs
-- from its start up to, not including, its end.
function M.block_at(schedule, now)
	local t = M.time_string(now)
	for _, block in ipairs(schedule.blocks) do
		if t >= block.start and t < block["end"] then return block.number end
	end
	return nil
end

-- The class `login` is in right now, as student or teacher, and which of the two.
function M.class_now(school, login, now)
	local day = M.day_type(school.schedule, now)
	if not day then return nil end
	local block = M.block_at(school.schedule, now)
	if not block then return nil end
	for _, class in ipairs(school.classes) do
		if class.day == day and class.block == block then
			if class.teacher == login then return class, "teacher" end
			if contains(class.students, login) then return class, "student" end
		end
	end
	return nil
end

-- Whether `class` is in session at `now`.
function M.in_session(schedule, class, now)
	return M.day_type(schedule, now) == class.day and M.block_at(schedule, now) == class.block
end

-- A key that changes when a class period starts or ends, so an opened class
-- chat closes by itself at the end of its period.
function M.period_key(class, now)
	return M.date_string(now) .. "/" .. class.id .. "/" .. class.block
end

-- What the server makes this person's presence say right now, or nil to leave
-- their own presence alone.
--   open_chats: { [period_key] = true } for class chats a teacher opened.
-- Returns { show = "away" | nil (available), status = "...", class = id }.
function M.status_for(school, login, now, open_chats)
	local class, as = M.class_now(school, login, now)
	if not class then return nil end
	local open = open_chats and open_chats[M.period_key(class, now)]
	if as == "teacher" then
		if open then
			return { status = "Teaching " .. class.name .. " · class chat open", class = class.id }
		end
		return { show = "away", status = "Teaching " .. class.name .. " · Block " .. class.block, class = class.id }
	end
	if open then
		return { status = "In " .. class.name .. " · class chat open", class = class.id }
	end
	return { show = "away", status = "In " .. class.name .. " · Block " .. class.block, class = class.id }
end

return M
