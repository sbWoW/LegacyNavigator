local addonName, ns = ...
local NIL = "<nil>"
local PREFIX = "|cff33ccffLegacyNavigator diag|r"
local unpackValues = unpack or table.unpack
local insert = table.insert
local TREE_IDS = { 1187, 1188, 1189 }
local LIB_NAMES = {
	"LibStub", "CallbackHandler-1.0", "AceAddon-3.0", "AceEvent-3.0",
	"AceConsole-3.0", "AceTimer-3.0", "AceDB-3.0",
}
local EVENT_NAMES = {
	"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
	"RECEIVED_ACHIEVEMENT_LIST", "CRITERIA_UPDATE", "CRITERIA_EARNED",
	"ACHIEVEMENT_EARNED", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED",
	"TRAIT_TREE_CURRENCY_INFO_UPDATED", "TRAIT_NODE_CHANGED",
	"MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "MAJOR_FACTION_UNLOCKED",
	"UPDATE_FACTION", "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP",
	"CURRENCY_DISPLAY_UPDATE", "ZONE_CHANGED_NEW_AREA",
}
local FIELD = {
	"ID", "type", "flags", "maxRanks", "totalMaxRanks", "currentRank", "activeRank",
	"ranksPurchased", "ranksIncreased", "isAvailable", "isVisible", "canPurchaseRank",
	"canRefundRank", "meetsEdgeRequirements", "isDisplayError", "entryIDs",
	"entryIDsWithCommittedRanks", "conditionIDs", "groupIDs", "subTreeID",
}
local CONDITION_FIELD = {
	"type", "isMet", "isGate", "isAlwaysMet", "isSufficient", "ranksGranted", "questID",
	"achievementID", "playerLevel", "traitCurrencyID", "spentAmountRequired",
	"traitCondAccountElementID",
}

local function encoded(value, seen)
	if value == nil then return NIL end
	if type(value) ~= "table" then
		if type(value) == "string" then return string.sub(value, 1, 4096) end
		if type(value) == "number" or type(value) == "boolean" then return value end
		return tostring(value)
	end
	seen = seen or {}
	if seen[value] then return "<cycle>" end
	seen[value] = true
	local copy = {}
	for key, item in pairs(value) do
		local keyType = type(key)
		if keyType == "string" or keyType == "number" then
			copy[key] = encoded(item, seen)
		end
	end
	seen[value] = nil
	return copy
end

local function arrayMaxIndex(values)
	local maximum = 0
	if type(values) == "table" then
		for key in pairs(values) do
			if type(key) == "number" and key > maximum and key == math.floor(key) then maximum = key end
		end
	end
	return maximum
end

local function unnil(value)
	if value == NIL then return nil end
	return value
end

local function slot(result, index)
	local value = result[index]
	if value == nil then return NIL end
	return value
end

local capabilities = {}
local callSerial = 0
local function call(name, fn, ...)
	callSerial = callSerial + 1
	local tracked = name ~= "GetTime" and name ~= "debugprofilestop"
	local cap
	if tracked then
		cap = capabilities[name]
		if not cap then cap = { status = "ok", calls = 0, errors = 0, missing = 0, nilReturns = 0, firstError = NIL }; capabilities[name] = cap end
		cap.calls = cap.calls + 1
	end
	local function setStatus(status)
		if not cap then return end
		if status == "error" then cap.errors = cap.errors + 1
		elseif status == "missing" then cap.missing = cap.missing + 1
		elseif status == "nil-return" then cap.nilReturns = cap.nilReturns + 1 end
		if cap.errors > 0 then cap.status = "error"
		elseif cap.missing > 0 then cap.status = "missing"
		elseif cap.nilReturns > 0 then cap.status = "nil-return"
		else cap.status = "ok" end
	end
	if type(fn) ~= "function" then
		setStatus("missing")
		return { status = "missing" }
	end
	local args = { n = select("#", ...), ... }
	local result
	local function capture(...)
		local n = select("#", ...)
		result = { status = "ok", n = n }
		for index = 1, n do
			local value = select(index, ...)
			if value == nil then value = NIL end
			result[index] = value
		end
	end
	local ok, err = pcall(function() capture(fn(unpackValues(args, 1, args.n))) end)
	if not ok then
		local message = tostring(err)
		setStatus("error")
		if cap and cap.firstError == NIL then cap.firstError = string.sub(message, 1, 200) end
		return { status = "error", err = message }
	end
	if not result then result = { status = "ok", n = 0 } end
	if name == "C_Timer.After" then
		setStatus("ok") -- returns nothing by design
	elseif result.n == 0 or result[1] == NIL then
		result.status = "nil-return"
		setStatus("nil-return")
	else
		setStatus("ok")
	end
	return result
end

local function get1(name, fn, ...)
	return slot(call(name, fn, ...), 1)
end

local function getPath(root, key)
	if type(root) == "table" then return root[key] end
	return nil
end

local function put(source, target, fields)
	for index = 1, #fields do
		local key = fields[index]
		local value
		if type(source) == "table" then value = source[key] end
		target[key] = encoded(value)
	end
end

local function scalarFields(source)
	local copy = {}
	if type(source) == "table" then
		for key, value in pairs(source) do
			local kind = type(value)
			if (type(key) == "string" or type(key) == "number") and
				(kind == "string" or kind == "number" or kind == "boolean") then
				copy[key] = encoded(value)
			end
		end
	end
	return copy
end

local function boolBit(value)
	if value == true then return "1" end
	if value == false then return "0" end
	return NIL
end

local function profileKey()
	local build = call("GetBuildInfo", GetBuildInfo)
	local beta = get1("IsBetaBuild", IsBetaBuild)
	local ptr = get1("IsPublicTestClient", IsPublicTestClient)
	local test = get1("IsTestBuild", IsTestBuild)
	local toc = slot(build, 4)
	local number = slot(build, 2)
	return tostring(toc) .. "|" .. tostring(number) .. "|beta=" .. boolBit(beta) ..
		"|ptr=" .. boolBit(ptr) .. "|test=" .. boolBit(test)
end

local session = { early = {}, events = {}, bootCapabilities = {}, loginTime = nil, enteringWorldSeen = false, loginSeen = false }
local loadTime = call("GetTime", GetTime)
session.loginTime = type(loadTime[1]) == "number" and loadTime[1] or nil
local function scalarArg(value)
	local kind = type(value)
	if value == nil then return NIL end
	if kind == "string" then return string.sub(value, 1, 60) end
	if kind == "number" or kind == "boolean" then return value end
	return NIL
end

local function recordEvent(event, ...)
	local record = session.events[event]
	if not record then
		record = { count = 0, first = NIL, last = NIL, args = {} }
		session.events[event] = record
	end
	local now = get1("GetTime", GetTime)
	if type(now) ~= "number" then now = nil end
	local elapsed = now and session.loginTime and (now - session.loginTime) or nil
	record.count = record.count + 1
	if record.count == 1 then record.first = encoded(elapsed) end
	record.last = encoded(elapsed)
	if record.count <= 3 then
		local args = { n = select("#", ...) }
		for index = 1, args.n do args[index] = scalarArg(select(index, ...)) end
		insert(record.args, args)
	end
end

