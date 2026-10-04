local unpackValues = unpack or table.unpack
local function check(value, message)
	if not value then error(message or "assertion failed", 2) end
end
local function contains(values, expected)
	for _, value in ipairs(values or {}) do if value == expected then return true end end
	return false
end
local function achievement(id, name, points, completed, earned, description, rewardText)
	local row = {
		[1] = id, [2] = name or ("Challenge " .. id), [3] = points or 0, [4] = completed,
		[5] = 1, [6] = 2, [7] = 2026, [8] = description or "Description", [9] = 0, [10] = 0,
		[11] = rewardText or "Reward text", [12] = false, [13] = earned, [14] = nil, [15] = false, n = 15,
	}
	return row
end
local function fixture(options)
	options = options or {}
	local h = {
		frames = {}, timers = {}, delayed = {}, messages = {}, calls = {}, regCalls = {},
		time = 100, profile = 0, combat = false, categoryItems = { [10] = { 101, 102 } },
		achievements = {
			[101] = achievement(101, "Reward challenge", 10, true, false, "Level 10 description", "Reward for level 10"),
			[102] = achievement(102, "Helper challenge", 0, true, nil),
		},
		rewards = { [101] = 5, [102] = 0 }, criteriaCounts = { [101] = 1, [102] = 1 },
		configIDs = {}, nodeIDs = {}, nodeInfo = {}, entries = {}, definitions = {}, conditions = {},
		currencyResults = {}, treeInfo = {}, homeCategory = {}, renownRewards = {},
		renownLevels = { { level = 1, name = "First", reputationRequired = 100 }, { level = 2, name = "Second" } },
		writeCalls = 0, categoryCountArgs = {}, currencyQueries = {},
	}
	h.achievements[102][8], h.achievements[102][11] = nil, nil

	local function count(name)
		h.calls[name] = (h.calls[name] or 0) + 1
	end
	local function frame()
		local value = { registered = {} }
		function value:RegisterEvent(event)
			self.registered[event] = true
			h.regCalls[event] = (h.regCalls[event] or 0) + 1
		end
		function value:UnregisterEvent(event) self.registered[event] = nil end
		function value:SetScript(script, callback) self[script] = callback end
		table.insert(h.frames, value)
		return value
	end
	CreateFrame = function() return frame() end
	C_Timer = {
		After = function(delay, callback)
			local queue = delay == 0 and h.timers or h.delayed
			table.insert(queue, callback)
		end,
	}
	DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) table.insert(h.messages, message) end }
	SlashCmdList = {}
	local libraries = {}
	local aceAddon = {}
	function aceAddon:NewAddon(name)
		if options.newAddonError then error("mixin failure") end
		local value = { name = name, commands = {} }
		function value:RegisterChatCommand(command, callback) self.commands[command] = callback end
		function value:Print(message) table.insert(h.messages, message) end
		function value:ScheduleTimer(callback, delay) C_Timer.After(delay, callback) end
		h.addon = value
		return value
	end
	libraries["AceAddon-3.0"] = aceAddon
	for _, name in ipairs({ "CallbackHandler-1.0", "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0", "AceDB-3.0" }) do
		libraries[name] = {}
	end
	LibStub = {
		GetLibrary = function(_, name) return libraries[name], 1403 end,
	}
	GetBuildInfo = function() return "12.1", "70205", "Oct 03 2026", 16001 end
	IsBetaBuild = function() return false end
	IsTestBuild = function() return false end
	IsPublicTestClient = function() return false end
	GetLocale = function() return "enUS" end
	GetRealmName = function() return "Realm" end
	UnitName = function() return "Tester" end
	UnitGUID = function() return "Player-1" end
	UnitClass = function() return "Warrior", "WARRIOR", 1 end
	UnitRace = function() return "Human", "Human", 1 end
	UnitFactionGroup = function() return "AllianceToken", "Alliance localized" end
	UnitLevel = function() return 70 end
	UnitXP = function() return 12 end
	UnitXPMax = function() return 100 end
	GetServerTime = function() return 1791060000 end
	GetTime = function() h.time = h.time + 0.1; return h.time end
	InCombatLockdown = function() return h.combat end
	debugprofilestop = function() h.profile = h.profile + 0.25; return h.profile end
	time = function() return 1791060000 end
	date = function() return "2026-10-03T12:00:00Z" end
	Constants = { LegacyConsts = { rewardTrackFactionID = 2802, traitCurrencyID = 4225 } }

	GetCategoryList = function() count("GetCategoryList"); return h.categoryList or { 10 } end
	GetCategoryInfo = function(categoryID) count("GetCategoryInfo"); return "Category " .. categoryID, -1, 0 end
	GetCategoryNumAchievements = function(categoryID, includeAll)
		count("GetCategoryNumAchievements")
		table.insert(h.categoryCountArgs, includeAll == nil and "<nil>" or includeAll)
		local items = h.categoryItems[categoryID] or {}
		return #items, 0, #items
	end
	GetAchievementInfo = function(first, index)
		count("GetAchievementInfo")
		if type(index) ~= "number" then return nil end
		local items = h.categoryItems[first] or {}
		local id = items[index]
		local row = id and h.achievements[id]
		if not row then return nil end
		return unpackValues(row, 1, row.n or 15)
	end
	GetAchievementCategory = function(id) count("GetAchievementCategory"); return h.homeCategory[id] or 10 end
	GetAchievementNumCriteria = function(id) count("GetAchievementNumCriteria"); return h.criteriaCounts[id] or 0 end
	GetAchievementCriteriaInfo = function(id, index)
		count("GetAchievementCriteriaInfo")
		return "Step " .. index, 0, true, 1, 1, "Tester", 0, 0, 501, 502, true
	end
	C_AchievementInfo = { IsValidAchievement = function() count("IsValidAchievement"); return true end }
	C_GameRules = { GetActiveGameMode = function() return nil end, IsHardcoreActive = function() return false end }
	C_MajorFactions = {
		GetCurrentRenownLevel = function() return 6 end,
		GetMajorFactionData = function() return { renownLevel = 6, progress = 3 } end,
		GetRenownLevels = function() return h.renownLevels end,
		GetRenownRewardsForLevel = function(_, level)
			count("GetRenownRewardsForLevel")
			return h.renownRewards[level] or { { itemID = 1000 + level, spellID = 2000 + level, rewardType = "item" } }
		end,
	}
	local traits = {
		GetTraitCurrencyForAchievement = function(_, id)
			count("GetTraitCurrencyForAchievement")
			if h.rewardError and h.rewardError[id] then error("reward query failed") end
			if h.rewardNil and h.rewardNil[id] then return nil end
			return h.rewards[id] or 0
		end,
		GetTraitCurrencyInfo = function() return 0, false, 4225, 123 end,
		GetMaxAvailableTraitCurrency = function(_, limitBySourcedMax)
			h.maxArgs = h.maxArgs or {}
			table.insert(h.maxArgs, limitBySourcedMax)
			return limitBySourcedMax and 22 or 11
		end,
		GetConfigIDByTreeID = function(treeID) return h.configIDs[treeID] end,
		GetTreeCurrencyInfo = function(_, treeID, excludeStagedChanges)
			table.insert(h.currencyQueries, { treeID, excludeStagedChanges })
			local result = h.currencyResults[treeID]
			return result and result[excludeStagedChanges] or {}
		end,
		ConfigHasStagedChanges = function() return true end,
		GetTreeInfo = function(_, treeID) return h.treeInfo[treeID] or { ID = treeID, rootNodeID = 1, cannotRefund = false } end,
		GetTreeNodes = function(treeID) return h.nodeIDs[treeID] or {} end,
		GetNodeInfo = function(_, nodeID) return h.nodeInfo[nodeID] or { ID = nodeID, entryIDs = {}, conditionIDs = {} } end,
		GetNodeCost = function() return { { ID = 4225, amount = 1 } } end,
		GetEntryInfo = function(_, entryID) return h.entries[entryID] end,
		GetDefinitionInfo = function(definitionID) return h.definitions[definitionID] end,
		GetConditionInfo = function(_, conditionID)
			count("condition:" .. conditionID)
			return h.conditions[conditionID] or { type = "unknown", isMet = true, isGate = false }
		end,
		PurchaseRank = function() h.writeCalls = h.writeCalls + 1; error("write API called") end,
		RefundRank = function() h.writeCalls = h.writeCalls + 1; error("write API called") end,
		CommitConfig = function() h.writeCalls = h.writeCalls + 1; error("write API called") end,
		ResetTree = function() h.writeCalls = h.writeCalls + 1; error("write API called") end,
		SetSelection = function() h.writeCalls = h.writeCalls + 1; error("write API called") end,
		StageChanges = function() h.writeCalls = h.writeCalls + 1; error("write API called") end,
	}
	h.traits = traits
	C_Traits = traits
	C_Spell = { GetSpellName = function(id) count("GetSpellName"); return "Spell " .. id end }
	C_SkillInfo = {
		GetNumSkillLines = function() return 1 end,
		GetSkillLineInfo = function() return { skillID = 100, name = "Mining", isHeader = true, isCollapsed = true, rank = 20, maxRank = 75 } end,
		ExpandSkillHeader = function() h.writeCalls = h.writeCalls + 1; error("write API called") end,
		CollapseSkillHeader = function() h.writeCalls = h.writeCalls + 1; error("write API called") end,
		SetSelectedSkillLine = function() h.writeCalls = h.writeCalls + 1; error("write API called") end,
	}
	C_Map = {
		GetBestMapForUnit = function() return 42 end,
		GetMapInfo = function(id) return { mapID = id, name = "Test map", mapType = 3, parentMapID = 1 } end,
		GetPlayerMapPosition = function() return h.position == nil and {
			GetXY = function() return 0.25, 0.75 end,
		} or h.position end,
		CanSetUserWaypointOnMap = function() return true end,
	}
	C_AddOns = { IsAddOnLoaded = function() return false end }
	LegacyForever = nil
	LegacyNavigatorDiagDB = nil

	h.ns = {}
	assert(loadfile("Diag.lua"))("LegacyNavigator", h.ns)
	h.diag = h.ns.Diag
	function h:drain()
		local head, steps = 1, 0
		while head <= #self.timers do
			steps = steps + 1
			check(steps < 50000, "timer loop did not drain")
			local callback = self.timers[head]
			head = head + 1
			callback()
		end
		self.timers = {}
	end
	function h:fire(event, ...)
		for _, value in ipairs(self.frames) do
			if value.registered[event] and value.OnEvent then value:OnEvent(event, ...) end
		end
	end
	function h:record(run)
		local profile = LegacyNavigatorDiagDB.profiles[run.meta.profileKey]
		return profile.characters[run.meta.realm .. "-" .. run.meta.playerName]
	end
	return h
