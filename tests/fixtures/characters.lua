-- Synthetic character states and planner input builder. Names are placeholders.
local M = {}

-- char(catalogue, { classFile, level, skills, points, state, capturedAt, done = { criterionID, ... } })
function M.char(catalogue, o)
	o = o or {}
	local char = {
		state = o.state or "confirmed", capturedAt = o.capturedAt or 1000, build = "70205", guid = "Player-0",
		classFile = o.classFile or "MAGE", level = o.level or 1, skills = o.skills or {},
		points = o.points or { available = 0, spent = 0 }, criteria = {},
	}
	for _, ach in pairs(catalogue.achievements) do
		for _, c in ipairs(ach.criteria) do char.criteria[c.id] = { q = 0, done = false } end
	end
	for _, id in ipairs(o.done or {}) do char.criteria[id] = { q = 1, done = true } end
	if o.criteria == false then char.criteria = nil end
	return char
end

-- input(ns, catalogue, characters, overrides)
function M.input(ns, catalogue, characters, o)
	local acts = {}
	for k, v in pairs(ns.Definitions.defaultActivities) do acts[k] = v end
	local input = {
		now = 2000, definitions = ns.Definitions, catalogue = catalogue,
		account = { state = "confirmed", completed = {}, renown = 0, build = "70205" },
		characters = characters, currentChar = "Realm-Alpha",
		settings = { activities = acts, allowCharacterSwitch = true },
	}
	for k, v in pairs(o or {}) do input[k] = v end
	return input
end

return M