local function earlyProbe(eventName)
	local savedCapabilities = capabilities
	capabilities = {}
	local early = { event = eventName }
	local categoryResult = call("GetCategoryList", GetCategoryList)
	local categories = unnil(categoryResult[1])
	early.categoryCount = type(categories) == "table" and #categories or NIL
	local firstCategory = type(categories) == "table" and categories[1] or nil
	if firstCategory ~= nil then
		local count = call("GetCategoryNumAchievements", GetCategoryNumAchievements, firstCategory)
		early.firstCategoryCounts = { slot(count, 1), slot(count, 2), slot(count, 3) }
		local achievement = call("GetAchievementInfo", GetAchievementInfo, firstCategory, 1)
		early.firstAchievement = { id = slot(achievement, 1), name = slot(achievement, 2) }
	else
		early.firstCategoryCounts = { NIL, NIL, NIL }
		early.firstAchievement = { id = NIL, name = NIL }
	end
	early.renownLevel = get1("C_MajorFactions.GetCurrentRenownLevel", getPath(C_MajorFactions, "GetCurrentRenownLevel"), 2802)
	early.config1188 = get1("C_Traits.GetConfigIDByTreeID", getPath(C_Traits, "GetConfigIDByTreeID"), 1188)
	local config1187 = get1("C_Traits.GetConfigIDByTreeID", getPath(C_Traits, "GetConfigIDByTreeID"), 1187)
	if config1187 ~= nil and config1187 ~= NIL then
		local currency = call("C_Traits.GetTreeCurrencyInfo", getPath(C_Traits, "GetTreeCurrencyInfo"), config1187, 1187, false)
		local rows = unnil(currency[1])
		local quantity, spent = nil, nil
		if type(rows) == "table" then
			for _, row in pairs(rows) do
				if type(row) == "table" and row.traitCurrencyID == 4225 then
					quantity, spent = row.quantity, row.spent
					break
				end
			end
		end
		early.tree1187Currency = { includingStaged = { quantity = encoded(quantity), spent = encoded(spent) } }
	else
		early.tree1187Currency = { includingStaged = { quantity = NIL, spent = NIL } }
	end
	early.limitBySourcedMaxFalse = get1("C_Traits.GetMaxAvailableTraitCurrency", getPath(C_Traits, "GetMaxAvailableTraitCurrency"), 4225, false)
	session.bootCapabilities[eventName] = encoded(capabilities)
	early.capabilities = encoded(capabilities)
	capabilities = savedCapabilities
	session.early[eventName] = early
end

local addon
local function chat(message)
	if addon and type(addon.Print) == "function" then
		local ok = pcall(addon.Print, addon, PREFIX .. " " .. tostring(message))
		if ok then return end
	end
	if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
		DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. " " .. tostring(message))
	end
end

local eventFrame = call("CreateFrame", CreateFrame, "Frame")[1]
local eventRegistration = {}
local pendingCombat = nil
local activeRun = nil
local generation = 0
local clearGeneration = 0
local regenRegistered = false
local clearPendingAt = nil
local fullRun

local function registerRegenOnce()
	if regenRegistered then return end
	local result = call("Frame.RegisterEvent", eventFrame and eventFrame.RegisterEvent, eventFrame, "PLAYER_REGEN_ENABLED")
	regenRegistered = result.status ~= "missing" and result.status ~= "error" and result[1] ~= false
end

local function deferForCombat(trigger, onDone)
	if not pendingCombat then pendingCombat = { trigger = trigger, callbacks = {} } end
	if type(onDone) == "function" then insert(pendingCombat.callbacks, onDone) end
	registerRegenOnce()
	chat("Full probe queued until combat ends.")
end

local function schedule(delay, fn)
	local timer = getPath(C_Timer, "After")
	if type(timer) == "function" then
		local result = call("C_Timer.After", timer, delay, fn)
		if result.status ~= "missing" and result.status ~= "error" then return true end
	end
	if addon and type(addon.ScheduleTimer) == "function" then
		local ok = pcall(addon.ScheduleTimer, addon, fn, math.max(delay, 0.01))
		if ok then return true end
	end
	return false
end

local function copyMap(source)
	return encoded(source)
end

local function runCapabilities()
	return copyMap(capabilities)
end

local function getDb()
	if type(LegacyNavigatorDiagDB) ~= "table" then LegacyNavigatorDiagDB = {} end
	if type(LegacyNavigatorDiagDB.profiles) ~= "table" then LegacyNavigatorDiagDB.profiles = {} end
	LegacyNavigatorDiagDB.schema = 1
	return LegacyNavigatorDiagDB
end

local function getLibs()
	local result = { present = type(LibStub) == "table" or type(LibStub) == "function" }
	for index = 1, #LIB_NAMES do
		local name = LIB_NAMES[index]
		local lib, minor
		if LibStub and type(LibStub.GetLibrary) == "function" then
			local ok, first, second = pcall(LibStub.GetLibrary, LibStub, name, true)
			if ok then lib, minor = first, second end
		elseif type(LibStub) == "function" then
			local ok, first = pcall(LibStub, name, true)
			if ok then lib = first end
		end
		result[name] = { available = lib ~= nil, minor = encoded(minor) }
	end
	return result
end

local function captureMeta(enqueue, run, trigger)
	local meta = { trigger = trigger }
	run.meta = meta
	enqueue(function()
		local build = call("GetBuildInfo", GetBuildInfo)
		meta.version, meta.buildNumber, meta.buildDate, meta.tocVersion = slot(build, 1), slot(build, 2), slot(build, 3), slot(build, 4)
	end)
	local scalarCalls = {
		{ "isBetaBuild", "IsBetaBuild", IsBetaBuild },
		{ "isTestBuild", "IsTestBuild", IsTestBuild },
		{ "isPublicTestClient", "IsPublicTestClient", IsPublicTestClient },
		{ "activeGameMode", "C_GameRules.GetActiveGameMode", getPath(C_GameRules, "GetActiveGameMode") },
		{ "hardcoreActive", "C_GameRules.IsHardcoreActive", getPath(C_GameRules, "IsHardcoreActive") },
		{ "locale", "GetLocale", GetLocale }, { "realm", "GetRealmName", GetRealmName },
		{ "playerGUID", "UnitGUID", UnitGUID, "player" }, { "level", "UnitLevel", UnitLevel, "player" },
		{ "xp", "UnitXP", UnitXP, "player" }, { "xpMax", "UnitXPMax", UnitXPMax, "player" },
		{ "serverTime", "GetServerTime", GetServerTime }, { "localTime", "time", time },
		{ "timestamp", "date", date, "!%Y-%m-%dT%H:%M:%SZ" },
	}
	for index = 1, #scalarCalls do
		local definition = scalarCalls[index]
		local key, name, fn, argument = definition[1], definition[2], definition[3], definition[4]
		enqueue(function()
			if argument ~= nil then meta[key] = get1(name, fn, argument) else meta[key] = get1(name, fn) end
		end)
	end
	enqueue(function()
		meta.playerName = get1("UnitName", UnitName, "player")
	end)
	enqueue(function()
		local class = call("UnitClass", UnitClass, "player")
		meta.className, meta.classFile, meta.classID = slot(class, 1), slot(class, 2), slot(class, 3)
	end)
	enqueue(function()
		local race = call("UnitRace", UnitRace, "player")
		meta.raceName, meta.raceFile, meta.raceID = slot(race, 1), slot(race, 2), slot(race, 3)
	end)
	enqueue(function()
		local faction = call("UnitFactionGroup", UnitFactionGroup, "player")
		meta.factionToken, meta.factionName = slot(faction, 1), slot(faction, 2)
	end)
	enqueue(function()
		meta.profileKey = tostring(meta.tocVersion) .. "|" .. tostring(meta.buildNumber) .. "|beta=" .. boolBit(meta.isBetaBuild) ..
			"|ptr=" .. boolBit(meta.isPublicTestClient) .. "|test=" .. boolBit(meta.isTestBuild)
	end)