end

-- Guarded calls preserve nil, false, and zero distinctly.
do
	local h = fixture()
	local packed = h.diag.call("spec.nil", function() return nil, false, 0 end)
	check(packed.status == "nil-return" and packed.n == 3, "nil-return arity was lost")
	check(packed[1] == "<nil>" and packed[2] == false and packed[3] == 0, "nil, false, or zero was coerced")
	C_Traits = nil
	local result
	check(h.diag.RunFull("manual", function(run) result = run end), "missing API probe did not start")
	h:drain()
	check(result and result.capabilities["C_Traits.GetTraitCurrencyForAchievement"].status == "missing", "missing API was not recorded")
	check(result.capabilities["C_GameRules.GetActiveGameMode"].status == "nil-return", "nil-return capability was lost")
	check(result.meta.activeGameMode == "<nil>", "nil return was not stored as the sentinel")
	check(result.capabilities.GetTime == nil, "event timing calls were counted as API probes")
end

-- Summary inputs distinguish rewards, explicit false, and unknown ownership.
do
	local h = fixture()
	local first
	check(h.diag.RunFull("manual", function(run) first = run end), "full probe did not start")
	h:drain()
	check(first.summary.rewardBearing == 1 and first.summary.rewardBearingCompleted == 1, "helper achievement counted as a reward")
	check(first.challenges.list[101].description == "Level 10 description" and first.challenges.list[101].rewardText == "Reward for level 10", "achievement description or reward text was not captured")
	check(first.challenges.list[102].description == "<nil>" and first.challenges.list[102].rewardText == "<nil>", "nil achievement description or reward text was not preserved")
	check(first.summary.completedNotEarnedByMe == 1, "explicit false ownership was not counted")
	check(first.summary.completedEarnedByUnknown == 1, "nil ownership was not counted as unknown")
	check(first.summary.legacyPointsCompleted == 5 and first.summary.criteriaTotal == 2, "point or criteria totals were wrong")
	check(first.points.traitCurrencyInfo.type == false, "false currency type was lost")
	check(first.points.maxAvailable4225.limitBySourcedMaxFalse == 11 and first.points.maxAvailable4225.limitBySourcedMaxTrue == 22, "sourced max arguments were inverted")
	check(h.maxArgs[1] == false and h.maxArgs[2] == true, "limitBySourcedMax argument order changed")
	check(first.meta.factionToken == "AllianceToken" and first.meta.factionName == "Alliance localized", "UnitFactionGroup returns were inverted")
	check(first.meta.durationMs ~= "<nil>" and first.meta.busyMs ~= "<nil>", "timings were not recorded")
	check(#h.categoryCountArgs == 1 and h.categoryCountArgs[1] == "<nil>", "Legacy category count passed includeAll")
	check(h.writeCalls == 0, "a write API was called")
	local prior = h:record(first)
	h.achievements[101][4], h.achievements[101][13] = false, true
	local second
	h.diag.RunFull("manual", function(run) second = run end)
	h:drain()
	local previous = h:record(second).previous
	check(previous and previous.challenges[101].completed == true and previous.challenges[101].wasEarnedByMe == false, "previous per-challenge snapshot was wrong")
	check(previous.summary.rewardBearing == prior.run.summary.rewardBearing, "previous summary was not copied")
end

-- A later successful call does not hide an earlier API error.
do
	local h = fixture()
	h.rewardError = { [101] = true }
	local run
	h.diag.RunFull("manual", function(value) run = value end)
	h:drain()
	local cap = run.capabilities["C_Traits.GetTraitCurrencyForAchievement"]
	check(cap.status == "error" and cap.errors == 1, "API error history was overwritten")
	check(run.summary.rewardBearing == "<nil>" and contains(run.summary.incomplete, "rewardBearing"), "unknown reward aggregate was coerced")
	check(run.summary.apiErrors >= 1, "apiErrors did not count errored APIs")
end

-- A nil reward query leaves reward aggregates unknown.
do
	local h = fixture()
	h.rewardNil = { [101] = true }
	local run
	h.diag.RunFull("manual", function(value) run = value end)
	h:drain()
	check(run.summary.rewardBearing == "<nil>" and contains(run.summary.incomplete, "rewardBearing"), "nil reward query was coerced")
end

-- Build profile keys separate beta and PTR clients.
do
	local h = fixture()
	local a = h.diag.ProfileKey()
	IsBetaBuild = function() return true end
	local b = h.diag.ProfileKey()
	IsBetaBuild = function() return false end
	IsPublicTestClient = function() return true end
	local c = h.diag.ProfileKey()
	check(a ~= b and a ~= c, "profile key did not separate beta and PTR")
end

-- Tree traversal copies both currency modes, deduplicates conditions, and stays read-only.
do
	local h = fixture()
	h.categoryItems = { [10] = { 301 } }
	h.achievements[301] = achievement(301, "Tree test", 0, false, nil)
	h.rewards[301] = 0
	h.configIDs[1188] = 1
	h.nodeIDs[1188] = { 1, 2, 3 }
	h.treeInfo[1188] = { ID = 1188, rootNodeID = 1, cannotRefund = false, gates = { topLeftNodeID = 1, conditionID = 700 } }
	h.nodeInfo[1] = { ID = 0 }
	h.nodeInfo[2] = { ID = 2, entryIDs = { 20 }, conditionIDs = { 700 }, visibleEdges = { { targetNode = 3, type = 1, isActive = true } } }
	h.nodeInfo[3] = { ID = 3, entryIDs = { 21 }, conditionIDs = { 700, 701 } }
	h.entries[20] = { definitionID = 30, type = 1, conditionIDs = { 700 } }
	h.entries[21] = { definitionID = 31, type = 1, conditionIDs = { 701 } }
	h.definitions[30] = { spellID = 40, overrideName = "Override name", overrideSubtext = "Subtext", subType = 1 }
	h.definitions[31] = { spellID = 44, overrideName = "", overriddenSpellID = 45, subType = 1 }
	h.conditions[700] = { type = "currency", isMet = true, isGate = true, traitCurrencyID = 4225 }
	h.conditions[701] = { type = "quest", isMet = false, questID = 900 }
	h.currencyResults[1188] = {
		[false] = { { traitCurrencyID = 4225, quantity = 40, maxQuantity = 50, spent = 10, spentInTree = 8 } },
		[true] = { { traitCurrencyID = 4225, quantity = 33, maxQuantity = 50, spent = 7, spentInTree = 6 } },
	}
	local run
	h.diag.RunFull("manual", function(value) run = value end)
	h:drain()
	local tree = run.trees[1188]
	check(tree.configID == 1 and tree.invalidNodes == 1, "invalid tree node was not counted")
	check(tree.nodes[2] and tree.nodes[3], "valid nodes were not stored")
	check(tree.entries[20].definition.name == "Override name", "override name was not used")
	check(tree.entries[21].definition.name == "Spell 44", "spell name fallback was not used")
	check(run.conditions[700] and run.conditions[701], "gate/node/entry conditions were omitted")
	check(h.calls["condition:700"] == 1, "shared condition was queried more than once")
	local rows = run.points.treeCurrency[1188]
	check(rows.includingStaged[1].quantity == 40 and rows.committedOnly[1].quantity == 33, "excludeStagedChanges mapping was inverted")
	check(rows.includingStaged[1].spentInTree == 8 and rows.committedOnly[1].spentInTree == 6, "documented currency fields were not copied")
	check(run.summary.treeCurrency[1188].includingStagedQuantity == 40, "summary did not use includingStaged")
	check(run.summary.nodeCounts[1188] == 2, "tree node count was wrong")
	check(run.summary.rewardTrackLevels == 2, "reward track level count was missing")
	check(run.rewardTrack.levels[1].level == 1 and run.rewardTrack.levels[1].rewards[1].itemID == 1001, "reward track rewards were not stored")
	check(h.calls.GetSpellName == 1 and h.writeCalls == 0, "tree path called a write API or missed spell fallback")
	check(h.currencyQueries[1][2] == false and h.currencyQueries[2][2] == true, "tree currency flags were not passed as documented")
end

-- Duplicate IDs retain their first category and skip all duplicate follow-ups.
do
	local h = fixture()
	h.categoryList = { 10, 20 }
	h.categoryItems = { [10] = { 401 }, [20] = { 401 } }
	h.achievements[401] = achievement(401, "Repeated", 0, false, nil)
	h.homeCategory[401] = 99
	h.rewards[401] = 3
	local run
	h.diag.RunFull("manual", function(value) run = value end)
	h:drain()
	local row = run.challenges.list[401]
	check(#run.challenges.duplicates == 1 and run.challenges.duplicates[1] == 401, "duplicate achievement was not recorded")
	check(row.cat == 10 and row.index == 1 and row.homeCategory == 99, "enumeration category was replaced by home category")
	check(h.calls.GetTraitCurrencyForAchievement == 1 and h.calls.GetAchievementNumCriteria == 1, "duplicate follow-up calls repeated")
end

-- Map vector positions and non-table position results are both safe.
do
	local h = fixture()
	local run
	h.diag.RunFull("manual", function(value) run = value end)
	h:drain()
	check(run.location.position.x == 0.25 and run.location.position.y == 0.75, "Vector2D GetXY values were not copied")
	local other = fixture()
	other.position = 12
	local safe
	other.diag.RunFull("manual", function(value) safe = value end)
	other:drain()
	check(safe.location.position == "<nil>", "non-table map position was not handled")
end

-- Combat deferrals coalesce work and notify every queued caller.
do
	local h = fixture()
	h.combat = true
	local one, two = false, false
	check(h.diag.RunFull("manual", function() one = true end) == false, "combat request was not deferred")
	check(h.diag.RunFull("manual", function() two = true end) == false, "second combat request was not deferred")
	check(h.regCalls.PLAYER_REGEN_ENABLED == 1, "combat event was registered more than once")
	h.combat = false
	h:fire("PLAYER_REGEN_ENABLED")
	h:drain()
	check(one and two, "coalesced callbacks did not both run")
end

-- Combat entered between ticks suspends work until regeneration.
do
	local h = fixture()
	local run
	h.diag.RunFull("manual", function(value) run = value end)
	check(#h.timers > 0, "probe did not spread work over ticks")
	h.combat = true
	local nextTick = table.remove(h.timers, 1)
	nextTick()
	check(run == nil and h.regCalls.PLAYER_REGEN_ENABLED == 1, "mid-run combat did not suspend")
	h.combat = false
	h:fire("PLAYER_REGEN_ENABLED")
	h:drain()
	check(run and run.combatPauses == 1, "suspended run did not resume and record its pause")
end

-- Overlap is rejected, while confirmed clear invalidates all queued work.
do
	local h = fixture()
	local called = false
	check(h.diag.RunFull("manual", function() called = true end), "first run did not start")
	check(h.diag.RunFull("manual") == false, "overlapping run was accepted")
	local found = false
	for _, message in ipairs(h.messages) do if string.find(message, "probe already running", 1, true) then found = true end end
	check(found, "overlap message was not printed")
	h.addon.commands.lnav("diag clear")
	h.addon.commands.lnav("diag clear")
	h:drain()
	check(not called and LegacyNavigatorDiagDB.schema == 1 and next(LegacyNavigatorDiagDB.profiles) == nil, "stale run committed after clear")
end

-- A broken job is isolated, reported, and followed by successful work.
do
	local h = fixture()
	h.configIDs[1188] = 1
	h.nodeIDs[1188] = { 1, 2 }
	h.nodeInfo[1] = { ID = 1, entryIDs = { 20 }, conditionIDs = {} }
	h.nodeInfo[2] = { ID = 2, entryIDs = {}, conditionIDs = {} }
	h.entries[20] = setmetatable({}, { __index = function() error(string.rep("job exploded ", 30)) end })
	local run
	h.diag.RunFull("manual", function(value) run = value end)
	h:drain()
	check(run and #run.jobErrors == 1, "job exception was not isolated")
	check(#run.jobErrors[1] <= 200 and string.find(run.jobErrors[1], "job exploded", 1, true), "job error was not truncated")
	check(run.location.mapID == 42, "probe stopped after a job error")
end

-- Login and reload event timing snapshots survive into a later run.
do
	local h = fixture()
	h:fire("PLAYER_LOGIN")
	h:fire("PLAYER_ENTERING_WORLD", true, false)
	check(h.diag.Session.early.PLAYER_LOGIN and h.diag.Session.early.PLAYER_ENTERING_WORLD, "early probes were not captured")
	check(h.diag.Session.isReload == false, "normal login was marked as reload")
	check(#h.delayed == 0, "login scheduled an automatic probe (diag is opt-in)")
	local run
	h.diag.RunFull("manual", function(value) run = value end)
	h:drain()
	check(run.bootCapabilities.load and run.bootCapabilities.PLAYER_LOGIN and run.bootCapabilities.PLAYER_ENTERING_WORLD, "boot capability snapshots were not retained")
	check(run.events.PLAYER_ENTERING_WORLD.args[1][1] == true and run.events.PLAYER_ENTERING_WORLD.args[1][2] == false, "PEW event args were lost")
	check(run.events.PLAYER_LOGIN.first ~= "<nil>", "login event timing was not recorded")
	local reload = fixture()
	reload:fire("PLAYER_ENTERING_WORLD", false, true)
	check(reload.diag.Session.isReload == true and type(reload.diag.Session.events.PLAYER_ENTERING_WORLD.first) == "number", "reload PEW did not record timings")
	check(reload.diag.Session.enteringWorldArgs.isInitialLogin == false and reload.diag.Session.enteringWorldArgs.isReloadingUi == true, "reload PEW flags were lost")
end

-- A NewAddon mixin failure falls back to chat and C_Timer.
do
	local h = fixture({ newAddonError = true })
	local run
	check(h.diag.RunFull("manual", function(value) run = value end), "fallback addon probe did not start")
	check(SlashCmdList.LNAV and SlashCmdList.LEGACYNAV and SLASH_LNAV1 == "/lnav", "plain addon did not register slash commands")
	h:drain()
	check(run ~= nil and #h.messages > 0, "plain addon fallback did not report through chat")
end

print("diag_spec: all assertions passed")
