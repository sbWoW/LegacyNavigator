local _, ns = ...

-- Status strings only (Etappe 1). Keys are the enUS text.
local deDE = {
	["Legacy Navigator status (build %s)"] = "Legacy Navigator Status (Build %s)",
	["Domains:"] = "Domänen:",
	["Catalogue: %d achievements, %d with points"] = "Katalog: %d Achievements, davon %d mit Punkten",
	["Activities: %s"] = "Aktivitäten: %s",
	["Trees read: %d/%d"] = "Bäume gelesen: %d/%d",
	["Known characters:"] = "Bekannte Charaktere:",
	["  none"] = "  keine",
	["  %s: %s, %s, build %s%s"] = "  %s: %s, %s, Build %s%s",
	[" (other build)"] = " (anderer Build)",
	["unknown"] = "unbekannt", ["loading"] = "lädt", ["confirmed"] = "bestätigt", ["stale"] = "veraltet",
	["never"] = "nie",
	["Data not ready yet. Try /lnav refresh."] = "Daten noch nicht bereit. /lnav refresh versuchen.",
	["Scan incomplete, snapshot not saved: %s"] = "Scan unvollständig, Stand nicht gespeichert: %s",
	["Refresh started."] = "Aktualisierung gestartet.",
	["Use /lnav status, /lnav refresh or /lnav diag."] = "Nutze /lnav status, /lnav refresh oder /lnav diag.",
}

local L = {}
if GetLocale and GetLocale() == "deDE" then L = deDE end
ns.L = setmetatable({}, { __index = function(_, key) return L[key] or key end })
