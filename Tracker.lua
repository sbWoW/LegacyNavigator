local _, ns = ...

-- Tracker (architecture.md Etappe 4): a flat, chrome-less block under the quest tracker. Own unprotected frames
-- only. Anchor (R3/D4): a plain SetPoint below ObjectiveTrackerFrame, decided inside our own Render; no hooks on
-- Blizzard frames, no reparenting. Tracker.Content is pure (no frames) so it loads and tests offline.
local L, Text, Style = ns.L, ns.Text, ns.Style
local Tracker = {}
ns.Tracker = Tracker

local WIDTH, MAX_LOCAL, DONE_SECONDS, FADE_SECONDS = 260, 2, 8, 0.5
local FALLBACK = { "TOPRIGHT", -60, -260 }
local createFrame
local core, frame, payload, state -- state = { event, phase = "done" | "fading" | "next" } after a completion

-- Content (pure) -----------------------------------------------------------------------------------------

local function achievementName(data, id)
	local entry = data.catalogue and data.catalogue.achievements and data.catalogue.achievements[id]
	return entry and entry.name or string.format(L["plan.unnamed"], id or 0)
end

local function colorName(data, charKey)
	local char = data.profile.characters and data.profile.characters[charKey]
	local color = char and char.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.classFile]
	local name = Text.name(charKey)
	if not color then return name end
	local function byte(v) return math.floor(v * 255 + 0.5) end
	return string.format("|cff%02x%02x%02x%s|r", byte(color.r), byte(color.g), byte(color.b), name)
end

local function findCard(result, id, charKey)
	for _, list in ipairs({ result and result.cards or {}, result and result.alternatives or {} }) do
		for _, card in ipairs(list) do
			if card.achievementID == id and card.charKey == charKey then return card end
		end
	end
end

