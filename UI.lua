local _, ns = ...

-- Overlay (architecture.md 12.1-12.6). Own unprotected frames, created once, shown/hidden. The data comes in
-- through UI.Render(payload) from Core:RenderUI; UI.Init(core) is the only place the core object is received
-- (UI loads before Core, so ns.Core must not be captured at load time).
local L, Text, Style = ns.L, ns.Text, ns.Style
local UI = {}
ns.UI = UI

local FRAME_NAME = "LegacyNavigatorOverlay"
local MAX_ROWS, TOOLTIP_ITEMS = 3, 5
local core, frame, payload
local W, PAD, GAP = Style.width, Style.pad, Style.gap
local INNER = W - 2 * PAD

-- Bindings.xml calls this global; the strings below must exist before the binding UI is opened.
BINDING_HEADER_LEGACYNAVIGATOR = L["ui.title"]
BINDING_NAME_LEGACYNAVIGATOR_TOGGLE = L["ui.binding"]
local function toggle()
	if core then core:CallUI(UI.Toggle) else UI.Toggle() end
end
function LegacyNavigatorToggle() toggle() end

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
	parts[#parts + 1] = Text.contribution(card, name)
	local data = Text.data(card)
	if data ~= "" then parts[#parts + 1] = data end
	return name, table.concat(parts, " · ")
end

local function goalText()
	local result, goal = payload.result, payload.profile.goal
	if not goal then return L["ui.goal.none"] end
	local g = result and result.goal or {}
	if result and result.status == "invalid" then
		local reason = L["plan.reason." .. tostring(result.reason)]
		if result.reasonArg then reason = string.format(reason, result.reasonArg) end
		return string.format(L["ui.goal.invalid"], reason)
	end
	local text
	if goal.type == "points" then text = string.format(L["ui.goal.points"], goal.need or 0)
	elseif goal.type == "renown" then text = string.format(L["ui.goal.renown"], goal.level or 0)
	elseif goal.type == "challenge" then text = string.format(L["ui.goal.challenge"], achievementName(goal.id))
	elseif goal.type == "node" then
		text = g.need and string.format(L["ui.goal.nodeNeed"], goal.nodeID or 0, g.need) or string.format(L["ui.goal.node"], goal.nodeID or 0)
	else text = "?" end
	if result and result.status == "reachable" then text = text .. L["ui.goal.reachable"]
	elseif g.remaining and g.remaining > 0 then text = text .. string.format(L["ui.goal.missing"], g.remaining) end
	return text
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

local function showTooltip(row)
	local card = row.card
	if not card or not card.achievementID then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(achievementName(card.achievementID), 1, 1, 1)
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
	GameTooltip:Show()
end

-- "Zum Legacy-Fenster" buttons (D22): visible whenever offered; dimmed + explained when it cannot act now.
local function legacyOnEnter(button)
	local reason, text = core and core:LegacyBlock()
	if not reason then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine(text, 1, 1, 1, true)
	GameTooltip:Show()
end

local function legacyOnLeave(button) if GameTooltip:IsOwned(button) then GameTooltip:Hide() end end

-- Wires the click path once; legacyState re-evaluates the look on every refresh.
local function legacySetup(button)
	button:SetScript("OnClick", function() if core then core:OpenLegacyWindow() end end)
	button:SetScript("OnEnter", legacyOnEnter)
	button:SetScript("OnLeave", legacyOnLeave)
	button:SetScript("OnHide", legacyOnLeave)
end

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

-- Frame ----------------------------------------------------------------------------------------------

function UI.ApplyPositions()
	if not frame then return end
	local pos = core.db.profile.ui.overlay
	frame:ClearAllPoints()
	frame:SetPoint(pos.point or "TOP", UIParent, pos.point or "TOP", pos.x or 0, pos.y or -160)
end

local function savePosition()
	local left, top = frame:GetLeft(), frame:GetTop()
	if not (left and top and UIParent:GetLeft() and UIParent:GetTop()) then return end
	local pos = core.db.profile.ui.overlay
	pos.point, pos.x, pos.y = "TOPLEFT", left - UIParent:GetLeft(), top - UIParent:GetTop()
	UI.ApplyPositions() -- re-anchor to the saved point so later height changes grow downward
end

local function createFrame()
	local f = CreateFrame("Frame", FRAME_NAME, UIParent)
	f:SetSize(W, 80)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:Hide()
	f:EnableMouse(true) -- swallow clicks on the overlay
	Style.Panel(f)

	local bar = CreateFrame("Frame", nil, f) -- drag handle
	bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT"); bar:SetHeight(24)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() f:StartMoving() end)
	bar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePosition() end)
	f.title = Style.Font(bar:CreateFontString(nil, "OVERLAY"), "title", "title")
	f.title:SetPoint("LEFT", PAD, 0)
	f.title:SetText(L["ui.title"])
	f.close = Style.CloseButton(bar)
	f.close:SetPoint("RIGHT", -4, 0)
	f.close:SetScript("OnClick", function() f:Hide() end)

	f.goal = Style.Font(f:CreateFontString(nil, "OVERLAY"), "goal", "accent")
	f.goal:SetJustifyH("LEFT"); f.goal:SetWidth(INNER)
	f.legacy = Style.Button(f, L["ui.legacy"]) -- goal line, only while the goal is reachable
	legacySetup(f.legacy)
	f.pinned = Style.Font(f:CreateFontString(nil, "OVERLAY"), "sub", "text")
	f.pinned:SetJustifyH("LEFT")
	f.unpin = Style.Button(f, L["ui.unpin"])
	f.unpin:SetScript("OnClick", function() if core then core:Unpin() end end)
	f.status = Style.Font(f:CreateFontString(nil, "OVERLAY"), "sub", "warn")
	f.status:SetJustifyH("LEFT"); f.status:SetWidth(INNER)
	f.divider = Style.Divider(f)
	f.empty = Style.Font(f:CreateFontString(nil, "OVERLAY"), "sub", "sub")
	f.empty:SetJustifyH("LEFT"); f.empty:SetWidth(INNER)
	f.here = Style.Font(f:CreateFontString(nil, "OVERLAY"), "sub", "sub") -- "Here:" line until the tracker exists
	f.here:SetJustifyH("LEFT"); f.here:SetWidth(INNER)
	f.rows = {}
	for i = 1, MAX_ROWS do f.rows[i] = UI.CreateRow(f, INNER) end
	table.insert(UISpecialFrames, FRAME_NAME) -- ESC closes
	frame = f -- last: a failed construction leaves frame nil and retries next time
	UI.ApplyPositions()
end

-- Lay out top to bottom; every block that is empty takes no space.
function UI.Refresh()
	if not (frame and payload) then return end
	local y = -26
	local function place(region, x, width)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", frame, "TOPLEFT", x or PAD, y)
		return region
	end

	local first = payload.result and payload.result.cards and payload.result.cards[1]
	local reachable = payload.result ~= nil and payload.result.status == "reachable" and first ~= nil and first.action == "spend"
	frame.goal:SetWidth(reachable and INNER - frame.legacy:GetWidth() - GAP or INNER)
	frame.goal:SetText(goalText())
	place(frame.goal)
	if reachable then
		legacyState(frame.legacy)
		frame.legacy:ClearAllPoints()
		frame.legacy:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, y + 2)
		frame.legacy:Show()
	else
		frame.legacy:Hide()
	end
	y = y - math.max(frame.goal:GetStringHeight(), reachable and 20 or 0) - 6

	local pinned, result = payload.profile.pinned, payload.result
	if pinned then
		local label = achievementName(pinned.achievementID)
		local detail
		if payload.profile.account and payload.profile.account.completed and payload.profile.account.completed[pinned.achievementID] then
			label = string.format(L["ui.pinned.done"], label)
		else
			for _, list in ipairs({ result and result.cards or {}, result and result.alternatives or {} }) do
				for _, card in ipairs(list) do
					if card.achievementID == pinned.achievementID and card.charKey == pinned.charKey and card.missing then detail = Text.missing(card) end
				end
			end
			label = string.format(L["ui.pinned"], label)
			if pinned.charKey ~= payload.currentKey then label = label .. " · " .. colorName(pinned.charKey) end
			if detail then label = label .. " · " .. detail end
		end
		frame.pinned:SetWidth(INNER - frame.unpin:GetWidth() - GAP)
		frame.pinned:SetText(label)
		place(frame.pinned)
		frame.unpin:ClearAllPoints()
		frame.unpin:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, y + 2)
		frame.pinned:Show(); frame.unpin:Show()
		y = y - math.max(frame.pinned:GetStringHeight(), 20) - 6
	else
		frame.pinned:Hide(); frame.unpin:Hide()
	end

	local status = statusText()
	if status then
		frame.status:SetText(status)
		place(frame.status):Show()
		y = y - frame.status:GetStringHeight() - 6
	else
		frame.status:Hide()
	end

	local cards = result and result.cards or {}
	local showRows = result ~= nil and (result.status == "ok" or result.status == "reachable") and #cards > 0
	local showEmpty = result ~= nil and result.status == "none"
	if showRows or showEmpty then
		frame.divider:ClearAllPoints()
		frame.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
		frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, y)
		frame.divider:Show()
		y = y - 1 - GAP
	else
		frame.divider:Hide()
	end

	if showEmpty then
		local reason = L["plan.reason." .. tostring(result.reason)]
		frame.empty:SetText(L["ui.empty"] .. "\n" .. reason .. "\n" .. L["ui.empty.hint"])
		place(frame.empty):Show()
		y = y - frame.empty:GetStringHeight() - GAP
	else
		frame.empty:Hide()
	end

	for i, row in ipairs(frame.rows) do
		local card = showRows and cards[i]
		if card then
			place(row, PAD)
			y = y - UI.SetRow(row, card, pinned, i == 1 and card.charKey == payload.currentKey) - GAP
			row:Show()
		else
			row.card = nil
			row:Hide()
		end
	end
	local opp = result and result["local"] and result["local"][1]
	if opp then
		local text = achievementName(opp.achievementID)
		if opp.missing then text = text .. " · " .. Text.missing(opp) end
		frame.here:SetText(string.format(L["ui.here"], text))
		place(frame.here):Show()
		y = y - frame.here:GetStringHeight() - GAP
	else
		frame.here:Hide()
	end
	frame:SetHeight(-y + PAD - GAP + 4)
end

-- Core entry points ----------------------------------------------------------------------------------

function UI.Render(data)
	payload = data
	if frame and frame:IsShown() then UI.Refresh() end
end

function UI.Show()
	if not core then return end
	if not frame then createFrame() end
	frame:Show()
	if payload then UI.Refresh() else core:RenderUI() end
end

function UI.Toggle()
	if frame and frame:IsShown() then frame:Hide() else UI.Show() end
end

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