end

local function enqueueAchievement(enqueue, challenges, categoryID, index, total)
	enqueue(function()
		local data = call("GetAchievementInfo", GetAchievementInfo, categoryID, index)
		local achievementID = unnil(data[1])
		if data.status ~= "ok" or achievementID == nil then challenges.collectionIncomplete = true end
		if achievementID ~= nil then
			if challenges._seen[achievementID] then
				if not challenges._duplicateMarked[achievementID] then
					challenges._duplicateMarked[achievementID] = true
					insert(challenges.duplicates, encoded(achievementID))
				end
			else
				local challenge = {
					cat = encoded(categoryID), index = index, homeCategory = NIL,
					name = slot(data, 2), points = slot(data, 3), description = slot(data, 8),
					rewardText = slot(data, 11), legacyPoints = NIL,
					completed = slot(data, 4), month = slot(data, 5), day = slot(data, 6), year = slot(data, 7),
					flags = slot(data, 9), wasEarnedByMe = slot(data, 13), earnedBy = slot(data, 14),
					isStatistic = slot(data, 15), numCriteria = NIL, criteria = {},
				}
				challenges.list[achievementID] = challenge
				challenges._seen[achievementID] = true
				insert(challenges.ids, achievementID)
				enqueue(function()
					challenge.isValid = get1("C_AchievementInfo.IsValidAchievement", getPath(C_AchievementInfo, "IsValidAchievement"), achievementID)
				end)
				enqueue(function()
					local result = call("GetAchievementCategory", GetAchievementCategory, achievementID)
					challenge.homeCategory = slot(result, 1)
				end)
				enqueue(function()
					local reward = call("C_Traits.GetTraitCurrencyForAchievement", getPath(C_Traits, "GetTraitCurrencyForAchievement"), 4225, achievementID)
					challenge.legacyPoints, challenge._rewardStatus = slot(reward, 1), reward.status
					if reward.status ~= "ok" then challenges.rewardIncomplete = true end
				end)
				enqueue(function()
					local count = call("GetAchievementNumCriteria", GetAchievementNumCriteria, achievementID)
					challenge.numCriteria = slot(count, 1)
					local totalCriteria = unnil(count[1])
					if count.status ~= "ok" or type(totalCriteria) ~= "number" then
						challenges.criteriaIncomplete = true
					else
						for criterionIndex = 1, totalCriteria do
							local ci = criterionIndex
							enqueue(function()
								local criterion = call("GetAchievementCriteriaInfo", GetAchievementCriteriaInfo, achievementID, ci)
								if criterion.status ~= "ok" then challenges.criteriaIncomplete = true end
								challenge.criteria[ci] = {
									i = ci, id = slot(criterion, 10), type = slot(criterion, 2), text = slot(criterion, 1),
									completed = slot(criterion, 3), quantity = slot(criterion, 4), req = slot(criterion, 5),
									charName = slot(criterion, 6), flags = slot(criterion, 7), assetID = slot(criterion, 8),
									eligible = slot(criterion, 11),
								}
							end)
						end
					end
				end)
			end
		end
		if index < total then enqueueAchievement(enqueue, challenges, categoryID, index + 1, total) end
	end)
end

local function enqueueCategories(enqueue, challenges)
	enqueue(function()
		local result = call("GetCategoryList", GetCategoryList)
		local categories = unnil(result[1])
		if result.status ~= "ok" or type(categories) ~= "table" then
			challenges.categoryList = NIL
			challenges.collectionIncomplete = true
			return
		end
		challenges.categoryList = encoded(categories)
		for index = 1, arrayMaxIndex(categories) do
			local categoryID = categories[index]
			if categoryID ~= nil then
				insert(challenges.order, encoded(categoryID))
				local category = { name = NIL, parentID = NIL, flags = NIL, num = NIL, numCompleted = NIL, numIncomplete = NIL }
				challenges.categories[categoryID] = category
				enqueue(function()
					local info = call("GetCategoryInfo", GetCategoryInfo, categoryID)
					category.name, category.parentID, category.flags = slot(info, 1), slot(info, 2), slot(info, 3)
				end)
				-- Omitting includeAll mirrors Blizzard's Legacy achievement panel.
				enqueue(function()
					local counts = call("GetCategoryNumAchievements", GetCategoryNumAchievements, categoryID)
					category.num, category.numCompleted, category.numIncomplete = slot(counts, 1), slot(counts, 2), slot(counts, 3)
					local total = unnil(counts[1])
					if counts.status ~= "ok" or type(total) ~= "number" then
						challenges.collectionIncomplete = true
					elseif total > 0 then
						enqueueAchievement(enqueue, challenges, categoryID, 1, total)
					end
				end)
			end
		end
	end)
end

local function buildChallenges(enqueue, run)
	local challenges = { categories = {}, order = {}, list = {}, ids = {}, duplicates = {}, _seen = {}, _duplicateMarked = {} }
	run.challenges = challenges
	enqueueCategories(enqueue, challenges)
end

local CURRENCY_FIELDS = { "traitCurrencyID", "quantity", "maxQuantity", "spent", "spentInTree" }
local function currencyRows(value)
	value = unnil(value)
	if type(value) ~= "table" then return NIL end
	local rows = {}
	for index = 1, arrayMaxIndex(value) do
		local source = value[index]
		if type(source) == "table" then
			local row = {}
			put(source, row, CURRENCY_FIELDS)
			rows[index] = row
		elseif source ~= nil then
			rows[index] = encoded(source)
		end
	end
	return rows
end

