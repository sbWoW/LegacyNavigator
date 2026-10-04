local _, ns = ...

-- The only file that calls WoW data APIs (achievements, traits, skills, maps). Read-only.
-- Every call is guarded: a missing function or a thrown error yields nil (never 0) and is noted once.
local def = ns.Definitions
local Provider = {}
ns.Provider = Provider

local errors = {}
local function note(name, message)
	if errors[name] == nil then errors[name] = string.sub(tostring(message), 1, 200) end
end
function Provider.takeErrors()
	local taken = errors
	errors = {}
	return taken
end

local function guard(name, fn, ...)
	if type(fn) ~= "function" then note(name, "missing"); return end
	local function pass(ok, ...)
		if not ok then note(name, (...)); return end
		return ...
	end
	return pass(pcall(fn, ...))
end

local function path(root, key)
	if type(root) == "table" then return root[key] end
end

function Provider.build() return select(2, guard("GetBuildInfo", GetBuildInfo)) end
function Provider.serverTime() return guard("GetServerTime", GetServerTime) end
function Provider.inCombat() return guard("InCombatLockdown", InCombatLockdown) == true end

function Provider.uptime() return guard("GetTime", GetTime) end

-- Ready when the achievement list answers and the Legacy trait config exists. Events only accelerate this.
function Provider.isReady()
	local categories = guard("GetCategoryList", GetCategoryList)
	if type(categories) ~= "table" then return false end
	-- Parent categories (Classes, PvP, ...) hold 0 achievements; probe the first category that has any.
	local probe
	for _, categoryID in ipairs(categories) do
		local total = guard("GetCategoryNumAchievements", GetCategoryNumAchievements, categoryID)
		if type(total) == "number" and total > 0 then probe = categoryID; break end
	end
	if probe == nil or guard("GetAchievementInfo", GetAchievementInfo, probe, 1) == nil then return false end
	return guard("C_Traits.GetConfigIDByTreeID", path(C_Traits, "GetConfigIDByTreeID"), def.treeIDs[1]) ~= nil
end

function Provider.categoryList()
	local categories = guard("GetCategoryList", GetCategoryList)
	if type(categories) ~= "table" then return nil end
	return categories
end

