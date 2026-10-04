local _, ns = ...

-- Shared UI helpers (D25: the free-floating overlay is gone). Row component, goal/status text, tooltip, minimap
-- button and the toggle global; Tracker and Panel build on it. Data comes in through UI.Render(payload) from
-- Core:RenderUI; UI.Init(core) is the only place the core object is received (UI loads before Core).
local L, Text, Style = ns.L, ns.Text, ns.Style
local UI = {}
ns.UI = UI

local TOOLTIP_ITEMS = 5
local core, payload
local GAP = Style.gap

-- Bindings.xml calls this global; the strings below must exist before the binding UI is opened.
BINDING_HEADER_LEGACYNAVIGATOR = L["ui.title"]
BINDING_NAME_LEGACYNAVIGATOR_TOGGLE = L["ui.binding"]
local function toggle()
	if core then core:ToggleLegacyWindow() end
end
function LegacyNavigatorToggle() toggle() end

-- Perk name for a node: live spell name via Provider, "Vorteil <id>" when unreadable. trees = core.trees.
function UI.NodeLabel(trees, nodeID)
	local configID
	for _, tree in pairs(trees or {}) do
		if type(tree) == "table" and tree.nodes and tree.nodes[nodeID] then configID = tree.configID end
	end
	return ns.Provider.nodeName(configID, nodeID)
end

-- Text helpers ---------------------------------------------------------------------------------------

local function achievement(id) return payload and payload.catalogue and payload.catalogue.achievements[id] end

local function achievementName(id)
	local entry = achievement(id)
	return entry and entry.name or string.format(L["plan.unnamed"], id or 0)
end

local function colorName(charKey)
	local char = payload and payload.profile.characters[charKey]
	local color = char and char.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.classFile]
	local name = Text.name(charKey)
	if not color then return name end
	local function byte(v) return math.floor(v * 255 + 0.5) end
	return string.format("|cff%02x%02x%02x%s|r", byte(color.r), byte(color.g), byte(color.b), name)
end

local function hasWhy(card, key)
	for _, value in ipairs(card.why or {}) do if value == key then return true end end
	return false
end

local function stamp(time) return type(time) == "number" and date("%Y-%m-%d", time) or "?" end

