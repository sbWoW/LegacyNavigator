local _, ns = ...

-- Flat look for our own frames. Plain textures only, game font objects as default.
-- With EllesmereUI loaded its RegisterSkin API paints the frames instead (primitives only; nothing copied).
local Style = {}
ns.Style = Style

Style.pad, Style.gap = 12, 8
Style.color = {
	panel = { 0.05, 0.07, 0.09, 0.92 }, border = { 1, 1, 1, 0.14 }, accent = { 0.05, 0.82, 0.62 },
	title = { 0.62, 0.66, 0.70 }, text = { 0.93, 0.95, 0.97 }, sub = { 0.64, 0.68, 0.72 }, warn = { 0.96, 0.74, 0.30 },
	button = { 0.13, 0.16, 0.20, 1 }, hover = { 1, 1, 1, 0.10 },
}
Style.fonts = { title = "GameFontNormalSmall", goal = "GameFontHighlightLarge", row = "GameFontHighlight", sub = "GameFontHighlightSmall" }

local C = Style.color
local skin -- the S handed over by EllesmereUI.RegisterSkin; kept for frames created later
local objects, accents, bars = {}, {}, {}

local function rgba(t, a) return t[1], t[2], t[3], a or t[4] or 1 end

local function apply(kind, obj)
	if not skin then return end
	if kind == "panel" then
		for _, tex in ipairs(obj._lnTextures) do tex:Hide() end
		skin.Panel(obj)
	elseif kind == "button" then
		obj._lnBg:Hide()
		if obj._lnHover then obj._lnHover:Hide() end
		skin.Button(obj)
	elseif kind == "font" then
		skin.Font(obj)
	end
end

local function track(kind, obj)
	objects[#objects + 1] = { kind, obj }
	apply(kind, obj)
end

function Style.AccentColor()
	if skin and skin.GetAccentColor then return skin.GetAccentColor() end -- never cached (SKINNING_API.md)
	return rgba(C.accent)
end

local function recolorAccents()
	for _, fs in ipairs(accents) do fs:SetTextColor(Style.AccentColor()) end
	for _, bar in ipairs(bars) do bar:SetStatusBarColor(Style.AccentColor()) end
end

-- role: key of Style.fonts; color: key of Style.color (default text). "accent" follows the Ellesmere accent.
function Style.Font(fs, role, color)
	fs:SetFontObject(Style.fonts[role])
	if color == "accent" then
		accents[#accents + 1] = fs
		fs:SetTextColor(Style.AccentColor())
	else
		fs:SetTextColor(rgba(C[color or "text"]))
	end
	track("font", fs)
	return fs
end

local function edge(frame, point1, point2, w, h)
	local tex = frame:CreateTexture(nil, "BORDER")
	tex:SetColorTexture(rgba(C.border))
	tex:SetPoint(point1); tex:SetPoint(point2)
	if w then tex:SetWidth(w) else tex:SetHeight(h) end
	return tex
end

function Style.Panel(frame)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(); bg:SetColorTexture(rgba(C.panel))
	frame._lnTextures = {
		bg, edge(frame, "TOPLEFT", "TOPRIGHT", nil, 1), edge(frame, "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1),
		edge(frame, "TOPLEFT", "BOTTOMLEFT", 1), edge(frame, "TOPRIGHT", "BOTTOMRIGHT", 1),
	}
	track("panel", frame)
	return frame
end

-- Backdrop opacity of a Style.Panel frame. Own look: the bg colour with alpha a. Skinned: the skin keeps its bg
-- texture in private state (nothing on the frame to reach) and fades our own textures, so the only lever is
-- frame:SetAlpha. That also dims the skin border, and the frame must hold no content: call this on a pure
-- background frame.
function Style.SetPanelAlpha(frame, a)
	if not skin then
		frame._lnTextures[1]:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], a)
		return
	end
	frame:SetAlpha(a)
end

function Style.Divider(parent)
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetColorTexture(rgba(C.border)); tex:SetHeight(1)
	return tex
end

-- flat 3-px bar (accent fill on a dim track, follows the Ellesmere accent) with "done/total" at its right end.
-- bar:Set(progress) shows it (progress = Text.ProgressFor result, or true-full via full) or hides it for nil.
function Style.ProgressBar(parent, width)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, 10)
	f.label = Style.Font(f:CreateFontString(nil, "OVERLAY"), "sub", "sub")
	f.label:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.bar = CreateFrame("StatusBar", nil, f)
	f.bar:SetHeight(3)
	f.bar:SetPoint("LEFT", f, "LEFT", 0, 0); f.bar:SetPoint("RIGHT", f.label, "LEFT", -4, 0)
	f.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	f.track = f.bar:CreateTexture(nil, "BACKGROUND")
	f.track:SetAllPoints(); f.track:SetColorTexture(1, 1, 1, 0.12)
	f.bar:SetStatusBarColor(Style.AccentColor())
	bars[#bars + 1] = f.bar
	function f:Set(progress, full)
		if not progress then self:Hide(); return end
		self.bar:SetMinMaxValues(0, progress.total)
		self.bar:SetValue(full and progress.total or progress.done)
		self.label:SetText(full and (progress.total .. "/" .. progress.total) or progress.text)
		self:Show()
	end
	return f
end

-- Small flat button; width follows the label.
function Style.Button(parent, text)
	local button = CreateFrame("Button", nil, parent)
	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(); bg:SetColorTexture(rgba(C.button))
	button._lnBg = bg
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(); hover:SetColorTexture(rgba(C.hover))
	button._lnHover = hover
	button.label = button:CreateFontString(nil, "OVERLAY")
	button.label:SetPoint("CENTER")
	Style.Font(button.label, "sub")
	function button:SetLabel(value)
		self.label:SetText(value)
		self:SetSize(math.max(56, self.label:GetStringWidth() + 16), 20)
	end
	button:SetLabel(text or "")
	track("button", button)
	return button
end

if EllesmereUI and EllesmereUI.RegisterSkin then
	pcall(EllesmereUI.RegisterSkin, "LegacyNavigator", function(S)
		skin = S
		for _, item in ipairs(objects) do pcall(apply, item[1], item[2]) end
		if S.OnLooksChanged then S.OnLooksChanged(recolorAccents) end
		recolorAccents()
	end)
end
