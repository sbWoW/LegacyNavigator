-- Run from the addon folder: lua tests/text_spec.lua
local function eq(actual, expected, message)
	if actual ~= expected then
		error((message or "mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local function load(locale)
	GetLocale = function() return locale end
	local ns = {}
	assert(loadfile("Definitions.lua"))("LegacyNavigator", ns)
	assert(loadfile("Locale.lua"))("LegacyNavigator", ns)
	return ns
end

local en, de = load("enUS").Text, load("deDE").Text
local function card(o)
	local c = { achievementID = 1, charKey = "Some Realm-Alpha", contribution = "point", dataState = "confirmed",
		missing = { kind = "criteria", n = 6, ctype = "boss" }, why = { "goal", "currentChar" } }
	for k, v in pairs(o or {}) do c[k] = v end
	return c
end
local function with(missing, o) o = o or {}; o.missing = missing; return card(o) end

-- missing: wording per kind / ctype
eq(en.missing(with({ kind = "criteria", n = 6, ctype = "boss" })), "6 bosses open")
eq(de.missing(with({ kind = "criteria", n = 6, ctype = "boss" })), "6 Bosse offen")
eq(de.missing(with({ kind = "criteria", n = 3, ctype = "area" })), "3 Gebiete offen")
eq(de.missing(with({ kind = "criteria", n = 4, ctype = "other" })), "4 Teilziele offen")
eq(de.missing(with({ kind = "criteria", n = 4 })), "4 Teilziele offen", "no ctype")
eq(de.missing(with({ kind = "level", n = 24 })), "24 Stufen fehlen")
eq(en.missing(with({ kind = "level", n = 24 })), "24 levels missing")
eq(de.missing(with({ kind = "skill", n = 130 })), "130 Punkte Fertigkeit fehlen")
eq(de.missing(with({ kind = "criteria", n = 1, ctype = "boss" })), "1 Boss offen")
eq(de.missing(with({ kind = "level", n = 1 })), "1 Stufe fehlt")

-- contribution
eq(de.contribution(card()), "", "point: no row segment (D28)")
eq(de.pointNote(card()), "+1 Legacy-Punkt bei Abschluss")
eq(en.pointNote(card()), "+1 Legacy point on completion")
eq(de.pointNote(with({ kind = "criteria", n = 1, ctype = "boss" })), "Letzter Schritt: +1 Legacy-Punkt", "exactly one open sub-goal")
eq(en.pointNote(with({ kind = "criteria", n = 1, ctype = "boss" })), "Last step: +1 Legacy point")
eq(de.pointNote(with({ kind = "level", n = 1 })), "+1 Legacy-Punkt bei Abschluss", "only criteria count as sub-goals")
eq(de.pointNote(card({ contribution = "progress" })), "")
eq(de.contribution(card({ contribution = "progress" }), "Explore Durotar"), "Fortschritt für Explore Durotar")
eq(en.contribution(card({ contribution = "progress", name = "Explore Durotar" })), "progress for Explore Durotar")

-- goal block (D28)
eq(de.goalLine(nil), "Kein Ziel – beste nächste Schritte"); eq(en.goalLine(nil), "No goal – best next steps")
eq(de.goalLine({ type = "points", need = 5 }), "Ziel: 5 Punkte ausgeben"); eq(en.goalLine({ type = "points", need = 5 }), "Goal: spend 5 points")
eq(de.goalLine({ type = "renown", level = 7 }), "Ziel: Renown-Stufe 7"); eq(en.goalLine({ type = "renown", level = 7 }), "Goal: renown level 7")
eq(en.goalLine({ type = "node" }, "Working Overtime"), "Goal: Working Overtime"); eq(de.goalLine({ type = "challenge" }, "X"), "Ziel: X")
local node = { type = "node" }
eq(de.goalSub(node, { status = "ok", goal = { remaining = 1 } }), "1 Punkt fehlt · Voraussetzungen ungeprüft")
eq(de.goalSub(node, { status = "ok", goal = { remaining = 3 } }), "3 Punkte fehlen · Voraussetzungen ungeprüft")
eq(en.goalSub(node, { status = "ok", goal = { remaining = 1 } }), "1 point missing · prerequisites unchecked")
eq(de.goalSub({ type = "renown" }, { status = "ok", goal = { remaining = 2 } }), "2 Stufen fehlen")
eq(de.goalSub(node, { status = "reachable", goal = {} }), "erreichbar – zum Legacy-Fenster · Voraussetzungen ungeprüft")
eq(de.goalSub({ type = "points" }, { status = "reachable", goal = {} }), "erreichbar – zum Legacy-Fenster")
eq(de.goalSub({ type = "challenge" }, { status = "ok", goal = {} }), ""); eq(de.goalSub(nil, {}), "")

-- data: confirmed says nothing, stale carries the date (2026-10-04 12:00 UTC is the 4th in any timezone)
local t = 1791115200
eq(de.data(card(), 0), ""); eq(en.data(card(), 0), "")
eq(de.data(card({ dataState = "stale", capturedAt = t }), t), "Stand 2026-10-04")
eq(en.data(card({ dataState = "stale", capturedAt = t }), t), "as of 2026-10-04")
eq(de.data(card({ dataState = "stale" }), t), "Stand unbekannt")

-- why / name
local why = de.why(card({ why = { "goal", "switch", "groupRequired" } }))
eq(#why, 3); eq(why[1], "dient dem Ziel"); eq(why[2], "Charakterwechsel"); eq(why[3], "Gruppe nötig")
eq(#en.why(card({ why = {} })), 0)
eq(de.name("Some Realm-Alpha"), "Alpha"); eq(de.name("Alpha"), "Alpha"); eq(de.name("Black-Realm-Alpha"), "Alpha")

eq(load("deDE").Locale.deDE["ui.here"], "Hier: %s")

-- every enUS key exists in deDE (and the reverse for plan.*); keys Core uses exist where they must
local loc = load("deDE").Locale
for key in pairs(loc.enUS) do
	if loc.deDE[key] == nil then error("deDE misses key " .. key) end
end
for key in pairs(loc.deDE) do
	if key:find("^plan%.") and loc.enUS[key] == nil then error("enUS misses key " .. key) end
end
local f = assert(io.open("Core.lua")); local src = f:read("*a"); f:close()
for key in src:gmatch('L%["([^"]-)"%]') do
	if key:find("^plan%.") then
		if loc.enUS[key] == nil then error("Core uses plan key missing in enUS: " .. key) end
		if loc.deDE[key] == nil then error("Core uses plan key missing in deDE: " .. key) end
	elseif loc.deDE[key] == nil then
		error("Core uses text without deDE entry: " .. key)
	end
end
local ui = ""
for _, name in ipairs({ "UI.lua", "Tracker.lua", "Panel.lua", "Hooks.lua" }) do local f2 = assert(io.open(name)); ui = ui .. f2:read("*a"); f2:close() end
for key in ui:gmatch('L%["([^"]-)"%]') do
	if loc.enUS[key] == nil or loc.deDE[key] == nil then error("UI uses text missing in enUS/deDE: " .. key) end
end
for _, key in ipairs({ "ui.pin", "ui.pinnedBtn", "ui.here", "ui.legacy", "legacy.combat", "legacy.error", "tracker.header", "tracker.here", "tracker.done", "tracker.next", "tracker.unlocked", "panel.set.alpha", "hooks.node", "hooks.goalSet", "hooks.hint.goal", "tree.1187", "tree.1188", "tree.1189" }) do
	if loc.enUS[key] == nil or loc.deDE[key] == nil then error("UI button key " .. key) end
end
-- Panel.lua builds some keys dynamically ("panel.set." .. key, tabs from a table)
for _, key in ipairs({ "dungeon", "raid", "pvp", "switch", "tracker", "minimap" }) do
	if loc.enUS["panel.set." .. key] == nil or loc.deDE["panel.set." .. key] == nil then error("panel.set key " .. key) end
end
for _, key in ipairs({ "panel.tab.plan", "panel.tab.chars", "panel.tab.settings", "panel.menu.none", "panel.menu.points", "panel.menu.renown",
	"panel.menu.challenge", "panel.menu.node", "panel.set.lock", "panel.set.unlock", "panel.set.reset", "panel.goal.change", "panel.goal.clear" }) do
	if loc.enUS[key] == nil or loc.deDE[key] == nil then error("panel key " .. key) end
end
-- dynamically built keys in Core ("plan.reason." .. x, L[self.states[domain]]) are covered by these lists
for _, key in ipairs({ "account", "character", "catalogue", "treesMissing", "needInvalid", "needAbove", "challengeUnknown",
	"challengeUnrated", "challengeDisabled", "challengeCompleted", "needImpossible", "nodeRanks", "points", "renown", "nodeUnknown", "nodeOwned",
	"goalType", "noStep", "noStepOnCurrent" }) do
	if loc.enUS["plan.reason." .. key] == nil or loc.deDE["plan.reason." .. key] == nil then error("reason key " .. key) end
end

-- ProgressFor (D30)
local pf = en.ProgressFor
eq(pf(with({ kind = "level", n = 24, total = 25 })).text, "1/25", "level")
eq(pf(with({ kind = "criteria", n = 6, total = 6, ctype = "boss" })).text, "0/6", "criteria")
eq(pf(with({ kind = "criteria", n = 545, total = 549, ctype = "area" })).text, "4/549", "explorer chain")
eq(pf(with({ kind = "criteria", n = 545, total = 549 })).done, 4)
eq(pf(with({ kind = "level", n = 3 })), nil, "no total")
eq(pf(with({ kind = "level", n = 3, total = 0 })), nil, "total 0")
eq(pf(card({ missing = false })), nil, "no missing")
eq(pf({ status = "done" }), nil); eq(pf({ status = "unknown" }), nil); eq(pf(nil), nil)
eq(pf(with({ kind = "level", n = 30, total = 25 })).done, 0, "clamped")

-- player-facing text must not carry internal dev wording
local forbidden = { -- { pattern, caseInsensitive }
	{ "etappe", true }, { "stage %d", true }, { "phase %d", true }, { "mvp", true }, { "ponytail", true },
	{ "architecture", true }, { "ledger", true }, { "todo", true }, { "fixme", true },
	{ "milestone 0", true }, { "meilenstein", true },
	{ "%f[%w]D%d%d?%f[%W]", false }, { "%f[%w]R%d%f[%W]", false }, { "%f[%w]O%d%f[%W]", false }, { "%f[%w]V%d%f[%W]", false },
}
local offenders = {}
local function scan(where, text)
	if type(text) ~= "string" then return end
	for _, rule in ipairs(forbidden) do
		local hit = (rule[2] and text:lower() or text):find(rule[1])
		if hit then offenders[#offenders + 1] = where .. ": /" .. rule[1] .. "/ in \"" .. text .. "\"" end
	end
end
local toc = assert(io.open("LegacyNavigator.toc"))
for line in toc:lines() do
	local k, v = line:match("^## (Title[%w%-]*):%s*(.*)$")
	if not k then k, v = line:match("^## (Notes[%w%-]*):%s*(.*)$") end
	if k then scan("toc " .. k, v) end
end
toc:close()
for k, v in pairs(loc.enUS) do scan("enUS key " .. tostring(k), k); scan("enUS[" .. tostring(k) .. "]", v) end
for k, v in pairs(loc.deDE) do scan("deDE[" .. tostring(k) .. "]", v) end
for _, name in ipairs({ "Core.lua", "UI.lua", "Panel.lua", "Tracker.lua", "Hooks.lua" }) do
	local h = assert(io.open(name)); local code = h:read("*a"); h:close()
	for args in code:gmatch(":Print%((.-)%)") do
		for lit in args:gmatch('"([^"]*)"') do scan(name .. " Print", lit) end
	end
end
if #offenders > 0 then error("internal wording reaches players:\n  " .. table.concat(offenders, "\n  "), 0) end

print("text_spec: all checks passed")
