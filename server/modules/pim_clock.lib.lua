-- pim_clock: the school's "now" for class time, as os.date("*t") in the server's
-- local time zone (the school's). Load with module:require("pim_clock").
--
-- Dev and demos only: pim_classtime_fake_now = "YYYY-MM-DD HH:MM" (a global
-- option; bin/pim-dev sets it from PIM_FAKE_NOW) pins the clock. It keeps
-- running from there, so periods still end. Never set on the school server.

local fake_now = module:get_option_string("pim_classtime_fake_now");
local offset = 0;
if fake_now then
	local y, mo, d, h, mi = fake_now:match("^(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d)$");
	if y then
		local pinned = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
			hour = tonumber(h), min = tonumber(mi), sec = 0 });
		offset = pinned - os.time();
		module:log("warn", "Clock pinned to %s for testing (pim_classtime_fake_now)", fake_now);
	else
		module:log("error", "pim_classtime_fake_now must be \"YYYY-MM-DD HH:MM\"; ignoring it");
	end
end

return function()
	return os.date("*t", os.time() + offset);
end
