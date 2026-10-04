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
		local id, achName, _, completed, _, _, _, _, _, _, _, _, wasEarnedByMe, earnedBy = guard("GetAchievementInfo", GetAchievementInfo, categoryID, index)
		if id == nil then
			complete = false
		else
			local ach = {
				id = id, name = achName, categoryID = categoryID, completed = completed, wasEarnedByMe = wasEarnedByMe, earnedBy = earnedBy,
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

-- Read-only: the achievement icon texture (panel rows). nil when unreadable.
function Provider.achievementIcon(id)
	return (select(10, guard("GetAchievementInfo", GetAchievementInfo, id)))
end

-- Perk name (D26): node -> entry -> definition -> spell name. Every step guarded; fallback "Vorteil <id>".
function Provider.nodeName(configID, nodeID)
	local traits, spells = C_Traits, C_Spell
	local name
	if configID ~= nil and nodeID ~= nil then
		local node = guard("C_Traits.GetNodeInfo", path(traits, "GetNodeInfo"), configID, nodeID)
		local entryID = type(node) == "table" and ((node.entryIDsWithCommittedRanks or {})[1] or (node.entryIDs or {})[1])
		local entry = entryID and guard("C_Traits.GetEntryInfo", path(traits, "GetEntryInfo"), configID, entryID)
		local definitionID = type(entry) == "table" and entry.definitionID
		local definition = definitionID and guard("C_Traits.GetDefinitionInfo", path(traits, "GetDefinitionInfo"), definitionID)
		local spellID = type(definition) == "table" and definition.spellID
		if spellID then name = guard("C_Spell.GetSpellName", path(spells, "GetSpellName"), spellID) end
	end
	if type(name) == "string" and name ~= "" then return name end
	return string.format(ns.L["hooks.node"], nodeID or 0)
end

-- Legacy window (D22). The only place that touches the Blizzard window globals. Opening is a plain window
-- toggle outside combat; nothing is spent here (spending happens on the user's clicks inside Blizzard's frame).
-- Gate = renown of faction 2802 > 0, same as Blizzard's ToggleLegacySystemUI.
function Provider.legacyUnlocked()
	local renown = Provider.readRenown()
	return type(renown) == "number" and renown > 0
end

-- Returns ok, reason, detail: true | false,"combat"|"error",message. Locked or not, the window opens (D24).
function Provider.openLegacyWindow()
	if Provider.inCombat() then return false, "combat" end
	local ok, err = pcall(function()
		if LegacySystemFrame and LegacySystemFrame:IsShown() then return end
		if Provider.legacyUnlocked() then return ToggleLegacySystemUI() end
		if type(LegacySystemFrame_LoadUI) == "function" then LegacySystemFrame_LoadUI()
		else
			local loaded, reason = C_AddOns.LoadAddOn("Blizzard_LegacySystem")
			if not loaded then error(tostring(reason)) end
		end
		if not LegacySystemFrame then error("LegacySystemFrame missing") end
		ShowUIPanel(LegacySystemFrame)
	end)
	if not ok then return false, "error", string.sub(tostring(err), 1, 200) end
	return true
end

-- D25: one entry for /lnav, minimap, key and tracker click. Open window -> close it (HideUIPanel under pcall).
function Provider.toggleLegacyWindow()
	if Provider.inCombat() then return false, "combat" end
	if LegacySystemFrame and LegacySystemFrame:IsShown() then
		local ok, err = pcall(HideUIPanel, LegacySystemFrame)
		if not ok then return false, "error", string.sub(tostring(err), 1, 200) end
		return true
	end
	return Provider.openLegacyWindow()
end

-- Jump to one achievement in the Legacy window: open it, show the challenges page, select its category and the
-- achievement. Public API only (EventRegistry triggers that Blizzard's own pages listen to); no method is replaced.
-- The window may need a frame after loading, so the selection runs on C_Timer.After(0), retried once.
-- onFail() is called at most once when the page opened but the selection did not work. Returns openLegacyWindow's result.
local CHALLENGES_PAGE = 2 -- Blizzard_LegacySystem.lua: CHALLENGES_PAGE_IDX

local function selectChallenge(achievementID, categoryID)
	if EventRegistry and EventRegistry.TriggerEvent then
		EventRegistry:TriggerEvent("Legacy.SelectPage", CHALLENGES_PAGE)
	elseif LegacySystemFrame and LegacySystemFrame.SelectPage then
		LegacySystemFrame:SelectPage(CHALLENGES_PAGE)
	else
		error("no page selector")
	end
	categoryID = categoryID or guard("GetAchievementCategory", GetAchievementCategory, achievementID)
	if categoryID == nil then error("no category") end
	EventRegistry:TriggerEvent("Legacy.OpenToChallengeCategory", categoryID)
	EventRegistry:TriggerEvent("Legacy.SelectChallenge", achievementID)
	-- The detail pane lists only what passes its search/filter; verify the challenge is in it (skipped if the layout differs).
	local page = LegacySystemFrame and LegacySystemFrame.ChallengesPage
	local box = page and page.DetailPane and page.DetailPane.ScrollBox
	local data = box and box.GetDataProvider and box:GetDataProvider()
	if data and data.FindElementDataByPredicate
		and not data:FindElementDataByPredicate(function(e) return type(e) == "table" and e.id == achievementID end) then
		error("challenge not listed")
	end
end

function Provider.showChallenge(achievementID, categoryID, onFail)
	local ok, reason, detail = Provider.openLegacyWindow()
	if not ok then return ok, reason, detail end
	local function attempt(n)
		if Provider.inCombat() then return end -- the window opened before combat; the selection is dropped silently
		if pcall(selectChallenge, achievementID, categoryID) then return end
		if n < 2 and C_Timer and C_Timer.After then return C_Timer.After(0, function() attempt(n + 1) end) end
		if onFail then pcall(onFail) end
	end
	if C_Timer and C_Timer.After then C_Timer.After(0, function() attempt(1) end) else attempt(2) end
	return true
end
