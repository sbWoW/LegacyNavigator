-- Minimal synthetic catalogue in Model.buildCatalogue shape. Only public game IDs; no personal data.
local function crit(id, ctype, extra)
	local c = { id = id, type = ctype, req = 1 }
	for k, v in pairs(extra or {}) do c[k] = v end
	return c
end
local function ach(id, name, activity, criteria, points)
	return { id = id, name = name, points = points or 1, categoryID = 10, activity = activity, criteria = criteria or {} }
end

local spelunker = {}
for i = 1, 6 do spelunker[i] = crit(91000 + i, 0) end

local achievements = {
	[61994] = ach(61994, "Novice Mage", "solo"),
	[62000] = ach(62000, "Novice Priest", "solo"),
	[62003] = ach(62003, "Novice Rogue", "solo"),
	[62004] = ach(62004, "Experienced Rogue", "solo"),
	[62012] = ach(62012, "Journeyman Alchemist", "solo", { crit(111540, 7, { assetID = 2937, req = 150 }) }),
	[62382] = ach(62382, "Explorer", "solo", { crit(112686, 8, { assetID = 728 }), crit(112687, 8, { assetID = 900002 }) }),
	[728] = ach(728, "Explore Durotar", "solo", { crit(831, 43), crit(832, 43) }, 0),
	[900002] = ach(900002, "Explore Nowhere Known", "solo", { crit(833, 43) }, 0), -- no zone map
	[90001] = ach(90001, "Novice Spelunker", "dungeon", spelunker),
	[90002] = ach(90002, "Raid Walker", "raid", { crit(92101, 0), crit(92102, 0) }),
	[62046] = ach(62046, "Reputation Rival", "pvp", { crit(92001, 243) }),
	[684] = ach(684, "Unrated Lair", "unrated", { crit(92201, 0), crit(92202, 0) }), -- open requirements, still never offered
	[900003] = ach(900003, "Battleground Helper", "pvp", { crit(92301, 0) }, 0),
	[90003] = ach(90003, "Lone Wanderer", "solo", { crit(93001, 0) }),
}

local M = { all = achievements }

-- subset(ids...) -> catalogue containing only these achievements (helpers of 62382 stay when 62382 is asked)
function M.subset(...)
	local cat = { build = "70205", readAt = 1000, categories = {}, achievements = {} }
	for _, id in ipairs({ ... }) do cat.achievements[id] = achievements[id] end
	return cat
end

return M