-- Title = challenge name; second line = action first (missing, group, contribution, data); twink name first.
local function cardTexts(card)
	if card.action == "spend" then return string.format(L["plan.card.spend"], card.available or 0), "" end
	if card.action == "chooseGoal" then return L["plan.card.chooseGoal"], "" end
	local name = achievementName(card.achievementID)
	local parts = {}
	if card.charKey ~= payload.currentKey then parts[#parts + 1] = colorName(card.charKey) end
	if card.missing then parts[#parts + 1] = Text.missing(card) end
	if hasWhy(card, "groupRequired") then parts[#parts + 1] = L["plan.why.groupRequired"] end
	local contribution = Text.contribution(card, name)
	if contribution ~= "" then parts[#parts + 1] = contribution end
	local data = Text.data(card)
	if data ~= "" then parts[#parts + 1] = data end
	return name, table.concat(parts, " · ")
end

local function goalText()
	local result, goal = payload.result, payload.profile.goal
	if not goal then return L["ui.goal.none"] end
	if result and result.status == "invalid" then
		local reason = L["plan.reason." .. tostring(result.reason)]
		if result.reasonArg then reason = string.format(reason, result.reasonArg) end
		return string.format(L["ui.goal.invalid"], reason)
	end
	local name
	if goal.type == "challenge" then name = achievementName(goal.id)
	elseif goal.type == "node" then name = UI.NodeLabel(payload.trees, goal.nodeID) end
	return Text.goalLine(goal, name)
end

local function statusText()
	if payload.planError then return L["ui.status.planError"] end
	if payload.combatPending then return L["ui.status.combat"] end
	if payload.incomplete then return L["ui.status.incomplete"] end
	if payload.scanning and payload.result then return string.format(L["ui.status.loadingKept"], stamp(payload.resultAt)) end
	if payload.scanning then return L["ui.status.loading"] end
	if payload.loadingKept then return string.format(L["ui.status.loadingKept"], stamp(payload.resultAt)) end
	if not payload.result or payload.result.status == "loading" then return L["ui.status.loading"] end
end

-- Tooltip (9A): why[] bullets + open sub-goals, truncated.
local function openItemName(card, item)
	local entry = achievement(card.achievementID)
	for _, criterion in ipairs(entry and entry.criteria or {}) do
		if criterion.id == item then return criterion.text end
	end
	local helper = achievement(item)
	return helper and helper.name or tostring(item)
end

local function showTooltip(row, anchor)
	local card = row.card
	if not card or not card.achievementID then return end
	GameTooltip:SetOwner(row, type(anchor) == "string" and anchor or "ANCHOR_RIGHT")
	GameTooltip:AddLine(achievementName(card.achievementID), 1, 1, 1)
	local note = Text.pointNote(card)
	if note ~= "" then GameTooltip:AddLine(note, 0.9, 0.9, 0.9) end
	local why = Text.why(card)
	if #why > 0 then
		GameTooltip:AddLine(L["ui.tooltip.why"], unpack(Style.color.title))
		for _, line in ipairs(why) do GameTooltip:AddLine("• " .. line, 0.9, 0.9, 0.9) end
	end
	local items = card.missing and card.missing.items
	if items and #items > 0 then
		GameTooltip:AddLine(L["ui.tooltip.open"], unpack(Style.color.title))
		for i = 1, math.min(#items, TOOLTIP_ITEMS) do GameTooltip:AddLine("• " .. openItemName(card, items[i]), 0.9, 0.9, 0.9) end
		if #items > TOOLTIP_ITEMS then GameTooltip:AddLine(string.format(L["ui.tooltip.more"], #items - TOOLTIP_ITEMS), unpack(Style.color.sub)) end
	end
	GameTooltip:AddLine(L["hooks.hint.goal"], 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

UI.ShowTooltip = showTooltip -- shared with the tracker rows
-- Shared with the docked panel; they read the payload UI.Render stored last (Core renders UI before Panel).
function UI.GoalText() return payload and goalText() end
function UI.StatusText() return payload and statusText() end
UI.ColorName, UI.AchievementName = colorName, achievementName

-- "Zum Legacy-Fenster" buttons (D22/D24): visible whenever offered; dimmed + explained only in combat.
local function legacyOnEnter(button)
	local reason, text = core and core:LegacyBlock()
	if not reason then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine(text, 1, 1, 1, true)
	GameTooltip:Show()
end

local function legacyOnLeave(button) if GameTooltip:IsOwned(button) then GameTooltip:Hide() end end

local function legacyState(button)
	local reason = core and core:LegacyBlock()
	button:SetEnabled(reason ~= "combat")
	button:SetAlpha(reason and 0.5 or 1)
end

-- Row component (reusable by tracker / panel) ----------------------------------------------------------

-- Title line + wrapped second line (max 2 lines, height from GetStringHeight) + right-aligned action.
function UI.CreateRow(parent, width)
	local row = CreateFrame("Frame", nil, parent)
	row:SetWidth(width)
	row:EnableMouse(true)
	row.marker = row:CreateTexture(nil, "OVERLAY")
	row.marker:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow") -- the font has no reliable arrow glyph
	row.marker:SetSize(12, 12)
	row.marker:SetPoint("TOPLEFT", 0, -1)
	row.action = Style.Button(row, "")
	row.action:SetPoint("TOPRIGHT", 0, 0)
	row.title = Style.Font(row:CreateFontString(nil, "OVERLAY"), "row")
	row.title:SetJustifyH("LEFT")
	row.sub = Style.Font(row:CreateFontString(nil, "OVERLAY"), "sub", "sub")
	row.sub:SetJustifyH("LEFT")
	if row.sub.SetMaxLines then row.sub:SetMaxLines(2) end
	if row.title.SetMaxLines then row.title:SetMaxLines(1) end
	row:SetScript("OnEnter", showTooltip)
	row:SetScript("OnMouseUp", function(self, button)
		if not (self.card and self.card.achievementID and core and self:IsMouseOver()) then return end
		if button == "LeftButton" then core:JumpToCard(self.card)
		elseif button == "MiddleButton" then core:SetChallengeGoal(self.card.achievementID, true) end
	end)
	local function leave() if GameTooltip:IsOwned(row) then GameTooltip:Hide() end end
	row:SetScript("OnLeave", leave)
	row:SetScript("OnHide", leave)
	row.action:SetScript("OnClick", function()
		-- Pin toggle is a pure SavedVariables action; the Legacy window path checks combat in Provider.
		if not (row.card and core) then return end
		if row.card.action == "spend" then core:OpenLegacyWindow() else core:TogglePin(row.card) end
	end)
	row.action:SetScript("OnEnter", function(button) if row.card and row.card.action == "spend" then legacyOnEnter(button) end end)
	row.action:SetScript("OnLeave", legacyOnLeave)
	return row
end

-- card: planner card; pinned: profile.pinned; marker: show the current-character arrow.
function UI.SetRow(row, card, pinned, marker)
	row.card = card
	local title, sub = cardTexts(card)
	local pinnable = card.action == "pin"
	local spend = card.action == "spend"
	local isPinned = pinnable and pinned and pinned.achievementID == card.achievementID
	local indent = marker and 16 or 0
	row.marker:SetShown(marker == true)
	row.action:SetShown(pinnable or spend)
	if pinnable then
		row.action:SetEnabled(true); row.action:SetAlpha(1)
		row.action:SetLabel(L[isPinned and "ui.pinnedBtn" or "ui.pin"])
	elseif spend then
		row.action:SetLabel(L["ui.legacy"])
		legacyState(row.action)
	end
	local actionWidth = (pinnable or spend) and row.action:GetWidth() + GAP or 0
	row.title:ClearAllPoints()
	row.title:SetPoint("TOPLEFT", indent, 0)
	row.title:SetWidth(row:GetWidth() - indent - actionWidth)
	row.title:SetText(title)
	row.sub:ClearAllPoints()
	row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
	row.sub:SetWidth(row:GetWidth() - indent - actionWidth)
	row.sub:SetText(sub)
	local height = row.title:GetStringHeight()
	if sub ~= "" then height = height + 2 + row.sub:GetStringHeight() end
	row:SetHeight(math.max(height, (pinnable or spend) and 20 or 0))
	return row:GetHeight()
end

-- Core entry point ----------------------------------------------------------------------------------

function UI.Render(data) payload = data end

local function setupMinimap()
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	local icon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not (ldb and icon) then return end -- lib missing: no minimap button, nothing else changes
	local object = ldb:GetDataObjectByName("LegacyNavigator") or ldb:NewDataObject("LegacyNavigator", {
		type = "launcher", text = L["ui.title"], icon = "Interface\\Icons\\INV_Misc_Map_01",
		OnClick = function(_, button) if button == "LeftButton" then toggle() end end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine(L["ui.title"])
			tooltip:AddLine(L["ui.minimap.hint"], 1, 1, 1)
		end,
	})
	if object and not icon:IsRegistered("LegacyNavigator") then icon:Register("LegacyNavigator", object, core.db.profile.minimap) end
end

function UI.Init(coreObject)
	core = coreObject
	setupMinimap()
end
