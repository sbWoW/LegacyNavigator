local _, ns = ...

-- Middle-click-to-set-goal inside Blizzard's Legacy window (D26, D27). Only HookScript on unprotected buttons (OnMouseUp,
-- OnEnter) and hooksecurefunc on the challenge mixin's Init. Nothing is replaced; left and right clicks keep
-- their Blizzard paths. Everything runs under pcall; a changed Blizzard layout costs the
-- feature, never the window. The pure helpers (GoalForChallenge, GoalForNode) are tested offline.
local L = ns.L
local Hooks = {}
ns.Hooks = Hooks

local ADDON = "Blizzard_LegacySystem"
local core
local installed = {}

-- Pure helpers -------------------------------------------------------------------------------------------

-- Mirrors the panel's challenge filter: rated, activity on, points > 0, not completed.
-- Returns { kind, a, b } (arguments of Core:SetGoal) or nil, reasonKey.
function Hooks.GoalForChallenge(catalogue, settings, completed, id)
	local ach = catalogue and catalogue.achievements and catalogue.achievements[id]
	if not ach then return nil, "hooks.reason.unknown" end
	if ach.activity == "unrated" then return nil, "hooks.reason.unrated" end
	if completed and completed[id] then return nil, "hooks.reason.completed" end
	if type(ach.points) ~= "number" or ach.points <= 0 then return nil, "hooks.reason.noPoints" end
	if not (settings and settings.activities and settings.activities[ach.activity] == true) then return nil, "hooks.reason.disabled" end
	return { kind = "challenge", a = id }
end

-- Our own rows (D27): a point-less zone helper cannot be a goal, so climb to the chain that contains it (depth <= 6).
-- Returns the same as GoalForChallenge for the resolved id.
function Hooks.GoalForCard(catalogue, settings, completed, id)
	local all = catalogue and catalogue.achievements or {}
	for _ = 1, 6 do
		local ach = all[id]
		if not (ach and ach.points == 0) then break end
		local parent
		for pid, candidate in pairs(all) do
			for _, c in ipairs(candidate.criteria or {}) do
				if c.type == 8 and c.assetID == id then parent = pid; break end
			end
			if parent then break end
		end
		if not parent then break end
		id = parent
	end
	return Hooks.GoalForChallenge(catalogue, settings, completed, id)
end

-- Perk node: target = next rank. Unknown node (trees not read yet) is passed through; Core validates.
function Hooks.GoalForNode(trees, nodeID)
	if type(nodeID) ~= "number" then return nil, "hooks.reason.unknown" end
	for _, tree in pairs(trees or {}) do
		local node = type(tree) == "table" and tree.nodes and tree.nodes[nodeID]
		if node then
			local rank, max = node.currentRank or 0, node.maxRanks or 1
			if rank >= max then return nil, "hooks.reason.owned" end
			return { kind = "node", a = nodeID, b = rank + 1 }
		end
	end
	return { kind = "node", a = nodeID }
end

-- Frame hooks --------------------------------------------------------------------------------------------

local function addHint(button, key)
	button:HookScript("OnEnter", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:AddLine(L[key], 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end
	end)
end

local function upClick(button, mouse, onClick)
	button:HookScript("OnMouseUp", function(self, which)
		if which == mouse and self:IsMouseOver() then
			local ok, err = pcall(onClick, self)
			if not ok and core then core:CallUI(error, err) end
		end
	end)
end

local function attachChallenge(button)
	if type(button) ~= "table" or button.lnavHooked or not button.HookScript then return end
	button.lnavHooked = true
	addHint(button, "hooks.hint.goal")
	upClick(button, "MiddleButton", function(self)
		core:SetChallengeGoal(self.id) -- read at click time: the button is pooled and re-used
	end)
end

local function attachNode(button)
	if type(button) ~= "table" or button.lnavHooked or not button.HookScript then return end
	button.lnavHooked = true
	addHint(button, "hooks.hint.goal")
	upClick(button, "MiddleButton", function(self)
		local goal, reason = Hooks.GoalForNode(core.trees, self:GetNodeID())
		if goal then core:SetGoal(goal.kind, goal.a, goal.b) else core:Print(L[reason]) end
	end)
end

-- Iterators differ (pairs gives key, value; pool enumerators give the frame): take whichever is a frame.
local function each(iter, state, init, fn)
	for a, b in iter, state, init do fn(type(b) == "table" and b or a) end
end

local function challengeScroll()
	local frame = _G.LegacySystemFrame
	if not frame then return nil end
	for _, key in ipairs({ "ChallengesPage", "ChallengePage", "ChallengesFrame" }) do
		local page = frame[key]
		if type(page) == "table" then return page.ScrollBox or page end
	end
end

local function installChallenges()
	if not installed.challengeInit and _G.LegacyChallengeTemplateMixin then
		hooksecurefunc(LegacyChallengeTemplateMixin, "Init", function(button) pcall(attachChallenge, button) end)
		installed.challengeInit = true
	end
	local scroll = challengeScroll()
	if scroll and scroll.ForEachFrame then scroll:ForEachFrame(function(button) pcall(attachChallenge, button) end) end
end

local function installTree()
	local frame = _G.LegacySystemFrame
	local panel = frame and frame.TreePage and frame.TreePage.LegacyTreeTraitPanel
	if not panel then return end
	if not panel.lnavHooked and panel.RegisterCallback then
		panel.lnavHooked = true
		panel:RegisterCallback("TalentButtonAcquired", function(_, button) pcall(attachNode, button) end, Hooks)
	end
	if panel.EnumerateAllTalentButtons then each(panel:EnumerateAllTalentButtons(), nil, nil, function(button) pcall(attachNode, button) end) end
end

-- Idempotent: also called by the panel whenever the Legacy window opens (pages build lazily).
function Hooks.Rescan()
	if not core then return end
	pcall(installChallenges)
	pcall(installTree)
end

function Hooks.Init(coreObject)
	core = coreObject
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	events:SetScript("OnEvent", function(_, _, name)
		if name == ADDON then Hooks.Rescan() end
	end)
	Hooks.Rescan() -- Blizzard_LegacySystem may already be loaded
end
