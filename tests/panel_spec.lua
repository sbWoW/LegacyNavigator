-- Run from the addon folder: lua tests/panel_spec.lua
-- Pure helpers of the docked panel (Panel.lua): no frames needed.
local function check(value, message) if not value then error(message or "assertion failed", 2) end end
local function eq(actual, expected, message)
	if actual ~= expected then error((message or "mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local function load(locale)
	GetLocale = function() return locale end
	local ns = {}
	for _, file in ipairs({ "Locale.lua", "Definitions.lua", "Model.lua", "Style.lua", "Panel.lua" }) do
		assert(loadfile(file))("LegacyNavigator", ns)
	end
	return ns.Panel
end
local P = load("enUS")

-- ProgressModel: bar only with a reliable denominator
local m = P.ProgressModel({ type = "points", need = 5 }, { status = "ok", goal = { need = 5, available = 3, remaining = 2 } })
check(m.bar and m.value == 3 and m.max == 5, "points bar"); eq(m.text, "3 of 5 points available")
m = P.ProgressModel({ type = "points", need = 5 }, { status = "reachable", goal = { need = 5, available = 9 } })
eq(m.value, 5, "bar value is clamped to need")
m = P.ProgressModel({ type = "points", need = 5 }, { status = "loading", goal = {} })
check(not m.bar and m.text == "", "loading: no bar, no zero")
m = P.ProgressModel({ type = "renown", level = 25 }, { status = "ok", goal = { level = 25, need = 10, remaining = 10 } })
check(m.bar and m.value == 15 and m.max == 25, "renown bar"); eq(m.text, "Renown 15 of 25")
m = P.ProgressModel({ type = "renown", level = 25 }, { status = "reachable", goal = { level = 25, need = -3, remaining = 0 } })
eq(m.value, 25, "renown reached")
m = P.ProgressModel({ type = "node", nodeID = 7 }, { status = "ok", goal = { need = 3, available = 1 } })
check(not m.bar, "node never gets a bar"); eq(m.text, "Minimum need 3 points, prerequisites unchecked")
eq(P.ProgressModel({ type = "node", nodeID = 7 }, { status = "ok", goal = {} }).text, "Minimum need, prerequisites unchecked")
eq(load("deDE").ProgressModel({ type = "node", nodeID = 7 }, { status = "ok", goal = {} }).text, "Mindestbedarf, Voraussetzungen ungeprüft")
check(not P.ProgressModel({ type = "challenge", id = 1 }, { status = "ok", goal = {} }).bar, "challenge: no bar")
check(not P.ProgressModel(nil, { status = "ok", goal = {} }).bar, "no goal")
check(not P.ProgressModel({ type = "points", need = 99 }, { status = "invalid", goal = {}, reason = "needAbove" }).bar, "invalid: no bar")
check(not P.ProgressModel({ type = "points", need = 5 }, nil).bar, "no result")

-- GoalMenuModel
local function ach(name, points, activity, cat) return { name = name, points = points, activity = activity, categoryID = cat } end
local catalogue = {
	categories = { [1] = { name = "Zeta" }, [2] = { name = "Alpha" } },
	achievements = {
		[10] = ach("Bravo", 1, "solo", 1), [11] = ach("Aardvark", 1, "solo", 1), [12] = ach("Raid Walker", 1, "raid", 2),
		[13] = ach("Unrated", 1, "unrated", 2), [14] = ach("No Points", 0, "solo", 2), [15] = ach("Done", 1, "dungeon", 2),
		[16] = ach("Dungeon", 1, "dungeon", 2),
	},
}
local settings = { activities = { solo = true, dungeon = true, raid = false, pvp = false } }
local trees = {
	[1187] = { nodes = { [5] = { currentRank = 0, maxRanks = 2 }, [3] = { currentRank = 1, maxRanks = 1 }, [4] = { maxRanks = 1 } } },
	[1188] = { incomplete = true, nodes = { [9] = { maxRanks = 1 } } },
}
local menu = P.GoalMenuModel(catalogue, settings, trees, { [15] = true })
eq(menu[1].action.kind, "clear"); eq(menu[1].text, "No goal (orientation)")
eq(menu[2].text, "Spend points…"); eq(#menu[2].children, 16); eq(menu[2].children[7].action.kind, "points"); eq(menu[2].children[7].action.a, 7)
local renown = menu[3].children
eq(renown[1].action.a, 15); eq(renown[1].text, "Level 15 (reward)"); eq(renown[4].action.a, 55)
local levels = {}
for _, e in ipairs(renown) do levels[e.action.a] = (levels[e.action.a] or 0) + 1; eq(e.action.kind, "renown") end
for lvl = 5, 65, 5 do eq(levels[lvl], 1, "renown level " .. lvl .. " exactly once") end
local challenge = menu[4]
eq(challenge.text, "Challenge…"); eq(#challenge.children, 2, "two categories hold open rated enabled challenges")
eq(challenge.children[1].text, "Alpha", "categories sorted"); eq(challenge.children[2].text, "Zeta")
eq(#challenge.children[1].children, 1); eq(challenge.children[1].children[1].action.a, 16, "completed, raid(off), unrated, no-point excluded")
eq(challenge.children[2].children[1].text, "Aardvark", "challenges sorted by name"); eq(challenge.children[2].children[2].text, "Bravo")
eq(challenge.children[2].children[1].action.kind, "challenge")
local node = menu[5]
eq(node.text, "Advantage… (unchecked)"); eq(#node.children, 1, "incomplete tree skipped"); eq(node.children[1].text, "Advantage tree 1")
local nodes = node.children[1].children
eq(#nodes, 2, "fully owned node skipped"); eq(nodes[1].action.a, 4); eq(nodes[2].action.a, 5); eq(nodes[2].text, "Advantage 5 (rank 0/2)"); eq(nodes[2].action.kind, "node")
-- no catalogue / trees -> only the always-available entries
local bare = P.GoalMenuModel(nil, nil, nil, nil)
eq(#bare, 3, "no challenge/node entries without data")
eq(load("deDE").GoalMenuModel(nil, nil, nil)[1].text, "Kein Ziel (Orientierung)")
-- enabling raid adds the raid challenge
settings.activities.raid = true
eq(#P.GoalMenuModel(catalogue, settings, trees, {})[4].children[1].children, 3, "raid enabled: 12, 15, 16")

-- SettingsModel
local s = P.SettingsModel({ settings = { activities = { dungeon = true, raid = false, pvp = false }, allowCharacterSwitch = true }, ui = { tracker = { shown = false } }, minimap = { hide = false } })
eq(#s, 6)
local byKey = {}
for _, e in ipairs(s) do byKey[e.key] = e.value end
check(byKey.dungeon and not byKey.raid and not byKey.pvp and byKey.switch and not byKey.tracker and byKey.minimap, "settings values")
check(not P.SettingsModel({ settings = { activities = {} }, ui = {}, minimap = { hide = true } })[6].value, "minimap hidden")

-- CharacterRows
local rows = P.CharacterRows({ characters = { ["R-Beta"] = { classFile = "MAGE", level = 12, capturedAt = 5, points = { available = 2 } }, ["R-Alpha"] = { level = 60 } } }, "R-Alpha", true, nil)
eq(#rows, 2); eq(rows[1].key, "R-Alpha"); eq(rows[1].state, "confirmed"); eq(rows[1].available, nil)
eq(rows[2].state, "stale"); eq(rows[2].level, 12); eq(rows[2].available, 2); eq(rows[2].classFile, "MAGE")

-- DockSide: tabs hang right of the host
eq(P.DockSide(1000, 44, 320, 1920), "right"); eq(P.DockSide(1600, 44, 320, 1920), "left"); eq(P.DockSide(1552, 44, 320, 1920), "right", "exact fit incl. gap")
eq(P.DockSide(1553, 44, 320, 1920), "left")

print("panel_spec: all checks passed")
