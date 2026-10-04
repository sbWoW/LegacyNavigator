-- Run from the addon folder: lua tests/integration_spec.lua
-- O7/D16: client-shaped Provider stubs -> Core scan -> Model snapshot/persist -> Planner via Core:Replan.
local function check(value, message)
	if not value then error(message or "assertion failed", 2) end
end
local function eq(actual, expected, message)
	if actual ~= expected then
		error((message or "mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

-- Anonymized catalogue in raw client shapes. Row: GetAchievementInfo order (id, name, points, completed, ..., wasEarnedByMe).
local categories = { [15586] = { 62003, 62382, 62053, 768 }, [15593] = { 15594 }, [15620] = { 62046 }, [15626] = { 90002 } }
local function row(id, name, points) return { id, name, points, false, nil, nil, nil, nil, 0, 0, "", false, false } end
local info = {
	[62003] = row(62003, "Novice Rogue", 1), [62382] = row(62382, "Explorer", 1), [62053] = row(62053, "Explore Azeroth", 0), [768] = row(768, "Explore Tirisfal Glades", 0),
	[15594] = row(15594, "Novice Spelunker", 1), [62046] = row(62046, "Reputation Rival", 1), [90002] = row(90002, "Raid Walker", 1),
}
local function crit(text, ctype, quantity, req, assetID, id) return { text, ctype, false, quantity, req, nil, 0, assetID, "", id } end
local criteria = {
	[62003] = {}, -- level challenge: no criteria, the class milestone comes from Definitions
	[62382] = { crit("Explore Azeroth", 8, 0, 1, 62053, 112690) },
	[62053] = { crit("Tirisfal Glades", 8, 0, 1, 768, 112691) },
	[768] = { crit("Brill", 43, 0, 1, nil, 841), crit("Deathknell", 43, 0, 1, nil, 842), crit("Garrison", 43, 0, 1, nil, 843) },
	[15594] = { crit("Boss A", 0, 0, 1, nil, 93101), crit("Boss B", 0, 0, 1, nil, 93102) },
	[62046] = { crit("Faction", 243, 0, 1, nil, 92001) },
	[90002] = { crit("Raid Boss", 0, 0, 1, nil, 92101) },
}

local timers, events = {}, {}
local saved = {}
local db = { profile = { characters = {} }, global = {}, current = "Default", profiles = {} }
function db:GetCurrentProfile() return self.current end
function db:SetProfile(name) self.current = name end
function db:DeleteProfile(name) self.profiles[name] = nil end

local core
local function lib(name)
	if name == "AceAddon-3.0" then
		return { NewAddon = function(_, addonName)
			local o = { name = addonName }
			function o:RegisterEvent(event, handler) events[event] = handler or event end
			function o:RegisterChatCommand() end
			function o:Print(message) saved[#saved + 1] = message end
			function o:ScheduleTimer(fn)
				local callback = type(fn) == "string" and function() o[fn](o) end or fn
				timers[#timers + 1] = callback
				return callback
			end
			function o:ScheduleRepeatingTimer(fn) return function() o[fn](o) end end
			function o:CancelTimer() end
			core = o
			return o
		end }
	elseif name == "AceDB-3.0" then
		return { New = function() return db end }
	end
end
LibStub = lib
GetLocale = function() return "enUS" end
GetBuildInfo = function() return "1.60.1", "70205", "Oct 03 2026", 16001 end
GetTime = function() return 0 end
GetServerTime = function() return 5000 end
date = function() return "DATE" end
InCombatLockdown = function() return false end
UnitName = function() return "Alpha" end
GetRealmName = function() return "Realm" end
UnitClass = function() return "Rogue", "ROGUE", 4 end
UnitGUID = function() return "Player-Alpha" end
UnitLevel = function() return 1 end
GetCategoryList = function() return { 15586, 15593, 15620, 15626 } end
GetCategoryInfo = function(id) return "Category " .. id, -1, 0 end
GetCategoryNumAchievements = function(id) return #categories[id], 0, 0 end
GetAchievementInfo = function(a, b)
	local id = categories[a] and categories[a][b]
	if id then return table.unpack(info[id], 1, 13) end
end
GetAchievementNumCriteria = function(id) return #criteria[id] end
GetAchievementCriteriaInfo = function(id, i) return table.unpack(criteria[id][i], 1, 10) end
C_Traits = {
	GetTraitCurrencyForAchievement = function(_, id) return info[id][3] end,
	GetConfigIDByTreeID = function(tree) return 900 + tree end,
	GetTreeCurrencyInfo = function() return {} end,
	GetTreeNodes = function() return { 1 } end,
	GetTreeInfo = function() return { rootNodeID = 1, cannotRefund = true } end,
	GetNodeInfo = function() return { ID = 1, currentRank = 0, maxRanks = 1, conditionIDs = {} } end,
	GetNodeCost = function() return { { ID = 4225, amount = 1 } } end,
}
C_MajorFactions = { GetCurrentRenownLevel = function() return 0 end }
C_SkillInfo = { GetNumSkillLines = function() return 0 end }
C_Map = { GetBestMapForUnit = function() return 1411 end }

local ns = {}
for _, file in ipairs({ "Locale.lua", "Definitions.lua", "Model.lua", "Planner.lua", "Provider.lua", "Tracker.lua", "Core.lua" }) do
	assert(loadfile(file))("LegacyNavigator", ns)
end
core:OnInitialize()
core:OnEnable()
core[events.PLAYER_ENTERING_WORLD](core)
for _ = 1, 5000 do
	if #timers == 0 then break end
	table.remove(timers, 1)()
end

-- Snapshot persisted through the Core scan path.
local alpha = db.profile.characters["Realm-Alpha"]
check(alpha and alpha.state == "confirmed" and alpha.classFile == "ROGUE" and alpha.level == 1, "snapshot not persisted")
eq(alpha.criteria[841].done, false, "area criterion not stored")
eq(core.states.account, "confirmed")

-- Plan via Core:Replan.
local result = core.lastResult
eq(result.status, "ok", "plan status")
-- D19: the smallest relative remainder leads within an activity: Novice Rogue 24/25 = 0.96 precedes the Explorer
-- card 3/3 = 1.0; the level-1 rogue gets its own class challenge, no other class's.
local novice
for _, c in ipairs(result.cards) do
	if c.achievementID == 62003 then novice = c end
end
check(novice and novice.missing.kind == "level" and novice.missing.n == 24, "Novice Rogue card missing")
local explorer
for _, list in ipairs({ result.cards, result.alternatives }) do
	for _, c in ipairs(list) do if c.achievementID == 62382 then explorer = c end end
end
check(explorer, "explorer card missing")
eq(explorer.missing.n, 3, "explorer counts open leaf areas through a 2-level chain")
eq(explorer.missing.total, 3, "explorer total = all areas")
local pos = {}
for i, c in ipairs(result.cards) do pos[c.achievementID] = i end
check(pos[62003] and (not pos[62382] or pos[62003] < pos[62382]), "Novice Rogue (0.96) must precede Explorer (1.0)")
for _, c in ipairs(result.cards) do
	check(c.achievementID ~= 62046 and c.achievementID ~= 90002, "pvp/raid card offered by default")
end

-- Pin toggling changes result.pinned; a planner error keeps lastResult.
local first = result.cards[1]
core:TogglePin(first)
eq(core.lastResult.pinned.achievementID, first.achievementID, "pin not in result")
core:TogglePin(first)
eq(core.lastResult.pinned, nil, "unpin not in result")
core:TogglePin({ achievementID = 62003, charKey = "Realm-Alpha", action = "spend" })
eq(db.profile.pinned, nil, "non-pin card was pinned")
local good = core.lastResult
core.forcePlanError = true
core:Replan()
eq(core.lastResult, good, "planner error dropped lastResult")
check(core.planError, "planError not set")

-- Etappe 4: Core clears the pin when it reports completion; the render payload carries the one-shot event.
do
	local payloads = {}
	ns.Tracker.Render = function(p) payloads[#payloads + 1] = p end -- the real Render needs frames
	core:TogglePin(result.cards[1])
	local pinnedID = db.profile.pinned.achievementID
	info[pinnedID][4] = true -- the client now reports it completed (points > 0 in the fixture)
	core:StartScan()
	for _ = 1, 5000 do
		if #timers == 0 then break end
		table.remove(timers, 1)()
	end
	eq(db.profile.pinned, nil, "completed pin must be cleared by Core")
	local last = payloads[#payloads]
	check(last.completed and last.completed.kind == "completed" and last.completed.achievementID == pinnedID, "payload carries completed event")
	info[pinnedID][4] = false
end

-- D22: Zum Legacy-Fenster. Blizzard globals are stubbed; Provider is the only caller.
do
	local calls, renown, combat, shownFrame = {}, 0, false, false
	local function reset() for k in pairs(calls) do calls[k] = nil end; saved = {}; core.previewNoted = nil end
	local function count(name) return calls[name] or 0 end
	local function hit(name) calls[name] = count(name) + 1 end
	InCombatLockdown = function() return combat end
	C_MajorFactions.GetCurrentRenownLevel = function() return renown end
	LegacySystemFrame = { IsShown = function() return shownFrame end }
	ToggleLegacySystemUI = function() hit("toggle") end
	C_AddOns = { LoadAddOn = function() hit("load"); return true end }
	ShowUIPanel = function() hit("show") end
	LEGACY_MICRO_BUTTON_LOCKED_TOOLTIP = "Earn a point."
	local P = ns.Provider
	db.profile.settings = { activities = {}, preview = false } -- the stub db has no AceDB defaults

	combat = true
	local ok, reason = P.openLegacyWindow()
	check(ok == false and reason == "combat" and count("toggle") + count("show") == 0, "combat must refuse")
	eq(core:LegacyBlock(), "combat", "button blocked in combat")
	combat = false
	eq(core:LegacyBlock(), nil, "locked: button not blocked (D24)")

	renown = 3
	ok = P.openLegacyWindow()
	check(ok and count("toggle") == 1, "unlocked must call ToggleLegacySystemUI")
	shownFrame = true; P.openLegacyWindow()
	eq(count("toggle"), 1, "already shown must not toggle it closed")
	shownFrame = false

	reset(); renown = 0
	ok, reason = P.openLegacyWindow()
	check(ok and reason == nil and count("load") == 1 and count("show") == 1 and count("toggle") == 0, "locked opens anyway: load + show")
	LegacySystemFrame_LoadUI = function() hit("loadui") end
	P.openLegacyWindow()
	eq(count("loadui"), 1, "LegacySystemFrame_LoadUI preferred"); eq(count("load"), 1)
	LegacySystemFrame_LoadUI = nil
	reset(); core:OpenLegacyWindow()
	eq(#saved, 0, "locked open prints nothing")

	ShowUIPanel = function() error("boom") end
	reset()
	ok, reason = P.openLegacyWindow()
	check(ok == false and reason == "error", "ShowUIPanel error handled")
	check(pcall(core.OpenLegacyWindow, core), "Core must not throw")
	check(saved[#saved]:find("boom"), "error message shown")
	core:SetSetting("preview", "on")
	check(saved[#saved]:find("Usage"), "preview setting is gone")
end

-- Tracker.Content (pure): selection logic without frames.
do
	local T = ns.Tracker
	local function data(over)
		local d = {
			profile = { characters = { ["Realm-Beta"] = { classFile = "MAGE" } } }, currentKey = "Realm-Alpha",
			catalogue = { achievements = { [1] = { name = "One" }, [2] = { name = "Two" }, [3] = { name = "Three" }, [4] = { name = "Four" } } },
			result = { cards = {}, alternatives = {}, ["local"] = {} },
		}
		for k, v in pairs(over or {}) do d[k] = v end
		return d
	end
	local function opp(id, key) return { achievementID = id, charKey = key or "Realm-Alpha", missing = { kind = "criteria", n = 2, ctype = "area" } } end
	eq(T.Content(data()), nil, "empty -> nil")
	eq(T.Content(nil), nil, "no payload -> nil")

	local d = data()
	d.profile.pinned = { achievementID = 1, charKey = "Realm-Alpha" }
	local c = T.Content(d)
	check(c and c.pinnedLine and c.pinnedLine.text:find("One", 1, true), "pin -> pinned line")
	eq(#c.localLines, 0)

	d.profile.pinned = { achievementID = 1, charKey = "Realm-Beta" }
	c = T.Content(d)
	eq(c.pinnedLine.charKey, "Realm-Beta", "twink pin carries charKey")
	check(c.pinnedLine.text:find("Beta", 1, true), "twink name shown")

	d.result["local"] = { opp(1), opp(2), opp(3), opp(4, "Realm-Beta") }
	c = T.Content(d)
	eq(#c.localLines, 2, "max 2 local lines")
	check(c.localLines[1].text:find("Two", 1, true) and c.localLines[2].text:find("Three", 1, true), "pin excluded, order kept")
	d.profile.pinned = nil
	d.result["local"] = { opp(4, "Realm-Beta") }
	eq(T.Content(d), nil, "other character's local ignored")

	d.completed = { kind = "completed", achievementID = 1, charKey = "Realm-Alpha" }
	d.result.cards = { { action = "pin", achievementID = 1, charKey = "Realm-Alpha" }, { action = "pin", achievementID = 2, charKey = "Realm-Alpha" } }
	c = T.Content(d)
	check(c and c.completed and c.completed.text:find("One", 1, true), "completed state")
	eq(c.completed.nextCard.achievementID, 2, "next skips the completed challenge")
	check(c.completed.nextText:find("Two", 1, true), "next text")
	eq(c.pinnedLine, nil, "no pin after completion")

	d.result["local"] = { opp(2), opp(3) }
	c = T.Content(d)
	eq(#c.localLines, 1, "next card excluded from local lines")
	eq(c.localLines[1].card.achievementID, 3)

	d.result.cards = { { action = "pin", achievementID = 1, charKey = "Realm-Alpha" } }
	d.result["local"] = {}
	c = T.Content(d)
	check(c and c.completed and c.completed.nextCard == nil, "no next card -> completed without nextCard")
	d.completed = nil
	eq(T.Content(d), nil, "event dropped, nothing left -> nil (tracker hides)")
end

print("integration_spec: all assertions passed")