-- One category: its info and all achievements with criteria. complete == false if any read failed.
function Provider.readCategory(categoryID)
	local name, parentID = guard("GetCategoryInfo", GetCategoryInfo, categoryID)
	local info = { name = name, parentID = parentID }
	local total = guard("GetCategoryNumAchievements", GetCategoryNumAchievements, categoryID)
	local list, complete = {}, type(total) == "number" and name ~= nil
	for index = 1, (type(total) == "number" and total or 0) do
		local id, achName, _, completed, _, _, _, _, _, _, _, _, wasEarnedByMe = guard("GetAchievementInfo", GetAchievementInfo, categoryID, index)
		if id == nil then
			complete = false
		else
			local ach = {
				id = id, name = achName, categoryID = categoryID, completed = completed, wasEarnedByMe = wasEarnedByMe,
				legacyPoints = guard("C_Traits.GetTraitCurrencyForAchievement", path(C_Traits, "GetTraitCurrencyForAchievement"), def.pointsCurrencyID, id),
				criteria = {},
			}
			local count = guard("GetAchievementNumCriteria", GetAchievementNumCriteria, id)
			if type(count) ~= "number" then
				ach.incomplete = true
			else
				for i = 1, count do
					local text, ctype, done, quantity, req, _, _, assetID, _, criteriaID = guard("GetAchievementCriteriaInfo", GetAchievementCriteriaInfo, id, i)
					if criteriaID == nil and text == nil then ach.incomplete = true end
					ach.criteria[i] = { id = criteriaID, type = ctype, text = text, done = done, quantity = quantity, req = req, assetID = assetID }
				end
			end
			list[#list + 1] = ach
		end
	end
	return info, list, complete
end

function Provider.readCharacter()
	local name = guard("UnitName", UnitName, "player")
	local realm = guard("GetRealmName", GetRealmName)
	local _, classFile = guard("UnitClass", UnitClass, "player")
	return {
		key = name and realm and (realm .. "-" .. name) or nil,
		guid = guard("UnitGUID", UnitGUID, "player"),
		classFile = classFile,
		level = guard("UnitLevel", UnitLevel, "player"),
	}
end

-- skillID -> { rank, max }. nil if unreadable or if collapsed headers hide lines (never expanded: read-only).
function Provider.readSkills()
	local skillInfo = C_SkillInfo
	local count = guard("C_SkillInfo.GetNumSkillLines", path(skillInfo, "GetNumSkillLines"))
	if type(count) ~= "number" then return nil end
	local skills = {}
	for index = 1, count do
		local line = guard("C_SkillInfo.GetSkillLineInfo", path(skillInfo, "GetSkillLineInfo"), index)
		if type(line) ~= "table" then return nil end
		if line.isHeader then
			if line.isCollapsed then return nil end
		elseif line.skillID ~= nil and line.rank ~= nil then
			skills[line.skillID] = { rank = line.rank, max = line.maxRank }
		end
	end
	return skills
end

function Provider.readRenown()
	return guard("C_MajorFactions.GetCurrentRenownLevel", path(C_MajorFactions, "GetCurrentRenownLevel"), def.rewardTrackFactionID)
end

-- Spendable points incl. staged changes. No row for the currency (the client returns {} at 0) is only an
-- assumed 0: `assumed = true`, Model.snapshot confirms it against renown 0.
function Provider.readPoints()
	local treeID = def.treeIDs[1]
	local configID = guard("C_Traits.GetConfigIDByTreeID", path(C_Traits, "GetConfigIDByTreeID"), treeID)
	if configID == nil then return nil end
	local rows = guard("C_Traits.GetTreeCurrencyInfo", path(C_Traits, "GetTreeCurrencyInfo"), configID, treeID, false)
	if type(rows) ~= "table" then return nil end
	for _, row in pairs(rows) do
		if type(row) == "table" and row.traitCurrencyID == def.pointsCurrencyID then
			if row.quantity == nil then return nil end
			return { available = row.quantity, spent = row.spent }
		end
	end
	return { available = 0, spent = 0, assumed = true }
end

function Provider.readLocation()
	local mapID = guard("C_Map.GetBestMapForUnit", path(C_Map, "GetBestMapForUnit"), "player")
	if mapID == nil then return nil end
	return { mapID = mapID }
end

-- One advantage tree for the later "minimum need, unchecked" goal: nodes with ranks and cost, conditions
-- with spentAmountRequired. nil if the config or node list is missing; individual node failures leave
-- `incomplete = true`.
function Provider.readTree(treeID)
	local traits = C_Traits
	local configID = guard("C_Traits.GetConfigIDByTreeID", path(traits, "GetConfigIDByTreeID"), treeID)
	if configID == nil then return nil end
	local ids = guard("C_Traits.GetTreeNodes", path(traits, "GetTreeNodes"), treeID)
	if type(ids) ~= "table" then return nil end
	local tree = { treeID = treeID, configID = configID, nodes = {}, conditions = {} }
	local info = guard("C_Traits.GetTreeInfo", path(traits, "GetTreeInfo"), configID, treeID)
	if type(info) == "table" then tree.rootNodeID, tree.cannotRefund = info.rootNodeID, info.cannotRefund else tree.incomplete = true end
	for _, nodeID in ipairs(ids) do
		local node = guard("C_Traits.GetNodeInfo", path(traits, "GetNodeInfo"), configID, nodeID)
		if type(node) ~= "table" or node.ID == nil then
			tree.incomplete = true
		elseif node.ID ~= 0 then
			local cost = guard("C_Traits.GetNodeCost", path(traits, "GetNodeCost"), configID, nodeID)
			if cost == nil then tree.incomplete = true end
			tree.nodes[nodeID] = {
				currentRank = node.currentRank, maxRanks = node.maxRanks, isAvailable = node.isAvailable,
				canPurchaseRank = node.canPurchaseRank, meetsEdgeRequirements = node.meetsEdgeRequirements,
				conditionIDs = node.conditionIDs, cost = cost,
			}
			for _, conditionID in ipairs(node.conditionIDs or {}) do
				if tree.conditions[conditionID] == nil then
					local condition = guard("C_Traits.GetConditionInfo", path(traits, "GetConditionInfo"), configID, conditionID)
					if type(condition) == "table" then
						tree.conditions[conditionID] = {
							type = condition.type, isMet = condition.isMet, isGate = condition.isGate,
							spentAmountRequired = condition.spentAmountRequired, traitCurrencyID = condition.traitCurrencyID,
						}
					else
						tree.incomplete = true
					end
				end
			end
		end
	end
	return tree
end
