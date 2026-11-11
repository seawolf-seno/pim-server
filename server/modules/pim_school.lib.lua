-- pim_school: load pim-seed's school.json for a module. Shared by
-- mod_pim_classtime and mod_pim_classroom; load it with module:require("pim_school"),
-- which runs this file with the calling module as `module`.

local json = require "util.json";

return function(path)
	if not path then
		module:log("error", "pim_school_file is not set; pim's school features are off");
		return nil;
	end
	local f, err = io.open(path, "r");
	if not f then
		module:log("error", "Can't read pim_school_file: %s", err);
		return nil;
	end
	local text = f:read("*a");
	f:close();
	local data, decode_err = json.decode(text);
	if type(data) ~= "table" or type(data.schedule) ~= "table" or type(data.classes) ~= "table"
		or type(data.people) ~= "table" or type(data.domain) ~= "string" then
		module:log("error", "pim_school_file is not a pim-seed school.json: %s", tostring(decode_err));
		return nil;
	end
	-- Counts only: names never go in the log.
	module:log("info", "Loaded school: %d classes, %d activities", #data.classes, #(data.activities or {}));
	return data;
end