local function runPoints(enqueue, run)
	local points = {
		constants = { rewardTrackFaction = 2802, traitCurrency = 4225, trees = { 1187, 1188, 1189 } },
		renownLevel = NIL, majorFactionData = NIL, treeCurrency = {}, maxAvailable4225 = {}, traitCurrencyInfo = NIL,
		configs = {}, configStatus = {}, statuses = {},
	}
	run.points = points
	local legacyConsts = Constants and Constants.LegacyConsts
	points.constants.legacyConsts = scalarFields(legacyConsts)
	for index = 1, #TREE_IDS do
		local treeID = TREE_IDS[index]
		points.treeCurrency[treeID] = { configID = NIL, includingStaged = NIL, committedOnly = NIL }
		points.configs[treeID] = NIL
	end
	enqueue(function()
		local result = call("C_MajorFactions.GetCurrentRenownLevel", getPath(C_MajorFactions, "GetCurrentRenownLevel"), 2802)
		points.renownLevel, points.renownStatus = slot(result, 1), result.status
	end)
	enqueue(function()
		local result = call("C_MajorFactions.GetMajorFactionData", getPath(C_MajorFactions, "GetMajorFactionData"), 2802)
		local data = unnil(result[1])
		if type(data) == "table" then points.majorFactionData = scalarFields(data) else points.majorFactionData = NIL end
	end)
	enqueue(function()
		local result = call("C_Traits.GetTraitCurrencyInfo", getPath(C_Traits, "GetTraitCurrencyInfo"), 4225)
		points.traitCurrencyInfo = {
			flags = slot(result, 1), type = slot(result, 2),
			currencyTypesID = slot(result, 3), icon = slot(result, 4),
		}
	end)
	for _, limitBySourcedMax in ipairs({ false, true }) do
		local limit = limitBySourcedMax
		enqueue(function()
			local result = call("C_Traits.GetMaxAvailableTraitCurrency", getPath(C_Traits, "GetMaxAvailableTraitCurrency"), 4225, limit)
			local key = limit and "limitBySourcedMaxTrue" or "limitBySourcedMaxFalse"
			points.maxAvailable4225[key] = slot(result, 1)
			points.statuses[key] = result.status
		end)
	end
	for index = 1, #TREE_IDS do
		local treeID = TREE_IDS[index]
		local currency = points.treeCurrency[treeID]
		enqueue(function()
			local result = call("C_Traits.GetConfigIDByTreeID", getPath(C_Traits, "GetConfigIDByTreeID"), treeID)
			local configID = unnil(result[1])
			currency.configID = slot(result, 1)
			points.configs[treeID] = slot(result, 1)
			points.configStatus[treeID] = result.status
			if configID ~= nil then
				enqueue(function()
					local data = call("C_Traits.GetTreeCurrencyInfo", getPath(C_Traits, "GetTreeCurrencyInfo"), configID, treeID, false)
					currency.includingStaged = currencyRows(data[1])
					currency.includingStagedStatus = data.status
				end)
				enqueue(function()
					local data = call("C_Traits.GetTreeCurrencyInfo", getPath(C_Traits, "GetTreeCurrencyInfo"), configID, treeID, true)
					currency.committedOnly = currencyRows(data[1])
					currency.committedOnlyStatus = data.status
				end)
			end
		end)
	end
end

local function runRewardTrack(enqueue, run)
	local track = { factionID = 2802, levels = NIL, status = NIL }
	run.rewardTrack = track
	enqueue(function()
		local result = call("C_MajorFactions.GetRenownLevels", getPath(C_MajorFactions, "GetRenownLevels"), 2802)
		local levels = unnil(result[1])
		track.status = result.status
		if type(levels) ~= "table" then track.levels = NIL; return end
		track.levels = {}
		for index = 1, arrayMaxIndex(levels) do
			local source = levels[index]
			if type(source) == "table" then
				local level = scalarFields(source)
				level.level = encoded(source.level)
				level.rewards = NIL
				track.levels[index] = level
				local levelID = unnil(source.level)
				if type(levelID) == "number" then
					enqueue(function()
						local rewardResult = call("C_MajorFactions.GetRenownRewardsForLevel", getPath(C_MajorFactions, "GetRenownRewardsForLevel"), 2802, levelID)
						local rewards = unnil(rewardResult[1])
						if type(rewards) ~= "table" then level.rewards = NIL; track.rewardsIncomplete = true; return end
						level.rewards = {}
						for rewardIndex = 1, arrayMaxIndex(rewards) do
							local reward = rewards[rewardIndex]
							if type(reward) == "table" then
								level.rewards[rewardIndex] = scalarFields(reward)
								level.rewards[rewardIndex].icon = nil
							else
								level.rewards[rewardIndex] = encoded(reward)
							end
						end
						if rewardResult.status ~= "ok" then track.rewardsIncomplete = true end
					end)
				else
					level.rewards = NIL
					track.rewardsIncomplete = true
				end
			end
		end
	end)
end

local function addConditionID(run, value, configID)
	local id = unnil(value)
	if type(id) == "number" or type(id) == "string" then
		if run._conditionIDs[id] == nil then run._conditionIDs[id] = configID end
	end
end

local function addConditionArray(run, value, configID)
	value = unnil(value)
	if type(value) == "table" then
		for _, id in pairs(value) do
			if type(id) == "table" then
				addConditionID(run, id.conditionID or id.id or id[2], configID)
			else
				addConditionID(run, id, configID)
			end
		end
	end
end

local function runTrees(enqueue, run)
	run.trees = {}
	run._conditionIDs = {}
	for treeIndex = 1, #TREE_IDS do
		local currentTreeID = TREE_IDS[treeIndex]
		local configID = unnil(run.points.configs[currentTreeID])
		local invalidNodes = configID ~= nil and 0 or NIL
		local tree = { configID = encoded(configID), staged = NIL, info = NIL, nodes = {}, entries = {}, invalidNodes = invalidNodes, validNodeCount = 0 }
		run.trees[currentTreeID] = tree
		if configID ~= nil then
			enqueue(function()
				local result = call("C_Traits.ConfigHasStagedChanges", getPath(C_Traits, "ConfigHasStagedChanges"), configID)
				tree.staged = slot(result, 1)
			end)
			enqueue(function()
				local result = call("C_Traits.GetTreeInfo", getPath(C_Traits, "GetTreeInfo"), configID, currentTreeID)
				local source = unnil(result[1])
				if type(source) ~= "table" then tree.info = NIL; return end
				local info = {}
				put(source, info, { "ID", "rootNodeID", "cannotRefund" })
				info.gates = encoded(source.gates)
				if type(source.gates) == "table" then
					addConditionID(run, source.gates.conditionID or source.gates[2], configID)
					for _, gate in pairs(source.gates) do
						if type(gate) == "table" then addConditionID(run, gate.conditionID or gate[2], configID) end
					end
				end
				tree.info = info
			end)
			enqueue(function()
				local result = call("C_Traits.GetTreeNodes", getPath(C_Traits, "GetTreeNodes"), currentTreeID)
				local ids = unnil(result[1])
				tree.nodeIDs = encoded(ids)
				tree.nodeListStatus = result.status
				if type(ids) ~= "table" then return end
				local nodeCount = arrayMaxIndex(ids)
				for chunkStart = 1, nodeCount, 25 do
					local first, last = chunkStart, math.min(chunkStart + 24, nodeCount)
					enqueue(function()
					for nodeIndex = first, last do
					local currentNodeID = ids[nodeIndex]
					if currentNodeID ~= nil then
					enqueue(function()
					local nodeResult = call("C_Traits.GetNodeInfo", getPath(C_Traits, "GetNodeInfo"), configID, currentNodeID)
						local source = unnil(nodeResult[1])
						if type(source) ~= "table" or nodeResult.status ~= "ok" then
							tree.nodeInfoIncomplete = true
							tree.invalidNodes = tree.invalidNodes + 1
							return
						end
						if source.ID == nil or source.ID == 0 then
							if source.ID == nil then tree.nodeInfoIncomplete = true end
							tree.invalidNodes = tree.invalidNodes + 1
							return
						end
						local node = {}
						put(source, node, FIELD)
						node.visibleEdges = NIL
						if type(source.visibleEdges) == "table" then
							node.visibleEdges = {}
							for edgeIndex, edge in pairs(source.visibleEdges) do
								if type(edge) == "table" then
									node.visibleEdges[edgeIndex] = {
										targetNode = encoded(edge.targetNode), type = encoded(edge.type), isActive = encoded(edge.isActive),
									}
								end
							end
						end
						tree.nodes[currentNodeID] = node
						tree.validNodeCount = tree.validNodeCount + 1
						addConditionArray(run, source.conditionIDs, configID)
						local costNodeID = currentNodeID
						enqueue(function()
							local costResult = call("C_Traits.GetNodeCost", getPath(C_Traits, "GetNodeCost"), configID, costNodeID)
							node.cost = encoded(unnil(costResult[1]))
						end)
						local entryIDs = unnil(source.entryIDs)
						if type(entryIDs) ~= "table" then return end
						for entryIndex = 1, arrayMaxIndex(entryIDs) do
							local currentEntryID = entryIDs[entryIndex]
							if currentEntryID ~= nil and tree.entries[currentEntryID] == nil then
								tree.entries[currentEntryID] = { definition = NIL }
								enqueue(function()
									local entryResult = call("C_Traits.GetEntryInfo", getPath(C_Traits, "GetEntryInfo"), configID, currentEntryID)
									local entrySource = unnil(entryResult[1])
									if type(entrySource) ~= "table" then tree.entries[currentEntryID] = NIL; return end
									local entry = {}
									put(entrySource, entry, { "definitionID", "subTreeID", "type", "maxRanks", "isAvailable", "isDisplayError", "conditionIDs" })
									tree.entries[currentEntryID] = entry
									addConditionArray(run, entrySource.conditionIDs, configID)
									local definitionID = entrySource.definitionID
									if definitionID == nil then return end
									entry.definitionID = encoded(definitionID)
									entry.definition = NIL
									enqueue(function()
										local definitionResult = call("C_Traits.GetDefinitionInfo", getPath(C_Traits, "GetDefinitionInfo"), definitionID)
										local definitionSource = unnil(definitionResult[1])
										if type(definitionSource) ~= "table" then entry.definition = NIL; return end
										local definition = {}
										put(definitionSource, definition, { "spellID", "overrideName", "overrideSubtext", "overriddenSpellID", "subType" })
										entry.definition = definition
										local overrideName = definitionSource.overrideName
										local spellID = definitionSource.spellID
										if type(overrideName) == "string" and overrideName ~= "" then
											definition.name = overrideName
										elseif spellID ~= nil and type(getPath(C_Spell, "GetSpellName")) == "function" then
											definition.name = NIL
											local spellName = getPath(C_Spell, "GetSpellName")
											enqueue(function() definition.name = get1("C_Spell.GetSpellName", spellName, spellID) end)
										else
											definition.name = NIL
										end
									end)
								end)
							end
						end
					end)
					end
				end
					end)
				end
			end)
		end
	end