-- data: the Core render payload; event: the one-shot {kind = "completed"} (payload.completed or the kept copy).
-- Returns nil (nothing to show) or { pinnedLine, localLines (max 2), completed }; every line is { text, card }.
function Tracker.Content(data, event)
	if not (data and data.profile) then return nil end
	event = event or data.completed
	local out, pinned, result = { localLines = {} }, data.profile.pinned, data.result
	if pinned then
		local parts = { achievementName(data, pinned.achievementID) }
		if pinned.charKey ~= data.currentKey then parts[#parts + 1] = colorName(data, pinned.charKey) end
		local card = findCard(result, pinned.achievementID, pinned.charKey)
		if card and card.missing then parts[#parts + 1] = Text.missing(card) end
		out.pinnedLine = {
			text = table.concat(parts, " · "), charKey = pinned.charKey, achievementID = pinned.achievementID,
			card = card or { achievementID = pinned.achievementID, charKey = pinned.charKey },
		}
	end
	local pinnedID = pinned and pinned.achievementID
	for _, opp in ipairs(result and result["local"] or {}) do
		if #out.localLines >= MAX_LOCAL then break end
		if opp.achievementID ~= pinnedID and (opp.charKey == nil or opp.charKey == data.currentKey) then
			local text = achievementName(data, opp.achievementID)
			if opp.missing then text = text .. " · " .. Text.missing(opp) end
			out.localLines[#out.localLines + 1] = { text = text, card = opp }
		end
	end
	if event and event.kind == "completed" then
		local name = achievementName(data, event.achievementID)
		out.completed = { text = string.format(L["tracker.done"], name), charKey = event.charKey }
		for _, card in ipairs(result and result.cards or {}) do
			if card.action == "pin" and card.achievementID ~= event.achievementID then
				out.completed.nextCard = card
				out.completed.nextText = string.format(L["tracker.next"], achievementName(data, card.achievementID))
				break
			end
		end
	end
	if not (out.pinnedLine or out.completed or #out.localLines > 0) then return nil end
	return out
end

-- Frames ---------------------------------------------------------------------------------------------------

local function openOverlay()
	if core and ns.UI then core:CallUI(ns.UI.Toggle) end
end

-- A flat clickable text line with hover highlight and the overlay's tooltip.
local function createLine(parent, role, color)
	local line = CreateFrame("Button", nil, parent)
	line:SetWidth(WIDTH)
	local hover = line:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(); hover:SetColorTexture(unpack(Style.color.hover))
	line.text = Style.Font(line:CreateFontString(nil, "OVERLAY"), role, color)
	line.text:SetPoint("TOPLEFT"); line.text:SetWidth(WIDTH); line.text:SetJustifyH("LEFT")
	if line.text.SetMaxLines then line.text:SetMaxLines(2) end
	line:SetScript("OnClick", function(self)
		if self.onClick then self.onClick() else openOverlay() end
	end)
	line:SetScript("OnEnter", function(self) if self.card and ns.UI and ns.UI.ShowTooltip then ns.UI.ShowTooltip(self, "ANCHOR_LEFT") end end)
	line:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
	line:SetScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
	return line
end

local function unlocked() return core and core.db.profile.ui.tracker.locked == false end

-- R3/D4: decided here and nowhere else (our Render, PLAYER_ENTERING_WORLD, lock/reset); never from a Blizzard script.
function Tracker.Anchor()
	if not (frame and core) then return end
	local ui = core.db.profile.ui.tracker
	frame:ClearAllPoints()
	if ui.custom then
		frame:SetPoint(ui.point or FALLBACK[1], UIParent, ui.point or FALLBACK[1], ui.x or FALLBACK[2], ui.y or FALLBACK[3])
	elseif ObjectiveTrackerFrame and ObjectiveTrackerFrame.IsVisible and ObjectiveTrackerFrame:IsVisible() then
		frame:SetPoint("TOPRIGHT", ObjectiveTrackerFrame, "BOTTOMRIGHT", 0, -8)
	else
		frame:SetPoint(FALLBACK[1], UIParent, FALLBACK[1], FALLBACK[2], FALLBACK[3])
	end
end

function Tracker.ApplyPositions()
	if not frame and core and payload then createFrame() end
	if not frame then return end
	Tracker.Anchor()
	Tracker.Refresh()
end

local function savePosition()
	local right, top = frame:GetRight(), frame:GetTop()
	if not (right and top and UIParent:GetRight() and UIParent:GetTop()) then return end
	local ui = core.db.profile.ui.tracker
	ui.point, ui.x, ui.y, ui.custom = "TOPRIGHT", right - UIParent:GetRight(), top - UIParent:GetTop(), true
	Tracker.Anchor()
end

function createFrame()
	local f = CreateFrame("Frame", "LegacyNavigatorTracker", UIParent)
	f:SetSize(WIDTH, 20)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:Hide()
	f.header = createLine(f, "row", "accent")
	f.header.text:SetText(L["tracker.header"])
	f.header:SetHeight(16)
	f.header:RegisterForDrag("LeftButton")
	f.header:SetScript("OnDragStart", function() if unlocked() then f:StartMoving() end end)
	f.header:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePosition() end)
	f.pinned = createLine(f, "sub", "text")
	f.hereHeader = Style.Font(f:CreateFontString(nil, "OVERLAY"), "sub", "title")
	f.hereHeader:SetText(L["tracker.here"])
	f.locals = { createLine(f, "sub", "sub"), createLine(f, "sub", "sub") }
	-- No OnUpdate: a one-shot alpha animation fades the "done" line out.
	local group = f.pinned:CreateAnimationGroup()
	local alpha = group:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1); alpha:SetToAlpha(0); alpha:SetDuration(FADE_SECONDS)
	group:SetScript("OnFinished", function()
		if state then state.phase = "next" end
		Tracker.Refresh()
	end)
	f.fade = group
	frame = f
	Tracker.Anchor()
end

-- Lays out the block top down; hidden entirely when there is nothing to show (and the tracker is locked).
function Tracker.Refresh()
	if not (frame and payload and core) then return end
	local ui = core.db.profile.ui.tracker
	local content = ui.shown ~= false and Tracker.Content(payload, state and state.event) or nil
	if not content and not (ui.shown ~= false and unlocked()) then frame:Hide(); return end
	frame:Show()
	local y = 0
	local function put(region, gap)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
		region:Show()
		y = y - (gap or 0)
	end
	put(frame.header, 16 + 2)

	local line = frame.pinned
	frame.pinned.onClick, frame.pinned.card = nil, nil
	frame.pinned.text:SetTextColor(unpack(Style.color.text))
	if content and content.completed and state and state.phase ~= "next" then
		frame.pinned.text:SetText(content.completed.text)
		frame.pinned.text:SetTextColor(0.4, 0.85, 0.4)
	elseif content and content.completed and content.completed.nextCard then
		local next = content.completed
		frame.pinned.text:SetText(next.nextText)
		frame.pinned.card = next.nextCard
		frame.pinned.onClick = function() core:TogglePin(next.nextCard) end
	elseif content and content.pinnedLine then
		frame.pinned.text:SetText(content.pinnedLine.text)
		frame.pinned.card = content.pinnedLine.card
	else
		line = nil
	end
	if line then
		local h = frame.pinned.text:GetStringHeight()
		frame.pinned:SetHeight(h)
		put(frame.pinned, h + 4)
	else
		frame.pinned:Hide()
	end
	local locals = content and content.localLines or {}
	if #locals > 0 then
		put(frame.hereHeader, frame.hereHeader:GetStringHeight() + 2)
	else
		frame.hereHeader:Hide()
	end
	for i, row in ipairs(frame.locals) do
		local entry = locals[i]
		if entry then
			row.text:SetText(entry.text)
			row.card = entry.card
			local h = row.text:GetStringHeight()
			row:SetHeight(h)
			put(row, h + 2)
		else
			row.card = nil
			row:Hide()
		end
	end
	frame:SetHeight(math.max(-y, 16))
end

-- Core entry point: every render pass (Replan) lands here, under Core's pcall.
function Tracker.Render(data)
	payload = data
	if data.completed and data.completed.kind == "completed" then
		if state and state.timer then core:CancelTimer(state.timer) end
		state = { event = data.completed, phase = "done" }
		state.timer = core:ScheduleTimer(function()
			if not state then return end
			state.timer = nil
			if state.phase ~= "done" then return end
			state.phase = "fading"
			if frame and frame:IsShown() and frame.pinned:IsShown() then frame.fade:Play() else state.phase = "next"; Tracker.Refresh() end
		end, DONE_SECONDS)
	elseif state and data.profile.pinned then -- the user pinned something: the follow-up line is obsolete
		if state.timer then core:CancelTimer(state.timer) end
		state = nil
	end
	if not frame then
		if data.profile.ui.tracker.shown == false then return end
		createFrame()
	end
	Tracker.Anchor()
	Tracker.Refresh()
end

function Tracker.Init(coreObject)
	core = coreObject
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", function() core:CallUI(Tracker.Anchor) end)
end
