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
eq(de.contribution(card()), "+1 Punkt bei Abschluss")
eq(en.contribution(card()), "+1 point on completion")
eq(de.contribution(with({ kind = "criteria", n = 1, ctype = "boss" })), "+1 Punkt", "exactly one open sub-goal")
eq(de.contribution(with({ kind = "level", n = 1 })), "+1 Punkt bei Abschluss", "only criteria count as sub-goals")
eq(de.contribution(card({ contribution = "progress" }), "Explore Durotar"), "Fortschritt für Explore Durotar")
eq(en.contribution(card({ contribution = "progress", name = "Explore Durotar" })), "progress for Explore Durotar")

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
for _, name in ipairs({ "UI.lua", "Tracker.lua" }) do local f2 = assert(io.open(name)); ui = ui .. f2:read("*a"); f2:close() end
for key in ui:gmatch('L%["([^"]-)"%]') do
	if loc.enUS[key] == nil or loc.deDE[key] == nil then error("UI uses text missing in enUS/deDE: " .. key) end
end
for _, key in ipairs({ "ui.pin", "ui.pinnedBtn", "ui.here", "ui.legacy", "legacy.combat", "legacy.error", "tracker.header", "tracker.here", "tracker.done", "tracker.next" }) do
	if loc.enUS[key] == nil or loc.deDE[key] == nil then error("UI button key " .. key) end
end
-- dynamically built keys in Core ("plan.reason." .. x, L[self.states[domain]]) are covered by these lists
for _, key in ipairs({ "account", "character", "catalogue", "treesMissing", "needInvalid", "needAbove", "challengeUnknown",
	"challengeUnrated", "challengeDisabled", "needImpossible", "nodeRanks", "points", "renown", "nodeUnknown", "nodeOwned",
	"goalType", "noStep", "noStepOnCurrent" }) do
	if loc.enUS["plan.reason." .. key] == nil or loc.deDE["plan.reason." .. key] == nil then error("reason key " .. key) end
end

print("text_spec: all checks passed")