end

local function runConditions(enqueue, run)
	run.conditions = {}
	for condID, configID in pairs(run._conditionIDs or {}) do
		local id, currentConfigID = condID, configID
		enqueue(function()
			local result = call("C_Traits.GetConditionInfo", getPath(C_Traits, "GetConditionInfo"), currentConfigID, id)
			local source = unnil(result[1])
			local condition = { condID = encoded(id), info = type(source) == "table" }
			if type(source) ~= "table" then condition.info = NIL end
			put(source, condition, CONDITION_FIELD)
			run.conditions[id] = condition
		end)
	end
end

local SKILL_FIELDS = { "skillID", "name", "isHeader", "isCollapsed", "rank", "maxRank", "modifier", "skillLineCategoryID", "parentSkillLineID" }
local function runSkills(enqueue, run)
	local skills = { count = NIL, collapsedHeaders = NIL, lines = {}, status = NIL }
	run.skills = skills
	enqueue(function()
		local result = call("C_SkillInfo.GetNumSkillLines", getPath(C_SkillInfo, "GetNumSkillLines"))
		local count = unnil(result[1])
		skills.count, skills.status = slot(result, 1), result.status
		if type(count) == "number" then
			skills.collapsedHeaders = 0
			for index = 1, count do
				local lineIndex = index
				enqueue(function()
					local lineResult = call("C_SkillInfo.GetSkillLineInfo", getPath(C_SkillInfo, "GetSkillLineInfo"), lineIndex)
					local source = unnil(lineResult[1])
					local line = { index = lineIndex, info = type(source) == "table" }
					if type(source) ~= "table" then line.info = NIL end
					put(source, line, SKILL_FIELDS)
					if type(source) == "table" and source.isHeader and source.isCollapsed then skills.collapsedHeaders = skills.collapsedHeaders + 1 end
					skills.lines[lineIndex] = line
				end)
			end
		end
	end)
end

local function runLocation(enqueue, run)
	local location = { mapID = NIL, map = NIL, position = NIL, canSetWaypoint = NIL }
	run.location = location
	enqueue(function()
		local result = call("C_Map.GetBestMapForUnit", getPath(C_Map, "GetBestMapForUnit"), "player")
		local mapID = unnil(result[1])
		location.mapID = slot(result, 1)
		if mapID ~= nil then
			enqueue(function()
				local mapResult = call("C_Map.GetMapInfo", getPath(C_Map, "GetMapInfo"), mapID)
				local source = unnil(mapResult[1])
				if type(source) ~= "table" then location.map = NIL; return end
				local map = {}
				put(source, map, { "mapID", "name", "mapType", "parentMapID" })
				location.map = map
			end)
			enqueue(function()
				local posResult = call("C_Map.GetPlayerMapPosition", getPath(C_Map, "GetPlayerMapPosition"), mapID, "player")
				local pos = unnil(posResult[1])
				if type(pos) == "table" or type(pos) == "userdata" then
					local ok, getXY = pcall(function() return pos.GetXY end)
					if ok and type(getXY) == "function" then
						enqueue(function()
							local xy = call("C_Map.GetPlayerMapPosition.GetXY", getXY, pos)
							location.position = { x = slot(xy, 1), y = slot(xy, 2) }
						end)
					else
						location.position = NIL
					end
				else location.position = NIL end
			end)
			enqueue(function()
				location.canSetWaypoint = get1("C_Map.CanSetUserWaypointOnMap", getPath(C_Map, "CanSetUserWaypointOnMap"), mapID)
			end)
		end
	end)
end

local function runProvider(enqueue, run)
	local provider = { loaded = NIL, version = NIL, functions = {} }
	run.provider = provider
	enqueue(function()
		provider.loaded = get1("C_AddOns.IsAddOnLoaded", getPath(C_AddOns, "IsAddOnLoaded"), "LegacyForever")
		local legacy = LegacyForever
		local api = type(legacy) == "table" and legacy.API or nil
		if type(api) == "table" then
			provider.version = encoded(api.version)
			for _, name in ipairs({ "ZoneSummary", "Targets", "Navigate", "Subscribe" }) do
				provider.functions[name] = type(api[name]) == "function"
			end
		end
	end)
end

local function countValues(map)
	local n = 0
	for _ in pairs(map or {}) do n = n + 1 end
	return n
end

local function findCurrency(rows)
	rows = unnil(rows)
	if type(rows) == "table" then
		for _, row in pairs(rows) do
			if type(row) == "table" and row.traitCurrencyID == 4225 then return row end
		end
	end
	return nil
end

local function markIncomplete(summary, names, name)
	names[name] = true
end

local function aggregateChallenges(run, summary, first, last)
	local challenges = run.challenges
	for index = first, last do
		local id = challenges.ids[index]
		local challenge = challenges.list[id]
		local points, completed = unnil(challenge.legacyPoints), unnil(challenge.completed)
		local earned = unnil(challenge.wasEarnedByMe)
		if challenge._rewardStatus ~= "ok" or type(points) ~= "number" then
			summary._rewardIncomplete = true
		elseif points > 0 then
			summary.rewardBearing = summary.rewardBearing + 1
			if completed == true then
				summary.rewardBearingCompleted = summary.rewardBearingCompleted + 1
				summary.legacyPointsCompleted = summary.legacyPointsCompleted + points
			end
		end
		if completed == true then
			if earned == false then summary.completedNotEarnedByMe = summary.completedNotEarnedByMe + 1
			elseif earned == nil then summary.completedEarnedByUnknown = summary.completedEarnedByUnknown + 1 end
		elseif completed == nil then
			summary._completionIncomplete = true
		end
		summary.criteriaTotal = summary.criteriaTotal + countValues(challenge.criteria)
	end
