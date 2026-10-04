local _, ns = ...

-- Docked panel (architecture.md Etappe 3b, 15A). Our own frame, parented to UIParent and anchored with a plain
-- SetPoint next to LegacySystemFrame; shown only while that window is shown. Blizzard's frame is only read
-- (IsShown, size, edges), never hooked, modified or reparented. The pure helpers (ProgressModel, GoalMenuModel,
-- SettingsModel, CharacterRows, DockSide) have no frames and are tested offline.
local L, Text, Style, def = ns.L, ns.Text, ns.Style, ns.Definitions
local Panel = {}
ns.Panel = Panel

local HOST_NAME, HOST_ADDON = "LegacySystemFrame", "Blizzard_LegacySystem"
local WIDTH, PAD, GAP, GAP_HOST = 320, Style.pad, Style.gap, 4
local INNER = WIDTH - 2 * PAD
local ICON, ICON_GAP, MAX_ROWS, MAX_CHARS, POLL = 24, 6, 3, 10, 0.25
local MENU_SCROLL = 400
local SETTING_KEYS = { "dungeon", "raid", "pvp", "switch", "tracker", "minimap" }
local core, frame, payload, driver
local tab = "plan"

-- Pure helpers ---------------------------------------------------------------------------------------

-- Bar only with a reliable denominator: points (available / need) and renown (renown / level).
-- Node goals are a minimum need with unchecked prerequisites: text only. Everything else: no extra line.
function Panel.ProgressModel(goal, result)
	local g = result and result.goal or {}
	if not goal or not result or result.status == "invalid" then return { bar = false, text = "" } end
	if goal.type == "points" and type(g.need) == "number" and type(g.available) == "number" and g.need > 0 then
		return { bar = true, value = math.min(g.available, g.need), max = g.need, text = string.format(L["panel.progress.points"], g.available, g.need) }
	elseif goal.type == "renown" and type(g.level) == "number" and type(g.need) == "number" and g.level > 0 then
		local value = math.max(0, math.min(g.level, g.level - g.need))
		return { bar = true, value = value, max = g.level, text = string.format(L["panel.progress.renown"], value, g.level) }
	elseif goal.type == "node" then
		return { bar = false, text = type(g.need) == "number" and string.format(L["panel.progress.nodeNeed"], g.need) or L["panel.progress.node"] }
	end
	return { bar = false, text = "" }
end

