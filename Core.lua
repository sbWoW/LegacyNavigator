local addonName, ns = ...
local L, def, Model, Provider, Planner = ns.L, ns.Definitions, ns.Model, ns.Provider, ns.Planner

local POLL_SECONDS, POLL_DEADLINE = 1, 30 -- poll every second, give up after 30 s of client time
local CRITERIA_COALESCE = 1
local TICK = 0.01 -- next frame; one scan step per tick keeps the frame time flat

local defaults = {
	global = { schema = 1 },
	profile = {
		settings = { activities = def.defaultActivities, allowCharacterSwitch = true },
		goal = nil, -- { type = "points", need = n } | { type = "challenge", id = n } | { type = "node", nodeID = n, ranks = n }
		account = nil, -- Model.snapshot().account
		characters = {}, -- ["Realm-Name"] = Model.snapshot().character
	},
}

local Core = LibStub("AceAddon-3.0"):NewAddon("LegacyNavigatorCore", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
ns.Core = Core

-- AceConsole prefixes with tostring(self) = the AceAddon name; use the addon's public name instead.
local console = LibStub("AceConsole-3.0", true)
local prefix = setmetatable({}, { __tostring = function() return "LegacyNavigator" end })
if console then function Core:Print(...) return console.Print(prefix, ...) end end

function Core:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("LegacyNavigatorDB", defaults, true) -- shared "Default" profile
	-- profileKeys are sticky per character: move old-build chars off the dev profile "16001-beta" and drop it
	if self.db:GetCurrentProfile() ~= "Default" then self.db:SetProfile("Default") end
	if self.db.profiles["16001-beta"] then self.db:DeleteProfile("16001-beta", true) end
	self.states = Model.newStates()
	self.shownErrors = {}
	-- Registered after Diag, so this replaces Diag's handler; `diag` is routed back to it.
	self:RegisterChatCommand("lnav", "OnSlash")
	self:RegisterChatCommand("legacynav", "OnSlash")
end

function Core:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("RECEIVED_ACHIEVEMENT_LIST", "CheckReady")
	self:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED", "CheckReady")
	self:RegisterEvent("CRITERIA_UPDATE")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Readiness ---------------------------------------------------------------------------------------

function Core:PLAYER_ENTERING_WORLD()
	if self.started then return end -- later loading screens change nothing in Etappe 1
	self.started = true
	Model.beginSession(self.states, self.db.profile, Provider.readCharacter().key)
	self:StartPoll()
end

function Core:StartPoll()
	if self.pollTimer then return end
	self.pollDeadline = (Provider.uptime() or 0) + POLL_DEADLINE
	self.pollTimer = self:ScheduleRepeatingTimer("CheckReady", POLL_SECONDS)
	self:CheckReady()
end

-- Poll tick and event accelerator in one: events are not required, the poll is. After the deadline only a
-- late readiness event can still start the first scan.
function Core:CheckReady()
	if not self.started then return end
	if self.pollTimer then
		if Provider.isReady() then
			self:CancelTimer(self.pollTimer)
			self.pollTimer = nil
			self:StartScan()
		elseif (Provider.uptime() or 0) >= self.pollDeadline then
			self:CancelTimer(self.pollTimer)
			self.pollTimer = nil -- states stay loading/stale; /lnav refresh retries
		end
	elseif not self.catalogue and not self.scan and Provider.isReady() then
		self:StartScan()
	end
end

-- Scan --------------------------------------------------------------------------------------------

function Core:StartScan()
	if self.scan then self.rescan = true; return end
	if Provider.inCombat() then self.pendingScan = true; return end
	local raw = { achievements = {}, categories = {}, achievementsComplete = true, trees = {}, build = Provider.build(), seen = {} }
	local steps, scan = {}, nil
	local function add(fn) steps[#steps + 1] = fn end
	add(function()
		local list = Provider.categoryList()
		if not list then raw.achievementsComplete = false; return end
		for index = 1, #list do
			local categoryID = list[index]
			if categoryID ~= nil then
				add(function()
					local info, achievements, complete = Provider.readCategory(categoryID)
					raw.categories[categoryID] = info
					if not complete then raw.achievementsComplete = false end
					for _, ach in ipairs(achievements) do
						if not raw.seen[ach.id] then
							raw.seen[ach.id] = true
							raw.achievements[#raw.achievements + 1] = ach
						end
					end
				end)
			end
		end
	end)
	add(function()
		local char = Provider.readCharacter()
		raw.key, raw.guid, raw.classFile, raw.level = char.key, char.guid, char.classFile, char.level
	end)
	add(function() raw.skills = Provider.readSkills() end)
	add(function() raw.renown = Provider.readRenown() end)
	add(function() raw.points = Provider.readPoints() end)
	add(function() raw.location = Provider.readLocation() end)
	for _, treeID in ipairs(def.treeIDs) do
		add(function() raw.trees[treeID] = Provider.readTree(treeID) end)
	end
	scan = { raw = raw, steps = steps, index = 0 }
	self.scan = scan
	self:ScheduleTimer("ScanTick", TICK)
end

function Core:ScanTick()
	local scan = self.scan
	if not scan then return end
	if Provider.inCombat() then scan.paused = true; return end -- resumed by PLAYER_REGEN_ENABLED
	scan.index = scan.index + 1
	local step = scan.steps[scan.index]
	if not step then return self:FinishScan() end
	local ok, err = pcall(step)
	if not ok then -- keeps the snapshot out of storage
		scan.raw.achievementsComplete = false
		scan.raw.stepError = scan.raw.stepError or tostring(err)
	end
	self:ScheduleTimer("ScanTick", TICK)
end

function Core:FinishScan()
	local raw = self.scan.raw
	self.scan = nil
	raw.readAt = Provider.serverTime()
	local snap = Model.snapshot(raw, raw.readAt)
	if raw.location == nil then snap.incomplete.location = { "map" } end
	local catalogue = Model.buildCatalogue(raw, def)
	if raw.achievementsComplete and not catalogue.incomplete then
		self.catalogue = catalogue
		self.trees = raw.trees -- session memory only, consumed by the later planner
	end
	local saved = Model.persist(self.db.profile, snap)
	Model.applyScan(self.states, snap.incomplete, saved)
	self.currentKey = raw.key
	self.location = raw.location -- session only
	if raw.stepError and not self.shownErrors.stepError then
		self.shownErrors.stepError = true
		self:Print("Scan step failed: " .. raw.stepError)
	end
	if not saved then
		local summary = Model.summarizeIncomplete(snap.incomplete)
		if summary ~= self.lastReported then self:Print(string.format(L["Scan incomplete, snapshot not saved: %s"], summary)) end
		self.lastReported = summary
	else
		self.lastReported = nil
	end
	for name, message in pairs(Provider.takeErrors()) do
		if not self.shownErrors[name] then
			self.shownErrors[name] = true
			self:Print(name .. ": " .. message)
		end
	end
	if self.rescan then self.rescan = false; self:StartScan() end
end

-- Events ------------------------------------------------------------------------------------------

function Core:CRITERIA_UPDATE()
	if self.scan then self.rescan = true; return end -- the running scan may have read stale criteria
	if not self.currentKey or self.criteriaTimer then return end -- nothing scanned yet / burst already queued
	-- ponytail: this rescan re-reads trees and catalogue too; reuse the previous trees if it measures slow.
	self.criteriaTimer = self:ScheduleTimer(function()
		self.criteriaTimer = nil
		self:StartScan()
	end, CRITERIA_COALESCE)
end

function Core:PLAYER_REGEN_ENABLED()
	if self.scan and self.scan.paused then
		self.scan.paused = false
		self:ScheduleTimer("ScanTick", TICK)
	elseif self.pendingScan then
		self.pendingScan = false
		self:StartScan()
	end
end

-- Slash -------------------------------------------------------------------------------------------

local function stamp(time)
	if type(time) ~= "number" then return L["never"] end
	return date("%Y-%m-%d %H:%M", time)
end

function Core:PrintStatus()
	local profile = self.db.profile
	self:Print(string.format(L["Legacy Navigator status (build %s)"], tostring(Provider.build())))
	local parts = {}
	for _, domain in ipairs(Model.DOMAINS) do parts[#parts + 1] = domain .. "=" .. L[self.states[domain]] end
	self:Print(L["Domains:"] .. " " .. table.concat(parts, ", "))
	if self.catalogue then
		local total, withPoints, byActivity = Model.counts(self.catalogue)
		self:Print(string.format(L["Catalogue: %d achievements, %d with points"], total, withPoints))
		local activities = {}
		for activity, count in pairs(byActivity) do activities[#activities + 1] = activity .. "=" .. count end
		table.sort(activities)
		self:Print(string.format(L["Activities: %s"], table.concat(activities, ", ")))
		local read = 0
		for _, tree in pairs(self.trees or {}) do if not tree.incomplete then read = read + 1 end end
		self:Print(string.format(L["Trees read: %d/%d"], read, #def.treeIDs))
	elseif not self.pollTimer and self.states.account ~= "confirmed" then
		self:Print(L["Data not ready yet. Try /lnav refresh."])
	end
	self:Print(L["Known characters:"])
	local list = Model.listCharacters(profile, self.currentKey, self.states.character == "confirmed", Provider.build())
	if #list == 0 then self:Print(L["  none"]) end
	for _, entry in ipairs(list) do
		self:Print(string.format(L["  %s: %s, %s, build %s%s"], entry.key, L[entry.state], stamp(entry.capturedAt),
			tostring(entry.build), entry.buildMismatch and L[" (other build)"] or ""))
	end
end

-- Planner ------------------------------------------------------------------------------------------

local function missingText(missing)
	return string.format(L["plan.missing." .. missing.kind], missing.n)
end

local function whyText(why)
	local parts = {}
	for _, key in ipairs(why or {}) do parts[#parts + 1] = L["plan.why." .. key] end
	return table.concat(parts, ", ")
end

local function dataText(card)
	local text = L["plan.data." .. card.dataState]
	if card.dataState == "stale" then text = text .. " " .. stamp(card.capturedAt) end
	return text
end

function Core:AchievementName(id)
	local entry = self.catalogue and self.catalogue.achievements[id]
	return entry and entry.name or string.format(L["plan.unnamed"], id)
end

function Core:BuildPlanInput()
	local profile = self.db.profile
	return {
		definitions = def, catalogue = self.catalogue, account = profile.account, characters = profile.characters,
		currentChar = self.currentKey or Provider.readCharacter().key, location = self.location, trees = self.trees,
		settings = profile.settings, goal = profile.goal, states = self.states,
	}
end

function Core:PrintPlan()
	local ok, result = pcall(Planner.plan, self:BuildPlanInput())
	if not ok then self:Print(string.format(L["Planner error: %s"], tostring(result))); return end
	local goal = self.db.profile.goal
	if not goal then self:Print(L["plan.header.none"])
	elseif goal.type == "points" then self:Print(string.format(L["plan.header.points"], goal.need or 0))
	elseif goal.type == "node" then
		if result.goal.need then self:Print(string.format(L["plan.header.node"], goal.nodeID or 0, result.goal.need))
		else self:Print(string.format(L["plan.header.nodeUnknown"], goal.nodeID or 0)) end
	elseif goal.type == "challenge" then self:Print(string.format(L["plan.header.challenge"], goal.id or 0)) end
	if result.goal.available and result.goal.remaining and result.goal.remaining > 0 then
		self:Print(string.format(L["plan.goal.remaining"], result.goal.remaining, result.goal.available))
	end
	if result.status == "loading" then
		self:Print(L["plan.status.loading"] .. " (" .. L["plan.reason." .. result.reason] .. ")")
	elseif result.status == "invalid" then
		local reason = L["plan.reason." .. result.reason]
		if result.reasonArg then reason = string.format(reason, result.reasonArg) end
		self:Print(L["plan.status.invalid"] .. " " .. reason)
	elseif result.status == "none" then
		self:Print(L["plan.status.none"] .. " " .. L["plan.reason." .. result.reason])
	else
		if result.status == "reachable" then self:Print(L["plan.status.reachable"]) end
		if result.reason then self:Print(L["plan.reason." .. result.reason]) end
		for i, card in ipairs(result.cards) do
			if card.action == "spend" then
				self:Print(string.format(L["plan.card.spend"], card.available or 0))
			elseif card.action == "chooseGoal" then
				self:Print(L["plan.card.chooseGoal"])
			else
				self:Print(string.format(L["plan.card.line"], i, self:AchievementName(card.achievementID), card.charKey,
					L["plan.contribution." .. card.contribution], missingText(card.missing), whyText(card.why), dataText(card)))
			end
		end
		for _, alt in ipairs(result.alternatives) do
			self:Print(string.format(L["plan.card.alt"], self:AchievementName(alt.achievementID), alt.charKey,
				missingText(alt.missing), dataText(alt)))
		end
	end
	for _, opp in ipairs(result["local"]) do
		self:Print(string.format(L["plan.card.local"], self:AchievementName(opp.achievementID), opp.charKey))
	end
end

-- Reject what the planner would reject anyway, so an invalid goal is never stored. Returns reason key, arg.
-- Unknown catalogue/trees are not an error here; the planner validates again.
function Core:GoalProblem(goal)
	if goal.type == "points" then
		if goal.need % 1 ~= 0 or goal.need < 1 then return "needInvalid" end
		if goal.need > def.maxPoints then return "needAbove", def.maxPoints end
	elseif goal.type == "challenge" and self.catalogue then
		local ach = self.catalogue.achievements[goal.id]
		if not ach then return "challengeUnknown" end
		if ach.activity == "unrated" then return "challengeUnrated" end
		if self.db.profile.settings.activities[ach.activity] ~= true then return "challengeDisabled" end
	elseif goal.type == "node" and self.trees then
		local node, complete = nil, true
		for _, tree in pairs(self.trees) do
			if type(tree) ~= "table" or tree.incomplete then complete = false
			elseif tree.nodes and tree.nodes[goal.nodeID] then node = tree.nodes[goal.nodeID] end
		end
		if not node then return complete and "nodeUnknown" or nil end
		local ranks, maxRanks = goal.ranks, node.maxRanks or 1
		if ranks ~= nil and (ranks % 1 ~= 0 or ranks < 1 or ranks > maxRanks) then return "nodeRanks" end
	end
end

function Core:SetGoal(kind, a, b)
	local profile, n, m = self.db.profile, tonumber(a), tonumber(b)
	local goal
	if kind == "clear" then
		profile.goal = nil
		self:Print(L["Goal cleared."])
		return
	elseif n and kind == "points" then goal = { type = "points", need = n }
	elseif n and kind == "challenge" then goal = { type = "challenge", id = n }
	elseif n and kind == "node" then goal = { type = "node", nodeID = n, ranks = m }
	end
	if goal then
		local reason, arg = self:GoalProblem(goal)
		if reason then
			reason = L["plan.reason." .. reason]
			self:Print(L["plan.status.invalid"] .. " " .. (arg and string.format(reason, arg) or reason))
		else
			profile.goal = goal
			self:Print(L["Goal set."])
		end
	else
		self:Print(L["Usage: /lnav goal points N | challenge ID | node ID [ranks] | clear"])
	end
end

local SETTINGS = { pvp = true, dungeon = true, raid = true, switch = true }
function Core:SetSetting(name, value)
	local flag
	if value == "on" then flag = true elseif value == "off" then flag = false end
	if not SETTINGS[name or ""] or flag == nil then self:Print(L["Usage: /lnav set pvp|dungeon|raid|switch on|off"]); return end
	local settings = self.db.profile.settings
	if name == "switch" then settings.allowCharacterSwitch = flag else settings.activities[name] = flag end
	self:Print(string.format(L["Setting %s: %s"], name, flag and L["on"] or L["off"]))
end

function Core:OnSlash(input)
	local command = string.lower(string.match(input or "", "^%s*(%S*)") or "")
	if command == "diag" then
		if ns.Diag and ns.Diag.HandleSlash then ns.Diag.HandleSlash(input) end
	elseif command == "status" or command == "" then
		self:PrintStatus()
	elseif command == "plan" then
		self:PrintPlan()
	elseif command == "goal" then
		local _, kind, a, b = string.lower(input):match("^%s*(%S+)%s*(%S*)%s*(%S*)%s*(%S*)")
		self:SetGoal(kind ~= "" and kind or nil, a ~= "" and a or nil, b ~= "" and b or nil)
	elseif command == "set" then
		local _, name, value = string.lower(input):match("^%s*(%S+)%s*(%S*)%s*(%S*)")
		self:SetSetting(name ~= "" and name or nil, value ~= "" and value or nil)
	elseif command == "refresh" then
		self:Print(L["Refresh started."])
		if self.pollTimer then self:CheckReady() elseif not Provider.isReady() then self:StartPoll() else self:StartScan() end
	else
		self:Print(L["Use /lnav status, /lnav refresh, /lnav plan, /lnav goal, /lnav set or /lnav diag."])
	end
end