end

local function finishSummary(run, summary)
	local challenges = run.challenges
	local incomplete = {}
	if challenges.categoryList == NIL then
		summary.categories = NIL
		markIncomplete(summary, incomplete, "categories")
	end
	if challenges.collectionIncomplete then
		for _, key in ipairs({ "challengesTotal", "rewardBearing", "rewardBearingCompleted", "completedNotEarnedByMe", "completedEarnedByUnknown", "criteriaTotal", "legacyPointsCompleted" }) do
			summary[key] = NIL
			markIncomplete(summary, incomplete, key)
		end
	else
		if summary._rewardIncomplete then
			for _, key in ipairs({ "rewardBearing", "rewardBearingCompleted", "legacyPointsCompleted" }) do
				summary[key] = NIL
				markIncomplete(summary, incomplete, key)
			end
		end
		if summary._completionIncomplete then
			for _, key in ipairs({ "rewardBearingCompleted", "completedNotEarnedByMe", "completedEarnedByUnknown", "legacyPointsCompleted" }) do
				summary[key] = NIL
				markIncomplete(summary, incomplete, key)
			end
		end
		if challenges.criteriaIncomplete then
			summary.criteriaTotal = NIL
			markIncomplete(summary, incomplete, "criteriaTotal")
		end
	end
	summary._rewardIncomplete, summary._completionIncomplete = nil, nil
	summary.renownLevel = NIL
	if run.points and run.points.renownLevel ~= nil then summary.renownLevel = run.points.renownLevel end
	if not run.points or run.points.renownStatus ~= "ok" then markIncomplete(summary, incomplete, "renownLevel") end
	summary.treeCurrency, summary.nodeCounts = {}, {}
	for _, treeID in ipairs(TREE_IDS) do
		local currency = run.points and run.points.treeCurrency and run.points.treeCurrency[treeID]
		local including = findCurrency(currency and currency.includingStaged)
		local committed = findCurrency(currency and currency.committedOnly)
		local quantity, spent, maxQuantity = NIL, NIL, NIL
		local committedQuantity, committedSpent = NIL, NIL
		if including and currency.includingStagedStatus == "ok" and
			including.quantity ~= NIL and including.spent ~= NIL and including.maxQuantity ~= NIL then
			quantity, spent, maxQuantity = encoded(including.quantity), encoded(including.spent), encoded(including.maxQuantity)
		else
			markIncomplete(summary, incomplete, "treeCurrency" .. treeID .. ".includingStaged")
		end
		if committed and currency.committedOnlyStatus == "ok" and committed.quantity ~= NIL and committed.spent ~= NIL then
			committedQuantity, committedSpent = encoded(committed.quantity), encoded(committed.spent)
		else
			markIncomplete(summary, incomplete, "treeCurrency" .. treeID .. ".committedOnly")
		end
		summary.treeCurrency[treeID] = {
			includingStagedQuantity = quantity, includingStagedSpent = spent, includingStagedMaxQuantity = maxQuantity,
			committedOnlyQuantity = committedQuantity, committedOnlySpent = committedSpent,
		}
		local tree = run.trees and run.trees[treeID]
		if tree and tree.nodeListStatus == "ok" and not tree.nodeInfoIncomplete and type(unnil(tree.nodeIDs)) == "table" then
			summary.nodeCounts[treeID] = tree.validNodeCount
		else
			summary.nodeCounts[treeID] = NIL
			markIncomplete(summary, incomplete, "nodeCount" .. treeID)
		end
	end
	summary.maxAvailable4225 = copyMap(run.points and run.points.maxAvailable4225 or {})
	for _, key in ipairs({ "limitBySourcedMaxFalse", "limitBySourcedMaxTrue" }) do
		if not run.points or run.points.statuses[key] ~= "ok" then
			summary.maxAvailable4225[key] = NIL
			markIncomplete(summary, incomplete, "maxAvailable4225." .. key)
		end
	end
	summary.skillLines = run.skills and run.skills.count or NIL
	if not run.skills or run.skills.status ~= "ok" then
		summary.skillLines = NIL
		markIncomplete(summary, incomplete, "skillLines")
	end
	local levels = run.rewardTrack and unnil(run.rewardTrack.levels)
	if type(levels) == "table" and run.rewardTrack.status == "ok" then
		summary.rewardTrackLevels = countValues(levels)
	else
		summary.rewardTrackLevels = NIL
		markIncomplete(summary, incomplete, "rewardTrackLevels")
	end
	summary.apiErrors, summary.apiMissing = 0, 0
	for _, capability in pairs(capabilities) do
		if (capability.errors or 0) > 0 then summary.apiErrors = summary.apiErrors + 1 end
		if (capability.missing or 0) > 0 then summary.apiMissing = summary.apiMissing + 1 end
	end
	summary.incomplete = {}
	for name in pairs(incomplete) do insert(summary.incomplete, name) end
	table.sort(summary.incomplete)
end

