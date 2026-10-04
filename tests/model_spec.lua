-- Run from the addon folder: lua tests/model_spec.lua
local function check(value, message)
	if not value then error(message or "assertion failed", 2) end
end
local function eq(actual, expected, message)
	if actual ~= expected then
		error((message or "mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

----------------------------------------------------------------------------------------------------
-- Part A: Model and Definitions load without any WoW global (no API access possible).
----------------------------------------------------------------------------------------------------
local ns = {}
assert(loadfile("Definitions.lua"))("LegacyNavigator", ns)
assert(loadfile("Model.lua"))("LegacyNavigator", ns)
local Model, def = ns.Model, ns.Definitions

local function rawAch(id, completed, criteria, legacyPoints, categoryID)
	return { id = id, completed = completed, legacyPoints = legacyPoints, categoryID = categoryID or 10, criteria = criteria or {} }
end
local function rawScan(overrides)
	local raw = {
		key = "Realm-Alpha", guid = "Player-1", classFile = "MAGE", level = 12, build = "70205",
		skills = { [2937] = { rank = 20, max = 75 } }, renown = 0, points = { available = 0, spent = 0 },
		achievementsComplete = true, categories = { [10] = { name = "Cat", parentID = -1 } },
		achievements = {
			rawAch(101, false, { { id = 5001, type = 7, assetID = 2937, req = 150, done = false, quantity = 0 } }, 1),
			rawAch(102, true, { { id = 5002, type = 0, done = true, quantity = 1 } }, 0),
		},
	}
	for key, value in pairs(overrides or {}) do raw[key] = value end
	return raw
end

-- Account-complete rule: completed == true counts, regardless of wasEarnedByMe; nil is unknown.
eq(Model.isAccountComplete({ completed = true, wasEarnedByMe = false }), true, "completed by another character")
eq(Model.isAccountComplete({ completed = false, wasEarnedByMe = true }), false, "not completed")
eq(Model.isAccountComplete({}), nil, "missing completed must stay unknown")

-- nil is never 0.
do
	local snap = Model.snapshot(rawScan({ points = false, renown = false }), 1000)
	check(snap.character.points == nil, "unread points became a value")
	check(snap.account.renown == nil, "unread renown became a value")
	check(snap.incomplete.points and snap.incomplete.account, "missing reads were not reported")
	local zero = Model.snapshot(rawScan(), 1000)
	eq(zero.character.points.available, 0, "a confirmed 0 must stay 0")
	eq(zero.account.renown, 0, "a confirmed renown 0 must stay 0")
	local unknown = Model.snapshot(rawScan({ skills = false }), 1000)
	check(unknown.character.skills == nil, "unread skills became a table")
	local noQuantity = Model.snapshot(rawScan({ achievements = { rawAch(7, false, { { id = 9, type = 0, done = false } }, 1) } }), 1000)
	check(noQuantity.incomplete.character and noQuantity.character.criteria[9] == nil, "criterion without quantity was stored (3)")
	local noDone = Model.snapshot(rawScan({ achievements = { rawAch(7, false, { { id = 9, type = 0 } }, 1) } }), 1000)
	check(noDone.incomplete.character and noDone.character.criteria[9] == nil, "criterion without completed flag was stored")
end

-- Points: an assumed 0 is only confirmed by renown 0; missing spent is incomplete (1).
do
	local assumed = { available = 0, spent = 0, assumed = true }
	check(not Model.snapshot(rawScan({ points = assumed }), 1000).incomplete.points, "assumed 0 with renown 0 must pass")
	check(Model.snapshot(rawScan({ points = assumed, renown = 3 }), 1000).incomplete.points, "assumed 0 with renown > 0 accepted")
	check(Model.snapshot(rawScan({ points = assumed, renown = false }), 1000).incomplete.points, "assumed 0 with unknown renown accepted")
	check(Model.snapshot(rawScan({ points = { available = 2 } }), 1000).incomplete.points, "missing spent accepted")
end

-- Non-number time is incomplete (4); a catalogue with unknown points is incomplete (11); "ignore" is excluded (12).
do
	check(Model.snapshot(rawScan(), nil).incomplete.character, "nil time accepted")
	local raw = rawScan({ achievements = { rawAch(7, false, {}, nil), rawAch(8, false, {}, 1, 15425) } })
	local catalogue = Model.buildCatalogue(raw, def)
	check(catalogue.incomplete, "nil legacyPoints not flagged")
	check(catalogue.achievements[8] == nil and catalogue.achievements[7], "ignore category not excluded")
	local categories = { [10] = { parentID = -1 } }
	local function cat(id) return Model.activityFor({ id = 1, categoryID = id, criteria = {} }, categories, def) end
	eq(cat(15593), "dungeon"); eq(cat(15626), "raid"); eq(cat(15590), "solo"); eq(cat(15585), "solo")
	eq(cat(15620), "pvp"); eq(cat(15425), "ignore")
	eq(Model.activityFor({ id = 684, categoryID = 15593, criteria = {} }, categories, def), "unrated", "override must win")
end

-- Snapshot content.
do
	local snap = Model.snapshot(rawScan(), 1000)
	check(snap.account.completed[102] and not snap.account.completed[101], "completed map wrong")
	eq(snap.character.criteria[5001].q, 0, "criterion progress")
	eq(snap.character.criteria[5002].done, true, "criterion done")
	check(Model.isComplete(snap), "complete scan reported incomplete")
end

-- Incomplete snapshots are not written and never replace a complete one.
do
	local store = { characters = {} }
	check(Model.persist(store, Model.snapshot(rawScan(), 1000)), "complete snapshot was refused")
	eq(store.characters["Realm-Alpha"].capturedAt, 1000, "complete snapshot not stored")
	local ok = Model.persist(store, Model.snapshot(rawScan({ renown = false }), 2000))
	check(not ok and store.characters["Realm-Alpha"].capturedAt == 1000 and store.account.capturedAt == 1000, "incomplete snapshot overwrote")
	check(not Model.persist(store, Model.snapshot(rawScan({ achievementsComplete = false }), 2000)), "partial achievement scan was stored")
	check(not Model.persist(store, Model.snapshot(rawScan({ key = false }), 2000)), "snapshot without character key was stored")
	check(Model.persist({}, Model.snapshot(rawScan({ skills = false }), 3000)), "unreadable skills must not block the snapshot")
	-- (2) unreadable skills keep the stored ones; raw is not mutated
	local raw = rawScan({ skills = false })
	check(Model.persist(store, Model.snapshot(raw, 4000)) and raw.skills == false, "skills-less snapshot refused or raw mutated")
	eq(store.characters["Realm-Alpha"].capturedAt, 4000)
	eq(store.characters["Realm-Alpha"].skills[2937].rank, 20, "stored skills were erased")
	-- O4: carried-over skills keep their OLD stamp and are stale; fresh ones are confirmed with the new stamp
	eq(store.characters["Realm-Alpha"].skills.capturedAt, 1000, "carried-over skills got a fresh date")
	eq(store.characters["Realm-Alpha"].skills.state, "stale")
	check(Model.persist(store, Model.snapshot(rawScan(), 5000)), "fresh scan refused")
	eq(store.characters["Realm-Alpha"].skills.capturedAt, 5000); eq(store.characters["Realm-Alpha"].skills.state, "confirmed")
end

-- O2: per-character earned evidence for completed achievements; account rule unchanged.
do
	local mine = rawAch(102, true, {}, 0); mine.wasEarnedByMe = true
	local other = rawAch(103, true, {}, 1); other.wasEarnedByMe = false; other.earnedBy = "Someone"
	local open = rawAch(104, false, {}, 1); open.wasEarnedByMe = false
	local unknown = rawAch(105, true, {}, 1)
	local snap = Model.snapshot(rawScan({ achievements = { mine, other, open, unknown } }), 1000)
	eq(snap.character.earnedByMe[102].me, true)
	eq(snap.character.earnedByMe[103].me, false); eq(snap.character.earnedByMe[103].by, "Someone")
	eq(snap.character.earnedByMe[104], nil, "open achievement has no evidence")
	eq(snap.character.earnedByMe[105], nil, "unread evidence stays nil")
	eq(snap.account.completed[103], true, "completed by another character still counts account-wide")
end

-- Pin helpers.
do
	local profile = {}
	local p = Model.togglePin(profile, { achievementID = 7, charKey = "Realm-Alpha" }, 111)
	eq(profile.pinned, p); eq(p.achievementID, 7); eq(p.charKey, "Realm-Alpha"); eq(p.pinnedAt, 111)
	p = Model.togglePin(profile, { achievementID = 8, charKey = "Realm-Beta" }, 222)
	eq(p.achievementID, 8, "other achievement replaces"); eq(profile.pinned.pinnedAt, 222)
	eq(Model.togglePin(profile, { achievementID = 8, charKey = "Realm-Alpha" }, 333), nil, "same achievement unpins")
	eq(profile.pinned, nil)

	local cat = { achievements = { [7] = { points = 1 }, [8] = { points = 0 } } }
	local pin = { achievementID = 7 }
	eq(Model.pinCompleted({}, { [7] = true }, pin, cat), true)
	eq(Model.pinCompleted({ [7] = true }, { [7] = true }, pin, cat), false, "already complete before")
	eq(Model.pinCompleted({}, {}, pin, cat), false, "not complete")
	eq(Model.pinCompleted({}, { [7] = true }, nil, cat), false, "nothing pinned")
	eq(Model.pinCompleted({}, { [8] = true }, { achievementID = 8 }, cat), false, "0 points")
	eq(Model.pinCompleted({}, { [9] = true }, { achievementID = 9 }, cat), false, "not in catalogue")
	eq(Model.pinCompleted(nil, { [7] = true }, pin, cat), true, "no before set")
end

-- State transitions: unknown -> loading/stale -> confirmed; incomplete keeps the old state.
do
	local states = Model.newStates()
	for _, domain in ipairs(Model.DOMAINS) do eq(states[domain], "unknown", domain) end
	local store = { account = { capturedAt = 1 }, characters = { ["Realm-Alpha"] = { points = { available = 1 } } } }
	Model.beginSession(states, store, "Realm-Alpha")
	eq(states.account, "stale"); eq(states.character, "stale"); eq(states.points, "stale"); eq(states.location, "loading")
	Model.applyScan(states, { points = { "currency" } }, false)
	eq(states.account, "stale", "unsaved scan must not confirm (6)"); eq(states.location, "confirmed")
	Model.applyScan(states, { points = { "currency" } }, true)
	eq(states.account, "confirmed"); eq(states.character, "confirmed"); eq(states.points, "stale", "incomplete domain changed state")
	eq(states.location, "confirmed")
	local fresh = Model.newStates()
	Model.beginSession(fresh, { characters = {} }, "Realm-New")
	for _, domain in ipairs(Model.DOMAINS) do eq(fresh[domain], "loading", domain) end
	Model.applyScan(fresh, { account = { "x" }, location = { "map" } }, true)
	eq(fresh.account, "loading"); eq(fresh.character, "confirmed"); eq(fresh.location, "loading")
end

-- Other characters are stale with timestamp and build; only the current one can be confirmed.
do
	local store = { characters = {
		["Realm-Alpha"] = { capturedAt = 10, build = "70205" },
		["Realm-Beta"] = { capturedAt = 20, build = "70124" },
	} }
	local list = Model.listCharacters(store, "Realm-Alpha", true, "70205")
	eq(#list, 2); eq(list[1].key, "Realm-Alpha"); eq(list[1].state, "confirmed")
	eq(list[2].state, "stale", "other character must be stale"); eq(list[2].capturedAt, 20)
	check(list[2].buildMismatch and not list[1].buildMismatch, "build mismatch not detected")
	eq(Model.listCharacters(store, "Realm-Alpha", false, "70205")[1].state, "stale", "unconfirmed current is stale")
end

-- Activities and Definitions facts.
do
	local categories = { [15595] = { parentID = -1 }, [15600] = { parentID = 15595 }, [10] = { parentID = -1 } }
	eq(Model.activityFor({ id = 1, categoryID = 15600, criteria = {} }, categories, def), "pvp", "PvP subtree")
	eq(Model.activityFor({ id = 684, categoryID = 10, criteria = {} }, categories, def), "unrated", "Onyxia")
	eq(Model.activityFor({ id = 62054, categoryID = 10, criteria = {} }, categories, def), "unrated", "Valthalak")
	eq(Model.activityFor({ id = 61994, categoryID = 10, criteria = {} }, categories, def), "solo", "class challenge")
	eq(Model.activityFor({ id = 5, categoryID = 10, criteria = { { type = 0 }, { type = 0 } } }, categories, def), "unrated", "boss kills unmaintained")
	eq(def.classMilestones[61994].class, "MAGE"); eq(def.classMilestones[61994].level, 25)
	eq(def.classMilestones[61996].level, 60); eq(def.classMilestones[62011].class, "WARLOCK")
	check(def.defaultActivities.dungeon and def.defaultActivities.solo and not def.defaultActivities.raid and not def.defaultActivities.pvp, "default activities")
	local catalogue = Model.buildCatalogue(rawScan(), def)
	local total, withPoints = Model.counts(catalogue)
	eq(total, 2); eq(withPoints, 1)
end

----------------------------------------------------------------------------------------------------
-- Part B: Core + Provider smoke test with stubbed client and Ace libraries.
----------------------------------------------------------------------------------------------------
local function fixture(options)
	options = options or {}
	local h = { timers = {}, repeating = {}, messages = {}, events = {}, ready = options.ready ~= false, combat = false, writeCalls = 0, diagCalls = {} }
	local items = { [9] = {}, [10] = { 101, 102 }, [11] = { 61994 } }
	local info = {
		[101] = { 101, "Journeyman", 1, false, nil, nil, nil, nil, 0, 0, "", false, false },
		[102] = { 102, "Explore", 0, true, nil, nil, nil, nil, 0, 0, "", false, true },
		[61994] = { 61994, "Novice Mage", 1, false, nil, nil, nil, nil, 0, 0, "", false, false },
	}
	local criteria = {
		[101] = { { "150 Alchemy", 7, false, 20, 150, nil, 1, 2937, "", 5001 } },
		[102] = { { "Deathknell", 8, true, 1, 1, nil, 0, 62053, "", 5002 } },
		[61994] = {},
	}
	h.db = options.db or { profile = { characters = {} }, global = {}, current = "Default", profiles = {} }
	h.db.GetCurrentProfile = function(db) return db.current end
	h.db.SetProfile = function(db, name) db.current = name end
	h.db.DeleteProfile = function(db, name) assert(db.current ~= name, "active profile"); db.profiles[name] = nil end
	local function lib(name)
		if name == "AceAddon-3.0" then
			return { NewAddon = function(_, addonName)
				local o = { name = addonName, commands = {} }
				function o:RegisterEvent(event, handler) h.events[event] = handler or event end
				function o:RegisterChatCommand(command, handler) o.commands[command] = handler end
				function o:Print(message) table.insert(h.messages, message) end
				function o:ScheduleTimer(fn, delay)
					local callback = fn
					if type(fn) == "string" then callback = function() o[fn](o) end end
					local timer = { fn = callback, delay = delay }
					table.insert(h.timers, timer)
					return timer
				end
				function o:ScheduleRepeatingTimer(fn) local t = { fn = function() o[fn](o) end }; h.repeating[t] = true; return t end
				function o:CancelTimer(timer) h.repeating[timer] = nil; timer.cancelled = true end
				h.core = o
				return o
			end }
		elseif name == "AceDB-3.0" then
			return { New = function() return h.db end }
		end
	end
	LibStub = lib
	GetLocale = function() return "enUS" end
	GetBuildInfo = function() return "1.60.1", "70205", "Oct 03 2026", 16001 end
	IsBetaBuild = function() return true end
	IsPublicTestClient = function() return false end
	GetTime = function() return h.clock or 0 end
	GetServerTime = function() return h.now or 5000 end
	date = function() return "DATE" end
	InCombatLockdown = function() return h.combat end
	UnitName = function() return options.name or "Alpha" end
	GetRealmName = function() return "Realm" end
	UnitClass = function() return "Mage", "MAGE", 8 end
	UnitGUID = function() return "Player-" .. (options.name or "Alpha") end
	UnitLevel = function() return 12 end
	GetCategoryList = function() return { 9, 10, 11 } end
	GetCategoryInfo = function(id) return "Category " .. id, -1, 0 end
	GetCategoryNumAchievements = function(id) return #items[id], 0, 0 end
	GetAchievementInfo = function(a, b)
		if not h.ready then return nil end
		if type(b) ~= "number" then return nil end
		local id = items[a] and items[a][b]
		if not id then return nil end
		local row = info[id]
		return table.unpack(row, 1, 13)
	end
	GetAchievementNumCriteria = function(id) return #criteria[id] end
	GetAchievementCriteriaInfo = function(id, i) return table.unpack(criteria[id][i], 1, 10) end
	C_Traits = {
		GetTraitCurrencyForAchievement = function(_, id) return info[id][3] end,
		GetConfigIDByTreeID = function(tree) if h.ready then return 900 + tree end end,
		GetTreeCurrencyInfo = function() if not options.currencyNil then return {} end end,
		GetTreeNodes = function() return { 1 } end,
		GetTreeInfo = function() return { rootNodeID = 1, cannotRefund = true } end,
		GetNodeInfo = function() return { ID = 1, currentRank = 0, maxRanks = 1, conditionIDs = { 7 } } end,
		GetNodeCost = function() return { { ID = 4225, amount = 1 } } end,
		GetConditionInfo = function() return { type = 0, spentAmountRequired = 5, isMet = false } end,
		PurchaseRank = function() h.writeCalls = h.writeCalls + 1 end,
		CommitConfig = function() h.writeCalls = h.writeCalls + 1 end,
	}
	C_MajorFactions = { GetCurrentRenownLevel = function() if not options.renownNil then return 0 end end }
	C_SkillInfo = {
		GetNumSkillLines = function() return 1 end,
		GetSkillLineInfo = function() return { skillID = 2937, rank = 20, maxRank = 75, isHeader = false } end,
	}
	C_Map = { GetBestMapForUnit = function() return 1411 end, SetUserWaypoint = function() h.writeCalls = h.writeCalls + 1 end }

	h.ns = {}
	for _, file in ipairs({ "Locale.lua", "Definitions.lua", "Model.lua", "Planner.lua", "Provider.lua", "Core.lua" }) do
		h.ns.Diag = { HandleSlash = function(input) table.insert(h.diagCalls, input) end }
		assert(loadfile(file))("LegacyNavigator", h.ns)
	end
	h.ns.Diag = { HandleSlash = function(input) table.insert(h.diagCalls, input) end }
	local core = h.core
	core:OnInitialize()
	core:OnEnable()
	function h:fire(event, ...) local handler = self.events[event]; if type(handler) == "string" then core[handler](core, event, ...) else handler(core, event, ...) end end
	function h:drain()
		local steps = 0
		while #self.timers > 0 do
			steps = steps + 1
			assert(steps < 5000, "timer loop did not drain")
			local timer = table.remove(self.timers, 1)
			if not timer.cancelled then timer.fn() end
		end
	end
	function h:poll() for timer in pairs(self.repeating) do timer.fn() end end
	function h:text() return table.concat(self.messages, "\n") end
	h.states = core.states
	return h
end

-- Login with a late-ready client: poll only, no readiness event; loading until ready, then confirmed.
do
	local h = fixture({ ready = false })
	h:fire("PLAYER_ENTERING_WORLD")
	for _, domain in ipairs(Model.DOMAINS) do eq(h.states[domain], "loading", domain) end
	for _ = 1, 5 do h:poll() end
	h:drain()
	eq(h.states.account, "loading", "scanned before ready")
	check(next(h.db.profile.characters) == nil, "stored before ready")
	h.ready = true
	h:poll(); h:drain()
	for _, domain in ipairs(Model.DOMAINS) do eq(h.states[domain], "confirmed", domain) end
	local alpha = h.db.profile.characters["Realm-Alpha"]
	check(alpha and alpha.state == "confirmed" and alpha.build == "70205", "character not persisted")
	eq(alpha.criteria[5001].q, 20, "criterion progress"); eq(alpha.points.available, 0)
	eq(alpha.skills[2937].rank, 20)
	check(h.db.profile.account.completed[102], "account completion not stored")
	check(next(h.repeating) == nil, "poll kept running after ready")
	h.core:OnSlash("status")
	local text = h:text()
	check(text:find("account=confirmed", 1, true) and text:find("Catalogue: 3 achievements, 2 with points", 1, true), "status counts missing")
	check(text:find("Realm-Alpha: confirmed", 1, true), "known character missing in status")
	check(text:find("Trees read: 3/3", 1, true), "trees not read")
	eq(h.writeCalls, 0, "write API called")
end

-- Readiness event accelerates the poll; PEW twice scans once.
do
	local h = fixture()
	h:fire("PLAYER_ENTERING_WORLD"); h:fire("PLAYER_ENTERING_WORLD")
	h:drain()
	eq(h.states.account, "confirmed")
end

-- /reload and other characters: stored data is stale first, then confirmed; the other character stays stale.
do
	local first = fixture({ name = "Alpha" })
	first:fire("PLAYER_ENTERING_WORLD"); first:drain()
	local second = fixture({ name = "Beta", db = first.db })
	second:fire("PLAYER_ENTERING_WORLD")
	eq(second.states.account, "stale", "stored account must show stale at once")
	eq(second.states.character, "loading", "Beta has no stored state")
	second:drain()
	eq(second.states.character, "confirmed")
	second.core:OnSlash("status")
	local text = second:text()
	check(text:find("Realm-Alpha: stale, DATE", 1, true), "other character not stale")
	check(text:find("Realm-Beta: confirmed", 1, true), "current character not confirmed")
	local reload = fixture({ name = "Alpha", db = first.db })
	reload:fire("PLAYER_ENTERING_WORLD")
	eq(reload.states.character, "stale", "reload shows stored state as stale")
	reload:drain()
	eq(reload.states.character, "confirmed")
end

-- Character sticky-mapped to the old dev profile ends on "Default" and the old profile is gone.
do
	local old = fixture({ name = "Old", db = { profile = { characters = {} }, global = {}, current = "16001-beta", profiles = { ["16001-beta"] = {} } } })
	eq(old.db.current, "Default", "not moved to Default")
	check(old.db.profiles["16001-beta"] == nil, "old profile not deleted")
end

-- Incomplete scan (renown unreadable) writes nothing and keeps the old state.
do
	local good = fixture({ name = "Alpha" })
	good:fire("PLAYER_ENTERING_WORLD"); good:drain()
	local bad = fixture({ name = "Gamma", db = good.db, renownNil = true })
	bad:fire("PLAYER_ENTERING_WORLD"); bad:drain()
	check(good.db.profile.characters["Realm-Gamma"] == nil, "incomplete snapshot was written")
	eq(bad.states.account, "stale", "incomplete account domain must keep the stale state")
	check(bad:text():find("snapshot not saved", 1, true), "incomplete scan not announced")
	local noPoints = fixture({ name = "Delta", db = good.db, currencyNil = true })
	noPoints:fire("PLAYER_ENTERING_WORLD"); noPoints:drain()
	check(good.db.profile.characters["Realm-Delta"] == nil and noPoints.states.points == "loading", "nil points treated as 0")
end

-- (9) Poll deadline is elapsed time, events do not consume it; a late event after it still starts the scan.
do
	local h = fixture({ ready = false })
	h:fire("PLAYER_ENTERING_WORLD")
	for _ = 1, 100 do h:fire("RECEIVED_ACHIEVEMENT_LIST"); h:poll() end
	check(next(h.repeating) ~= nil, "poll expired by count instead of time")
	h.clock = 31; h:poll()
	check(next(h.repeating) == nil, "poll did not expire at 30 s")
	h.ready = true
	h:fire("RECEIVED_ACHIEVEMENT_LIST"); h:drain()
	eq(h.states.account, "confirmed", "late event did not start the scan")
end

-- (7) CRITERIA_UPDATE during the first scan (currentKey unset) causes one follow-up rescan.
-- (11) A scan with unreadable categories keeps the previous catalogue. (8) A tree without node cost is incomplete.
do
	local h = fixture()
	local builds = 0
	local build = h.ns.Provider.build
	h.ns.Provider.build = function() builds = builds + 1; return build() end
	h:fire("PLAYER_ENTERING_WORLD")
	check(h.core.scan and not h.core.currentKey, "test setup: first scan should be running")
	h:fire("CRITERIA_UPDATE"); h:drain()
	eq(builds, 2, "no follow-up rescan after CRITERIA_UPDATE during a scan")
	local catalogue = h.core.catalogue
	check(catalogue, "no catalogue")
	local list = GetCategoryList
	check(h.ns.Provider.isReady(), "not ready with empty parent category first")
	GetCategoryList = function() return { 9 } end
	check(not h.ns.Provider.isReady(), "ready although every category is empty")
	GetCategoryList = function() return nil end
	h.core:StartScan(); h:drain()
	check(h.core.catalogue == catalogue, "incomplete scan replaced the catalogue")
	GetCategoryList = list
	C_Traits.GetNodeCost = function() end
	h.core:StartScan(); h:drain()
	check(h.core.trees[1187].incomplete, "tree with failed node cost not flagged")
	h.messages = {}
	h.core:OnSlash("status")
	check(h:text():find("Trees read: 0/3", 1, true), "incomplete trees counted as read")
end

-- Combat: the scan waits and resumes at PLAYER_REGEN_ENABLED.
do
	local h = fixture()
	h.combat = true
	h:fire("PLAYER_ENTERING_WORLD"); h:drain()
	eq(h.states.account, "loading", "scanned in combat")
	h.combat = false
	h:fire("PLAYER_REGEN_ENABLED"); h:drain()
	eq(h.states.account, "confirmed")
	-- pause in the middle of a scan
	h.combat = false
	h.core:StartScan()
	table.remove(h.timers, 1).fn()
	h.combat = true
	h:drain()
	check(h.core.scan and h.core.scan.paused, "scan did not pause")
	h.combat = false
	h:fire("PLAYER_REGEN_ENABLED"); h:drain()
	check(h.core.scan == nil, "scan did not resume")
end

-- CRITERIA_UPDATE bursts coalesce into one rescan.
do
	local h = fixture()
	h:fire("PLAYER_ENTERING_WORLD"); h:drain()
	for _ = 1, 6 do h:fire("CRITERIA_UPDATE") end
	eq(#h.timers, 1, "burst not coalesced")
	h.db.profile.characters["Realm-Alpha"].capturedAt = 0
	h.now = 9000
	h:drain()
	eq(h.db.profile.characters["Realm-Alpha"].capturedAt, 9000, "rescan did not refresh the snapshot")
end

-- Slash routing: diag goes to Diag, status/refresh/unknown stay in Core.
do
	local h = fixture()
	h.core:OnSlash("diag status")
	eq(#h.diagCalls, 1); eq(h.diagCalls[1], "diag status")
	h.core:OnSlash("bogus")
	check(h:text():find("/lnav status", 1, true) and #h.diagCalls == 1, "unknown command routed wrong")
	check(h.core.commands.lnav == "OnSlash" and h.core.commands.legacynav == "OnSlash", "slash commands not registered")
end

-- Settings can be switched off; goals are validated before they are stored.
do
	local h = fixture()
	local core = h.core
	core.db.profile.settings = { activities = { solo = true, dungeon = true, raid = false, pvp = false }, allowCharacterSwitch = true }
	local s = core.db.profile.settings
	core:OnSlash("set dungeon off"); eq(s.activities.dungeon, false, "set off did not disable")
	core:OnSlash("set switch off"); eq(s.allowCharacterSwitch, false)
	core:OnSlash("set raid on"); eq(s.activities.raid, true)
	core:OnSlash("set switch maybe"); eq(s.allowCharacterSwitch, false, "bad value changed a setting")
	s.activities.dungeon = true
	core.catalogue = { achievements = { [1] = { activity = "dungeon" }, [2] = { activity = "unrated" }, [3] = { activity = "pvp" } } }
	core.trees = { [1187] = { nodes = { [10] = { maxRanks = 2 } } } }
	local function goal(text) core.db.profile.goal = nil; core:OnSlash("goal " .. text); return core.db.profile.goal end
	check(goal("points 17") == nil, "17 points stored"); check(goal("points 0") == nil); check(goal("points 1.5") == nil)
	eq(goal("points 16").need, 16); eq(goal("points 1").need, 1)
	check(goal("challenge 99") == nil, "unknown challenge stored"); check(goal("challenge 2") == nil, "unrated stored")
	check(goal("challenge 3") == nil, "disabled activity stored"); eq(goal("challenge 1").id, 1)
	check(goal("node 11") == nil, "unknown node stored"); check(goal("node 10 3") == nil, "bad ranks stored")
	check(goal("node 10 0") == nil); eq(goal("node 10 2").ranks, 2); eq(goal("node 10").nodeID, 10)
end

-- Etappe 3: events, Replan, pin, UI hand-off, scan-incomplete log.
do
	local h = fixture({ currencyNil = true })
	for _, event in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "ZONE_CHANGED_NEW_AREA" }) do
		check(h.events[event], event .. " not registered")
	end
	local renders, inits = {}, 0
	h.ns.UI = { Init = function() inits = inits + 1 end, Render = function(p) renders[#renders + 1] = p end }
	h.core.OpenLegacyWindow = function() renders.shown = true end
	h.core:OnEnable(); eq(inits, 1, "UI.Init not called from OnEnable")
	h:fire("PLAYER_ENTERING_WORLD"); h:drain()
	check(#renders >= 1, "FinishScan did not render")
	-- 20-entry ring buffer with reasons
	for _ = 1, 25 do h.core:LogIncomplete({ points = { "currency" } }, { readAt = 1, build = "1", key = "k" }) end
	eq(#h.db.global.scanLog, 20, "log not capped"); check(h.db.global.scanLog[20].reason:find("points=currency", 1, true))
	h.core:OnSlash("status")
	check(h:text():find("Incomplete scans logged: 20", 1, true), "status misses the log")
	-- planner error keeps the last good result
	h.core.lastResult = { status = "ok", cards = {}, alternatives = {}, ["local"] = {}, goal = {} }
	local good = h.core.lastResult
	h.core.forcePlanError = true; h.core:Replan()
	eq(h.core.lastResult, good, "planner error dropped lastResult"); check(h.core.planError, "planError not set")
	eq(renders[#renders].planError, h.core.planError, "UI not told about the planner error")
	h.core.forcePlanError = false; h.core:Replan(); eq(h.core.planError, nil)
	-- pin/unpin through Core replans
	local before = #renders
	h.core:TogglePin({ achievementID = 61994, charKey = "Realm-Alpha", action = "pin" })
	eq(h.db.profile.pinned.achievementID, 61994); check(#renders > before, "pin did not replan")
	h.core:Unpin(); eq(h.db.profile.pinned, nil)
	-- zone change: location + replan, no scan
	before = #renders
	h:fire("ZONE_CHANGED_NEW_AREA")
	check(#renders > before and h.core.scan == nil, "zone change: no replan or started a scan")
	check(not renders.shown, "intro opened while data is still loading")
	-- bare /lnav toggles the Legacy window (D25)
	local toggled = 0
	h.ns.Provider.toggleLegacyWindow = function() toggled = toggled + 1; return true end
	h.core:OnSlash(""); eq(toggled, 1)
	-- first start opens the Legacy window once, after the first successful plan
	local g = fixture()
	local shown = 0
	g.core.OpenLegacyWindow = function() shown = shown + 1 end
	g.ns.UI = { Render = function() end }
	g:fire("PLAYER_ENTERING_WORLD"); g:drain()
	eq(g.db.profile.seenIntro, true, "seenIntro not set"); eq(shown, 1, "intro window not shown once")
	g.core:Replan(); eq(shown, 1, "intro window opened again")
end

print("model_spec: all assertions passed")