local function sortedKeys(t, less)
	local keys = {}
	for key in pairs(t) do keys[#keys + 1] = key end
	table.sort(keys, less)
	return keys
end

-- Menu structure: entries are { text, action = { kind, a, b } } (leaf, same arguments as /lnav goal) or
-- { text, children = { ... } }. completed: account.completed. Challenges mirror Core:GoalProblem
-- (rated, activity enabled) and add: points > 0, not yet completed.
function Panel.GoalMenuModel(catalogue, settings, trees, completed)
	local menu = { { text = L["panel.menu.none"], action = { kind = "clear" } } }
	local points = {}
	for n = 1, def.maxPoints do points[n] = { text = string.format(L["panel.menu.pointsN"], n), action = { kind = "points", a = n } } end
	menu[#menu + 1] = { text = L["panel.menu.points"], children = points }

	local renown, seen = {}, {}
	for _, level in ipairs(def.renownRewardLevels) do
		seen[level] = true
		renown[#renown + 1] = { text = string.format(L["panel.menu.renownReward"], level), action = { kind = "renown", a = level } }
	end
	for level = 5, def.maxRenown, 5 do
		if not seen[level] then renown[#renown + 1] = { text = string.format(L["panel.menu.renownN"], level), action = { kind = "renown", a = level } } end
	end
	menu[#menu + 1] = { text = L["panel.menu.renown"], children = renown }

	local activities = settings and settings.activities or {}
	local byCategory = {}
	for id, ach in pairs(catalogue and catalogue.achievements or {}) do
		if type(ach.points) == "number" and ach.points > 0 and ach.activity ~= "unrated" and activities[ach.activity] == true
			and not (completed and completed[id]) then
			local list = byCategory[ach.categoryID]
			if not list then list = {}; byCategory[ach.categoryID] = list end
			list[#list + 1] = { text = ach.name or string.format(L["plan.unnamed"], id), action = { kind = "challenge", a = id }, id = id }
		end
	end
	local groups = {}
	for categoryID, list in pairs(byCategory) do
		table.sort(list, function(x, y) if x.text ~= y.text then return x.text < y.text end return x.id < y.id end)
		local info = catalogue.categories and catalogue.categories[categoryID]
		groups[#groups + 1] = { text = info and info.name or tostring(categoryID), children = list, id = categoryID }
	end
	table.sort(groups, function(x, y) if x.text ~= y.text then return x.text < y.text end return x.id < y.id end)
	if #groups > 0 then menu[#menu + 1] = { text = L["panel.menu.challenge"], children = groups } end

	local treeGroups = {}
	for index, treeID in ipairs(def.treeIDs) do
		local tree = type(trees) == "table" and trees[treeID]
		if type(tree) == "table" and not tree.incomplete and tree.nodes then
			local nodes = {}
			for _, nodeID in ipairs(sortedKeys(tree.nodes)) do
				local node = tree.nodes[nodeID]
				local maxRanks = node.maxRanks or 1
				if (node.currentRank or 0) < maxRanks then
					nodes[#nodes + 1] = { text = string.format(L["panel.menu.nodeN"], nodeID, node.currentRank or 0, maxRanks), action = { kind = "node", a = nodeID } }
				end
			end
			if #nodes > 0 then treeGroups[#treeGroups + 1] = { text = string.format(L["panel.menu.tree"], index), children = nodes } end
		end
	end
	if #treeGroups > 0 then menu[#menu + 1] = { text = L["panel.menu.node"], children = treeGroups } end
	return menu
end

-- [{ key, value }] in display order; read from the profile only.
function Panel.SettingsModel(profile)
	local settings = profile.settings or {}
	local acts = settings.activities or {}
	local trackerUI = profile.ui and profile.ui.tracker or {}
	return {
		{ key = "dungeon", value = acts.dungeon == true }, { key = "raid", value = acts.raid == true },
		{ key = "pvp", value = acts.pvp == true }, { key = "switch", value = settings.allowCharacterSwitch ~= false },
		{ key = "tracker", value = trackerUI.shown ~= false }, { key = "minimap", value = not (profile.minimap and profile.minimap.hide) },
	}
end

-- Known characters, current first is not required: Model sorts by key. Only fields that exist are filled.
function Panel.CharacterRows(profile, currentKey, currentConfirmed, build)
	local rows = {}
	for _, entry in ipairs(ns.Model.listCharacters(profile, currentKey, currentConfirmed, build)) do
		local char = profile.characters[entry.key] or {}
		rows[#rows + 1] = {
			key = entry.key, state = entry.state, capturedAt = entry.capturedAt, classFile = char.classFile, level = char.level,
			available = char.points and char.points.available,
		}
	end
	return rows
end

-- "right" when panel and the host's side tabs fit to the right of the host, else "left".
-- All values in UIParent coordinates; tabWidth is the width of the host's side tabs (they hang right of it).
function Panel.DockSide(hostRight, tabWidth, panelWidth, screenRight)
	if hostRight + (tabWidth or 0) + GAP_HOST + panelWidth <= screenRight then return "right" end
	return "left"
end

-- Frame helpers --------------------------------------------------------------------------------------

local function host() return _G[HOST_NAME] end

local function openGoalMenu(owner)
	if not core then return end
	local profile = core.db.profile
	local model = Panel.GoalMenuModel(core.catalogue, profile.settings, core.trees, profile.account and profile.account.completed)
	local function pick(action) core:SetGoal(action.kind, action.a, action.b) end
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			local function fill(parent, entries)
				for _, entry in ipairs(entries) do
					if entry.children then
						local sub = parent:CreateButton(entry.text)
						if sub.SetScrollMode then sub:SetScrollMode(MENU_SCROLL) end
						fill(sub, entry.children)
					else
						parent:CreateButton(entry.text, function() pick(entry.action) end)
					end
				end
			end
			fill(root, model)
		end)
	elseif UIDropDownMenu_Initialize and ToggleDropDownMenu and UIDropDownMenu_AddButton then
		-- ponytail: the fallback has no scrolling; long challenge/node lists need MenuUtil (modern client).
		local menu = Panel.dropdown or CreateFrame("Frame", "LegacyNavigatorGoalMenu", UIParent, "UIDropDownMenuTemplate")
		Panel.dropdown = menu
		local function convert(entries)
			local list = {}
			for _, entry in ipairs(entries) do
				local info = { text = entry.text, notCheckable = true }
				if entry.children then info.hasArrow, info.menuList = true, convert(entry.children)
				else info.func = function() CloseDropDownMenus(); pick(entry.action) end end
				list[#list + 1] = info
			end
			return list
		end
		local root = convert(model)
		UIDropDownMenu_Initialize(menu, function(_, level, menuList)
			for _, info in ipairs(level == 1 and root or menuList or {}) do UIDropDownMenu_AddButton(info, level) end
		end, "MENU")
		ToggleDropDownMenu(1, nil, menu, owner, 0, 0)
	end
end

local function applySetting(key, value)
	if not core then return end
	if key == "tracker" then core:SetTrackerShown(value and "on" or "off")
	elseif key == "minimap" then core:SetMinimapShown(value)
	else core:SetSetting(key, value and "on" or "off") end
end

local function stamp(time) return type(time) == "number" and date("%Y-%m-%d", time) or "?" end

-- Tabs -----------------------------------------------------------------------------------------------

local TABS = {
	{ id = "plan", key = "panel.tab.plan" },
	{ id = "chars", key = "panel.tab.chars" },
	{ id = "settings", key = "panel.tab.settings" },
}

local function hasContent(id)
	if id == "plan" then return payload.result ~= nil or ns.UI.StatusText() ~= nil end
	if id == "chars" then return next(payload.profile.characters or {}) ~= nil end
	return true
end

local function place(region, parent, x, y)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	return region
end

local function layoutPlan(c)
	local UI, result, y = ns.UI, payload.result, 0
	local status = UI.StatusText()
	if status then
		c.status:SetText(status)
		place(c.status, c, 0, y):Show()
		y = y - c.status:GetStringHeight() - 6
	else
		c.status:Hide()
	end
	local cards = result and result.cards or {}
	local showRows = result ~= nil and (result.status == "ok" or result.status == "reachable") and #cards > 0
	if result and result.status == "none" then
		c.empty:SetText(L["ui.empty"] .. "\n" .. L["plan.reason." .. tostring(result.reason)] .. "\n" .. L["ui.empty.hint"])
		place(c.empty, c, 0, y):Show()
		y = y - c.empty:GetStringHeight() - GAP
	else
		c.empty:Hide()
	end
	for i, wrap in ipairs(c.rows) do
		local card = showRows and cards[i]
		if card then
			place(wrap, c, 0, y)
			local icon = card.achievementID and ns.Provider.achievementIcon(card.achievementID)
			wrap.icon:SetTexture(icon)
			wrap.icon:SetShown(icon ~= nil)
			local height = ns.UI.SetRow(wrap.row, card, payload.profile.pinned, false)
			wrap:SetHeight(math.max(height, ICON))
			wrap:Show()
			y = y - wrap:GetHeight() - GAP
		else
			wrap.row.card = nil
			wrap:Hide()
		end
	end
	local opp = result and result["local"] and result["local"][1]
	if opp then
		local text = UI.AchievementName(opp.achievementID)
		if opp.missing then text = text .. " · " .. Text.missing(opp) end
		c.here:SetText(string.format(L["ui.here"], text))
		place(c.here, c, 0, y):Show()
	else
		c.here:Hide()
	end
end

local function layoutChars(c)
	local rows = Panel.CharacterRows(payload.profile, payload.currentKey, payload.states and payload.states.character == "confirmed", ns.Provider.build())
	local y = 0
	for i, line in ipairs(c.lines) do
		local row = rows[i]
		if row then
			local head = ns.UI.ColorName(row.key)
			if row.level then head = head .. "  " .. string.format(L["panel.char.level"], row.level) end
			local info = { L[row.state] .. " · " .. stamp(row.capturedAt) }
			if type(row.available) == "number" then info[#info + 1] = string.format(L["panel.char.points"], row.available) end
			line:SetText(head .. "\n" .. table.concat(info, " · "))
			place(line, c, 0, y):Show()
			y = y - line:GetStringHeight() - GAP
		else
			line:Hide()
		end
	end
	-- ponytail: no scrolling; characters beyond MAX_CHARS are only counted.
	if #rows > MAX_CHARS then
		c.more:SetText(string.format(L["ui.tooltip.more"], #rows - MAX_CHARS))
		place(c.more, c, 0, y):Show()
	else
		c.more:Hide()
	end
end

local function layoutSettings(c)
	local model, y = Panel.SettingsModel(payload.profile), 0
	for i, entry in ipairs(model) do
		local check = c.checks[i]
		check:SetChecked(entry.value)
		place(check, c, -4, y)
		y = y - 26
	end
	y = y - 4
	local locked = payload.profile.ui.tracker.locked ~= false
	c.lock:SetLabel(L[locked and "panel.set.unlock" or "panel.set.lock"])
	place(c.lock, c, 0, y)
	place(c.reset, c, 0, y - 24)
end

local LAYOUT = { plan = layoutPlan, chars = layoutChars, settings = layoutSettings }

-- Frame ----------------------------------------------------------------------------------------------

local function createPlan(c)
	c.status = Style.Font(c:CreateFontString(nil, "OVERLAY"), "sub", "warn")
	c.status:SetJustifyH("LEFT"); c.status:SetWidth(INNER)
	c.empty = Style.Font(c:CreateFontString(nil, "OVERLAY"), "sub", "sub")
	c.empty:SetJustifyH("LEFT"); c.empty:SetWidth(INNER)
	c.here = Style.Font(c:CreateFontString(nil, "OVERLAY"), "sub", "sub")
	c.here:SetJustifyH("LEFT"); c.here:SetWidth(INNER)
	c.rows = {}
	for i = 1, MAX_ROWS do
		local wrap = CreateFrame("Frame", nil, c)
		wrap:SetWidth(INNER)
		wrap.icon = wrap:CreateTexture(nil, "ARTWORK")
		wrap.icon:SetSize(ICON, ICON)
		wrap.icon:SetPoint("TOPLEFT")
		wrap.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		wrap.row = ns.UI.CreateRow(wrap, INNER - ICON - ICON_GAP)
		wrap.row:SetPoint("TOPLEFT", ICON + ICON_GAP, 0)
		c.rows[i] = wrap
	end
end

local function createChars(c)
	c.lines = {}
	for i = 1, MAX_CHARS do
		local line = Style.Font(c:CreateFontString(nil, "OVERLAY"), "sub", "text")
		line:SetJustifyH("LEFT"); line:SetWidth(INNER)
		c.lines[i] = line
	end
	c.more = Style.Font(c:CreateFontString(nil, "OVERLAY"), "sub", "sub")
	c.more:SetJustifyH("LEFT")
end

local function createSettings(c)
	c.checks = {}
	for i, key in ipairs(SETTING_KEYS) do
		local check = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
		check:SetSize(24, 24)
		check.label = Style.Font(check:CreateFontString(nil, "OVERLAY"), "row")
		check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
		check.label:SetText(L["panel.set." .. key])
		check:SetScript("OnClick", function(button)
			applySetting(key, button:GetChecked() and true or false)
			Panel.Refresh() -- a rejected change restores the box
		end)
		c.checks[i] = check
	end
	c.lock = Style.Button(c, L["panel.set.unlock"])
	c.lock:SetScript("OnClick", function()
		if not core then return end
		core:SetTrackerLocked(not (core.db.profile.ui.tracker.locked ~= false))
		core:RenderUI()
	end)
	c.reset = Style.Button(c, L["panel.set.reset"])
	c.reset:SetScript("OnClick", function() if core then core:ResetPositions() end end)
end

local CREATE = { plan = createPlan, chars = createChars, settings = createSettings }

local function createFrame()
	local f = CreateFrame("Frame", "LegacyNavigatorPanel", UIParent)
	f:SetSize(WIDTH, 400)
	f:SetClampedToScreen(true)
	f:EnableMouse(true) -- swallow clicks on the panel
	f:Hide()
	Style.Panel(f)
	f.title = Style.Font(f:CreateFontString(nil, "OVERLAY"), "title", "title")
	f.title:SetText(L["ui.title"])
	f.goal = Style.Font(f:CreateFontString(nil, "OVERLAY"), "goal", "accent")
	f.goal:SetJustifyH("LEFT"); f.goal:SetWidth(INNER)
	f.barBg = f:CreateTexture(nil, "ARTWORK")
	f.barBg:SetColorTexture(unpack(Style.color.button))
	f.barFill = f:CreateTexture(nil, "OVERLAY")
	f.progress = Style.Font(f:CreateFontString(nil, "OVERLAY"), "sub", "sub")
	f.progress:SetJustifyH("LEFT"); f.progress:SetWidth(INNER)
	f.change = Style.Button(f, L["panel.goal.change"])
	f.change:SetScript("OnClick", function(button) openGoalMenu(button) end)
	f.divider = Style.Divider(f)
	f.tabs, f.content = {}, {}
	for i, info in ipairs(TABS) do
		local button = Style.Button(f, L[info.key])
		button:SetScript("OnClick", function() tab = info.id; Panel.Refresh() end)
		f.tabs[i] = button
		local c = CreateFrame("Frame", nil, f)
		CREATE[info.id](c)
		c:Hide()
		f.content[info.id] = c
	end
	frame = f -- last: a failed construction leaves frame nil and retries next time
end

function Panel.Refresh()
	if not (frame and frame:IsShown() and payload) then return end
	local f, y = frame, -10
	place(f.title, f, PAD, y)
	y = y - 22
	f.goal:SetText(ns.UI.GoalText() or "")
	place(f.goal, f, PAD, y)
	y = y - f.goal:GetStringHeight() - 6

	local model = Panel.ProgressModel(payload.profile.goal, payload.result)
	if model.bar then
		local fraction = model.max > 0 and model.value / model.max or 0
		f.barBg:ClearAllPoints(); f.barBg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y); f.barBg:SetSize(INNER, 8); f.barBg:Show()
		f.barFill:ClearAllPoints(); f.barFill:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
		f.barFill:SetSize(math.max(INNER * fraction, 0.001), 8)
		f.barFill:SetColorTexture(Style.AccentColor()) -- never cached; read on every refresh
		f.barFill:Show()
		y = y - 8 - 4
	else
		f.barBg:Hide(); f.barFill:Hide()
	end
	if model.text ~= "" then
		f.progress:SetText(model.text)
		place(f.progress, f, PAD, y):Show()
		y = y - f.progress:GetStringHeight() - 6
	else
		f.progress:Hide()
	end
	place(f.change, f, PAD, y)
	y = y - 20 - GAP

	local visible = {}
	for i, info in ipairs(TABS) do if hasContent(info.id) then visible[#visible + 1] = i end end
	local selected
	for _, i in ipairs(visible) do if TABS[i].id == tab then selected = i end end
	selected = selected or visible[1]
	local x = PAD
	for i, button in ipairs(f.tabs) do
		local on = false
		for _, v in ipairs(visible) do if v == i then on = true end end
		if on then
			place(button, f, x, y):Show()
			button:SetAlpha(i == selected and 1 or 0.55)
			x = x + button:GetWidth() + 4
		else
			button:Hide()
		end
	end
	y = y - 20 - GAP
	f.divider:ClearAllPoints()
	f.divider:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y); f.divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
	y = y - 1 - GAP
	for i, info in ipairs(TABS) do
		local c = f.content[info.id]
		if i == selected then
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y); c:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
			c:Show()
			LAYOUT[info.id](c)
		else
			c:Hide()
		end
	end
end

-- Docking --------------------------------------------------------------------------------------------

-- Panel to the right of the host (past its side tabs, which hang right of it); left of the host if that would leave
-- the screen. Positions are plain anchors to the host: it moves, we follow, nothing is written to it.
local function dock(h)
	local ratio = h:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local tabs = h.LegacyRewardTrackTab
	local tabWidth = tabs and tabs.GetWidth and tabs:GetWidth() or 0
	local right = h:GetRight()
	local side = right and Panel.DockSide(right * ratio, tabWidth * ratio, WIDTH, UIParent:GetRight()) or "right"
	frame:ClearAllPoints()
	if side == "right" then frame:SetPoint("TOPLEFT", h, "TOPRIGHT", GAP_HOST + tabWidth, 0)
	else frame:SetPoint("TOPRIGHT", h, "TOPLEFT", -GAP_HOST, 0) end
	frame:SetHeight(h:GetHeight() * ratio)
	frame:SetFrameStrata(h:GetFrameStrata())
end

-- Show/hide follows the host. Blizzard fires no callback on LegacySystemFrame show (its OnShow only plays a sound and
-- refreshes currency; checked in the forever UI source), so we poll IsShown on our own frame, only once the host exists.
-- ponytail: a 0.25 s poll on a tiny frame; swap for an EventRegistry callback if Blizzard ever adds a show event.
function Panel.Sync()
	local h = host()
	if not (core and h) then return end
	local want = h:IsShown() == true
	if want then
		if not frame then createFrame() end
		if not frame:IsShown() then
			dock(h)
			frame:Show()
			if payload then Panel.Refresh() else core:RenderUI() end
		end
	elseif frame and frame:IsShown() then
		frame:Hide()
	end
end

local function watch()
	if not driver or driver.watching or not host() then return end
	driver.watching = true
	local elapsed = 0
	driver:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < POLL then return end
		elapsed = 0
		local ok, err = pcall(Panel.Sync)
		if not ok and core then core:CallUI(error, err) end
	end)
	Panel.Sync()
end

-- Blizzard options page: a short text and a button that opens the Legacy window (where the panel lives).
local function registerOptions()
	local canvas = CreateFrame("Frame")
	canvas.name = L["ui.title"]
	local text = Style.Font(canvas:CreateFontString(nil, "OVERLAY"), "row")
	text:SetPoint("TOPLEFT", 16, -16); text:SetWidth(560); text:SetJustifyH("LEFT")
	text:SetText(L["panel.options.text"])
	local open = Style.Button(canvas, L["panel.options.open"])
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
	open:SetScript("OnClick", function() if core then core:OpenLegacyWindow() end end)
	canvas.OnCommit, canvas.OnDefault, canvas.OnRefresh = function() end, function() end, function() end
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(canvas, canvas.name))
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(canvas)
	end
end

function Panel.Render(data)
	payload = data
	if frame and frame:IsShown() then Panel.Refresh() end
end

function Panel.Init(coreObject)
	core = coreObject
	pcall(registerOptions) -- the panel works without an options page
	driver = CreateFrame("Frame")
	driver:RegisterEvent("ADDON_LOADED")
	driver:SetScript("OnEvent", function(_, _, name) if name == HOST_ADDON then watch() end end)
	watch() -- the host may already be loaded
end