local function prepareSummary(enqueue, run)
	local summary = {
		categories = #run.challenges.order, challengesTotal = #run.challenges.ids,
		rewardBearing = 0, rewardBearingCompleted = 0, completedNotEarnedByMe = 0,
		completedEarnedByUnknown = 0, criteriaTotal = 0, legacyPointsCompleted = 0,
	}
	run.summary = summary
	for first = 1, #run.challenges.ids, 50 do
		local startAt, endAt = first, math.min(first + 49, #run.challenges.ids)
		enqueue(function() aggregateChallenges(run, summary, startAt, endAt) end)
	end
	enqueue(function() finishSummary(run, summary) end)
end

local function preparePrevious(enqueue, run)
	local db = type(LegacyNavigatorDiagDB) == "table" and LegacyNavigatorDiagDB or nil
	local profile = db and db.profiles and db.profiles[run.meta.profileKey]
	local character = profile and profile.characters and profile.characters[tostring(run.meta.realm) .. "-" .. tostring(run.meta.playerName)]
	if type(character) ~= "table" or type(character.run) ~= "table" then return end
	local previous = { summary = copyMap(character.run.summary), challenges = {} }
	run._previous = previous
	local oldChallenges = character.run.challenges or {}
	local ids = oldChallenges.ids
	if type(ids) ~= "table" then
		ids = {}
		for id in pairs(oldChallenges.list or {}) do insert(ids, id) end
	end
	for first = 1, #ids, 50 do
		local startAt, endAt = first, math.min(first + 49, #ids)
		enqueue(function()
			for index = startAt, endAt do
				local id = ids[index]
				local challenge = oldChallenges.list[id]
				previous.challenges[id] = {
					completed = encoded(unnil(challenge.completed)),
					wasEarnedByMe = encoded(unnil(challenge.wasEarnedByMe)),
				}
			end
		end)
	end
end

local function printSummary(summary)
	local currencyParts, nodeParts = {}, {}
	for _, treeID in ipairs(TREE_IDS) do
		local row = summary.treeCurrency[treeID]
		insert(currencyParts, tostring(treeID) .. " " .. tostring(row.includingStagedQuantity) .. "/" ..
			tostring(row.includingStagedSpent) .. "/" .. tostring(row.includingStagedMaxQuantity))
		insert(nodeParts, tostring(treeID) .. ":" .. tostring(summary.nodeCounts[treeID]))
	end
	chat("Categories " .. tostring(summary.categories) .. " | challenges " .. tostring(summary.challengesTotal) ..
		" | rewards " .. tostring(summary.rewardBearing) .. " (" .. tostring(summary.rewardBearingCompleted) .. " complete)")
	chat("Completed not earned by me " .. tostring(summary.completedNotEarnedByMe) .. " | unknown " ..
		tostring(summary.completedEarnedByUnknown) .. " | criteria " .. tostring(summary.criteriaTotal) ..
		" | completed legacy points " .. tostring(summary.legacyPointsCompleted))
	chat("Renown " .. tostring(summary.renownLevel) .. " | currency including staged qty/spent/max " .. table.concat(currencyParts, ", "))
	chat("max 4225 (unlimited/sourced) " .. tostring(summary.maxAvailable4225.limitBySourcedMaxFalse) .. "/" ..
		tostring(summary.maxAvailable4225.limitBySourcedMaxTrue) .. " | nodes " .. table.concat(nodeParts, ", ") ..
		" | skills " .. tostring(summary.skillLines) .. " | reward track levels " .. tostring(summary.rewardTrackLevels))
	chat("API errors/missing " .. tostring(summary.apiErrors) .. "/" .. tostring(summary.apiMissing) ..
		" | duration " .. tostring(summary.durationMs) .. " ms | busy " .. tostring(summary.busyMs) .. " ms")
end

local function profileNow()
	if type(debugprofilestop) ~= "function" then return nil end
	local result = call("debugprofilestop", debugprofilestop)
	return type(result[1]) == "number" and result[1] or nil
end

local function addBusy(state, before, callCount)
	if before ~= nil then
		local after = profileNow()
		if after ~= nil then state.busyMs = state.busyMs + math.max(0, after - before) end
	else
		state.fallbackCalls = state.fallbackCalls + callCount
	end
end

local function appendJobError(run, err)
	if #run.jobErrors >= 20 then return end
	insert(run.jobErrors, string.sub(tostring(err), 1, 200))
end

local function finalize(state)
	local run = state.run
	if activeRun ~= state or state.generation ~= generation then return end
	local before = profileNow()
	local previous = run._previous
	local now = get1("GetTime", GetTime)
	run.meta.durationMs = type(now) == "number" and type(state.startedWall) == "number" and (now - state.startedWall) * 1000 or NIL
	run.meta.busyMs = state.busyAvailable and state.busyMs or NIL
	run.combatPauses = state.run.combatPauses
	run.challenges._seen, run.challenges._duplicateMarked = nil, nil
	run._conditionIDs = nil
	run._previous = nil
	run.early = copyMap(session.early)
	run.bootCapabilities = copyMap(session.bootCapabilities)
	run.events = copyMap(session.events)
	run.session = {
		isReload = encoded(session.isReload), loginTime = encoded(session.loginTime),
		enteringWorldArgs = copyMap(session.enteringWorldArgs),
	}
	run.libs = getLibs()
	run.capabilities = runCapabilities()
	run.summary.durationMs = run.meta.durationMs
	run.summary.busyMs = run.meta.busyMs
	run.summary.apiErrors, run.summary.apiMissing = 0, 0
	for _, capability in pairs(capabilities) do
		if (capability.errors or 0) > 0 then run.summary.apiErrors = run.summary.apiErrors + 1 end
		if (capability.missing or 0) > 0 then run.summary.apiMissing = run.summary.apiMissing + 1 end
	end
	local key = run.meta.profileKey
	local db = getDb()
	local profile = db.profiles[key]
	if type(profile) ~= "table" then profile = { characters = {} }; db.profiles[key] = profile end
	if type(profile.characters) ~= "table" then profile.characters = {} end
	local character = tostring(run.meta.realm) .. "-" .. tostring(run.meta.playerName)
	local record = { run = run }
	if previous then record.previous = previous end
	profile.characters[character] = record
	local finishedWall = get1("GetTime", GetTime)
	if type(finishedWall) == "number" and type(state.startedWall) == "number" then
		run.meta.durationMs = (finishedWall - state.startedWall) * 1000
		run.summary.durationMs = run.meta.durationMs
	end
	addBusy(state, before, 0)
	run.meta.busyMs = state.busyAvailable and state.busyMs or NIL
	run.summary.busyMs = run.meta.busyMs
	activeRun = nil
	printSummary(run.summary)
	local callbackClearGeneration = clearGeneration
	for _, callback in ipairs(state.callbacks) do
		if callbackClearGeneration ~= clearGeneration then break end
		if type(callback) == "function" then pcall(callback, run) end
	end
end

local function fullProbe(trigger, onDone)
	if activeRun then chat("probe already running"); return false end
	if get1("InCombatLockdown", InCombatLockdown) == true then
		deferForCombat(trigger, onDone)
		return false
	end
	generation = generation + 1
	capabilities = {}
	local run = {
		meta = {}, jobErrors = {}, combatPauses = 0, bootCapabilities = copyMap(session.bootCapabilities),
	}
	local state = {
		run = run, generation = generation, callbacks = {}, stages = {}, stageIndex = 1,
		jobs = {}, head = 1, stageDone = false, busyMs = 0, fallbackCalls = 0,
		busyAvailable = type(debugprofilestop) == "function", suspended = false,
	}
	run.capabilities = capabilities
	if type(onDone) == "function" then insert(state.callbacks, onDone) end
	activeRun = state
	state.stages = {
		function(enqueue, done) captureMeta(enqueue, run, trigger); done() end,
		function(enqueue, done) buildChallenges(enqueue, run); done() end,
		function(enqueue, done) runPoints(enqueue, run); done() end,
		function(enqueue, done) runRewardTrack(enqueue, run); done() end,
		function(enqueue, done) runTrees(enqueue, run); done() end,
		function(enqueue, done) runConditions(enqueue, run); done() end,
		function(enqueue, done) runSkills(enqueue, run); done() end,
		function(enqueue, done) runLocation(enqueue, run); done() end,
		function(enqueue, done) runProvider(enqueue, run); done() end,
		function(enqueue, done) prepareSummary(enqueue, run); done() end,
		function(enqueue, done) preparePrevious(enqueue, run); done() end,
	}
	local processTick
	local function isCurrent()
		return activeRun == state and generation == state.generation
	end
	local function loadStage(index)
		state.stageIndex, state.jobs, state.head, state.stageDone = index, {}, 1, false
		local function enqueue(job) state.jobs[#state.jobs + 1] = job end
		local ok, err = pcall(state.stages[index], enqueue, function() state.stageDone = true end)
		if not ok then appendJobError(run, err); state.stageDone = true end
	end
	local function queueNext()
		if isCurrent() and not schedule(0, function() processTick() end) then processTick() end
	end
	processTick = function()
		if not isCurrent() then return end
		local tickStart, tickCalls = profileNow(), callSerial
		if tickStart == nil then state.busyAvailable = false end
		if get1("InCombatLockdown", InCombatLockdown) == true then
			if not state.suspended then
				state.suspended = true
				run.combatPauses = run.combatPauses + 1
				registerRegenOnce()
			end
			addBusy(state, tickStart, callSerial - tickCalls)
			return
		end
		state.suspended = false
		local used, finished = 0, false
		while isCurrent() do
			if state.head <= #state.jobs then
				local tickNow = tickStart and profileNow() or nil
				local elapsed = tickStart and tickNow and (tickNow - tickStart) or nil
				if used >= 24 or (elapsed and elapsed >= 4) then break end
				local job = state.jobs[state.head]
				state.head = state.head + 1
				local before = callSerial
				local ok, err = pcall(job)
				used = used + callSerial - before
				if not ok then appendJobError(run, err) end
			elseif state.stageDone then
				if state.stageIndex < #state.stages then
					loadStage(state.stageIndex + 1)
				else
					finished = true
					break
				end
			else
				break
			end
		end
		addBusy(state, tickStart, callSerial - tickCalls)
		if not isCurrent() then return end
		if finished then finalize(state) else queueNext() end
	end
	state.processTick = processTick
	state.startedWall = get1("GetTime", GetTime)
	loadStage(1)
	processTick()
	return true
end

fullRun = fullProbe

local function lastRun()
	if type(LegacyNavigatorDiagDB) ~= "table" or type(LegacyNavigatorDiagDB.profiles) ~= "table" then return nil end
	local latest, latestTime
	for _, profile in pairs(LegacyNavigatorDiagDB.profiles) do
		for _, character in pairs(profile.characters or {}) do
			if type(character) == "table" and type(character.run) == "table" then
				local timestamp = character.run.meta and character.run.meta.timestamp
				if type(timestamp) == "string" and (latestTime == nil or timestamp > latestTime) then
					latest, latestTime = character.run, timestamp
				end
			end
		end
	end
	return latest
end

local function clearDatabase()
	generation = generation + 1
	clearGeneration = clearGeneration + 1
	activeRun, pendingCombat = nil, nil
	if regenRegistered then
		call("Frame.UnregisterEvent", eventFrame and eventFrame.UnregisterEvent, eventFrame, "PLAYER_REGEN_ENABLED")
		regenRegistered = false
	end
	LegacyNavigatorDiagDB = { schema = 1, profiles = {} }
end

local function nowSeconds()
	local current = get1("GetTime", GetTime)
	if type(current) == "number" then return current end
	local epoch = get1("time", time)
	if type(epoch) == "number" then return epoch end
	return nil
end

local function handleSlash(input)
	local command, rest = string.match(input or "", "^%s*(%S*)%s*(.-)%s*$")
	command = string.lower(command or "")
	if command == "diag" then
		local action = string.lower(rest or "")
		if action == "status" then
			local run = lastRun()
			if run and run.summary then printSummary(run.summary) else chat("No diagnostic run is stored.") end
		elseif action == "clear" then
			local now = nowSeconds()
			if clearPendingAt and now and now - clearPendingAt <= 10 then
				clearDatabase()
				clearPendingAt = nil
				chat("Diagnostic data cleared.")
			else
				clearPendingAt = now
				chat("Run /lnav diag clear again within 10 seconds to erase diagnostic data.")
			end
		else
			fullRun("manual")
		end
	else
		chat("Use /lnav diag, /lnav diag status, or /lnav diag clear.")
	end
end

local aceAddon
if LibStub then
	local ok, library = pcall(function()
		if type(LibStub) == "table" and type(LibStub.GetLibrary) == "function" then return LibStub:GetLibrary("AceAddon-3.0", true) end
		if type(LibStub) == "function" then return LibStub("AceAddon-3.0", true) end
	end)
	if ok then aceAddon = library end
end
if aceAddon and type(aceAddon.NewAddon) == "function" then
	local ok, value = pcall(aceAddon.NewAddon, aceAddon, addonName, "AceConsole-3.0", "AceTimer-3.0")
	if ok and type(value) == "table" then addon = value end
end
if not addon then addon = {
	Print = function(_, message)
		if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then DEFAULT_CHAT_FRAME:AddMessage(message) end
	end,
	RegisterChatCommand = function(_, command, callback)
		local token = string.upper(command)
		if type(SlashCmdList) ~= "table" then SlashCmdList = {} end
		SlashCmdList[token] = callback
		_G["SLASH_" .. token .. "1"] = "/" .. command
	end,
} end
if type(addon.RegisterChatCommand) == "function" then
	pcall(addon.RegisterChatCommand, addon, "lnav", handleSlash)
	pcall(addon.RegisterChatCommand, addon, "legacynav", handleSlash)
end

for index = 1, #EVENT_NAMES do
	local event = EVENT_NAMES[index]
	local result = call("Frame.RegisterEvent", eventFrame and eventFrame.RegisterEvent, eventFrame, event)
	local ok = result.status ~= "missing" and result.status ~= "error" and result[1] ~= false
	eventRegistration[event] = ok and "ok" or "register-error"
	local record = session.events[event] or { count = 0, first = NIL, last = NIL, args = {} }
	if not ok then record.status = "register-error" end
	session.events[event] = record
end
session.bootCapabilities.load = copyMap(capabilities)

call("Frame.SetScript", eventFrame and eventFrame.SetScript, eventFrame, "OnEvent", function(_, event, ...)
	if event == "PLAYER_REGEN_ENABLED" then
		if regenRegistered then
			call("Frame.UnregisterEvent", eventFrame and eventFrame.UnregisterEvent, eventFrame, "PLAYER_REGEN_ENABLED")
			regenRegistered = false
		end
		local pending = pendingCombat
		pendingCombat = nil
		if pending then
			fullRun(pending.trigger, function(run)
				for _, callback in ipairs(pending.callbacks) do if type(callback) == "function" then pcall(callback, run) end end
			end)
		elseif activeRun and activeRun.suspended then
			local state = activeRun
			state.suspended = false
			if not schedule(0, function() if activeRun == state then state.processTick() end end) then state.processTick() end
		end
		return
	end
	if event == "ADDON_LOADED" and select(1, ...) ~= addonName then return end
	if event == "PLAYER_LOGIN" then
		if not session.loginTimeRefined then
			local loginTime = get1("GetTime", GetTime)
			session.loginTime = type(loginTime) == "number" and loginTime or session.loginTime
			session.loginTimeRefined = true
		end
		session.loginSeen = true
	elseif event == "PLAYER_ENTERING_WORLD" and not session.enteringWorldSeen and not session.loginTimeRefined then
		local loginTime = get1("GetTime", GetTime)
		session.loginTime = type(loginTime) == "number" and loginTime or session.loginTime
		session.loginTimeRefined = true
	end
	recordEvent(event, ...)
	if event == "PLAYER_LOGIN" then
		earlyProbe("PLAYER_LOGIN")
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not session.enteringWorldSeen then
			session.enteringWorldSeen = true
			session.isReload = not session.loginSeen
			session.enteringWorldArgs = { isInitialLogin = scalarArg(select(1, ...)), isReloadingUi = scalarArg(select(2, ...)) }
			earlyProbe("PLAYER_ENTERING_WORLD")
		end
	end
end)

ns.Diag = {
	HandleSlash = handleSlash,
	RunFull = function(trigger, onDone) return fullRun(trigger or "manual", onDone) end,
	ProfileKey = profileKey,
	call = call,
	Session = session,
	Events = eventRegistration,
}
