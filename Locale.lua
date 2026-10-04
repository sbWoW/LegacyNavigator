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
	["Use /lnav (overlay), /lnav status, /lnav refresh, /lnav plan, /lnav goal, /lnav set, /lnav unlock, /lnav lock, /lnav reset or /lnav diag."] = "Nutze /lnav (Overlay), /lnav status, /lnav refresh, /lnav plan, /lnav goal, /lnav set, /lnav unlock, /lnav lock, /lnav reset oder /lnav diag.",
	["Incomplete scans logged: %d (newest last; /lnav status log shows all)"] = "Unvollständige Scans protokolliert: %d (neueste zuletzt; /lnav status log zeigt alle)",
	["  %s build %s: %s"] = "  %s Build %s: %s",
	["Tracker locked."] = "Tracker gesperrt.", ["Tracker unlocked."] = "Tracker entsperrt.", ["Positions reset."] = "Positionen zurückgesetzt.",
	-- overlay (Etappe 3)
	["ui.title"] = "Legacy Navigator", ["ui.binding"] = "Legacy Navigator ein/aus",
	["ui.goal.none"] = "Ziel: keine - beste nächste Schritte (/lnav goal zum Setzen)",
	["ui.goal.points"] = "Ziel: %d Punkte", ["ui.goal.renown"] = "Ziel: Ansehen Stufe %d",
	["ui.goal.node"] = "Ziel: Vorteil %d", ["ui.goal.nodeNeed"] = "Ziel: Vorteil %d, Mindestbedarf %d Punkte (ungeprüft)",
	["ui.goal.challenge"] = "Ziel: %s", ["ui.goal.missing"] = " - %d fehlen", ["ui.goal.reachable"] = " - erreichbar",
	["ui.goal.invalid"] = "Ziel ungültig: %s - /lnav goal clear",
	["ui.pinned"] = "Angeheftet: %s", ["ui.pinned.done"] = "Angeheftet: %s - erledigt!",
	["ui.pin"] = "Anheften", ["ui.pinnedBtn"] = "Angeheftet", ["ui.unpin"] = "Lösen",
	["ui.status.loading"] = "Daten werden geladen ...", ["ui.status.loadingKept"] = "Daten werden geladen - letzter Stand vom %s",
	["ui.status.planError"] = "Planer-Fehler - letzter gültiger Stand",
	["ui.status.combat"] = "Aktualisierung nach dem Kampf", ["ui.status.incomplete"] = "Scan unvollständig - Details: /lnav status",
	["ui.empty"] = "Keine passende Empfehlung mit den aktuellen Einstellungen", ["ui.empty.hint"] = "Versuche: /lnav set dungeon on, /lnav set raid on oder /lnav set switch on",
	["ui.tooltip.why"] = "Warum", ["ui.tooltip.open"] = "Offene Teilziele", ["ui.tooltip.more"] = "+ %d weitere",
	["ui.minimap.hint"] = "Linksklick: Overlay ein/aus", ["ui.here"] = "Hier: %s",
	-- planner output (Etappe 2)
	["plan.header.none"] = "Plan (Orientierung, kein Ziel)",
	["plan.header.points"] = "Plan - Ziel: %d Punkte",
	["plan.header.node"] = "Plan - Ziel: Vorteil %d (Mindestbedarf, ungeprüft): %d Punkte",
	["plan.header.challenge"] = "Plan - Ziel: Herausforderung %d",
	["plan.header.renown"] = "Plan - Ziel: Ansehen Stufe %d (%d Punkte fehlen)",
	["plan.reason.renown"] = "Ansehen noch nicht gelesen",
	["plan.goal.remaining"] = "  Es fehlen %d Punkte, verfügbar: %d",
	["plan.status.loading"] = "Daten werden noch geladen, keine Empfehlung.",
	["plan.status.invalid"] = "Ziel ungültig:",
	["plan.status.none"] = "Kein bestätigter Schritt gefunden:",
	["plan.status.reachable"] = "Ziel ist bereits erreichbar.",
	["plan.reason.account"] = "Accountdaten fehlen",
	["plan.reason.character"] = "Charakterdaten fehlen",
	["plan.reason.catalogue"] = "Katalog noch nicht gelesen",
	["plan.reason.treesMissing"] = "Vorteilsbäume noch nicht gelesen",
	["plan.reason.needInvalid"] = "Punktebedarf muss eine ganze Zahl >= 1 sein",
	["plan.reason.needAbove"] = "Punktebedarf über der Grenze von %d",
	["plan.reason.challengeUnknown"] = "Herausforderung nicht im Katalog",
	["plan.reason.challengeUnrated"] = "Herausforderung nicht bewertet",
	["plan.reason.challengeDisabled"] = "Aktivität der Herausforderung ist ausgeschaltet",
	["plan.reason.needImpossible"] = "Bedarf ist mit den restlichen Legacy-Punkten nicht erreichbar",
	["plan.reason.nodeRanks"] = "Ränge außerhalb des gültigen Bereichs",
	["plan.reason.points"] = "Punktestand noch nicht gelesen",
	["plan.header.nodeUnknown"] = "Plan - Ziel: Vorteil %d (Bedarf unbekannt)",
	["plan.reason.nodeUnknown"] = "Vorteilsknoten unbekannt",
	["plan.reason.nodeOwned"] = "Vorteil bereits erworben",
	["plan.reason.goalType"] = "unbekannter Zieltyp",
	["plan.reason.noStep"] = "Keine passende Aufgabe mit bekanntem Restbedarf",
	["plan.reason.noStepOnCurrent"] = "Auf diesem Charakter gibt es keinen bekannten Schritt; Twink als Alternative",
	["plan.card.spend"] = "Zum Legacy-Fenster und Punkte ausgeben (%d verfügbar)",
	["plan.card.chooseGoal"] = "Ziel erreicht - neues Ziel wählen (/lnav goal)",
	["plan.card.line"] = "%d. %s (%s): %s",
	["plan.card.alt"] = "   Alternative: %s (%s): %s",
	["plan.card.local"] = "  Hier: %s (%s)",
	["plan.contribution.point"] = "+1 Punkt bei Abschluss",
	["plan.contribution.pointLast"] = "+1 Punkt",
	["plan.contribution.progress"] = "Fortschritt für %s",
	["plan.missing.level"] = "%d Stufen fehlen", ["plan.missing.level.one"] = "%d Stufe fehlt",
	["plan.missing.skill"] = "%d Punkte Fertigkeit fehlen", ["plan.missing.skill.one"] = "%d Punkt Fertigkeit fehlt",
	["plan.missing.boss"] = "%d Bosse offen", ["plan.missing.boss.one"] = "%d Boss offen",
	["plan.missing.area"] = "%d Gebiete offen", ["plan.missing.area.one"] = "%d Gebiet offen",
	["plan.missing.other"] = "%d Teilziele offen", ["plan.missing.other.one"] = "%d Teilziel offen",
	["plan.why.goal"] = "dient dem Ziel",
	["plan.why.currentChar"] = "aktueller Charakter",
	["plan.why.switch"] = "Charakterwechsel",
	["plan.why.soloNoPrep"] = "solo, ohne Vorbereitung",
	["plan.why.groupRequired"] = "Gruppe nötig",
	["plan.why.reachable"] = "Ziel erreichbar",
	["plan.why.alternative"] = "Alternative",
	["plan.data.stale"] = "Stand %s",
	["plan.data.staleUnknown"] = "Stand unbekannt",
	["plan.unnamed"] = "Aufgabe %d",
	["Goal set."] = "Ziel gesetzt.",
	["Goal cleared."] = "Ziel gelöscht.",
	["Usage: /lnav goal points N | renown N | challenge ID | node ID [ranks] | clear"] = "Aufruf: /lnav goal points N | renown N | challenge ID | node ID [Ränge] | clear",
	["Usage: /lnav set pvp|dungeon|raid|switch on|off"] = "Aufruf: /lnav set pvp|dungeon|raid|switch on|off",
	["Setting %s: %s"] = "Einstellung %s: %s",
	["on"] = "an", ["off"] = "aus",
	["Planner error: %s"] = "Planer-Fehler: %s",
}

local enUS = {
	["plan.header.none"] = "Plan (orientation, no goal)",
	["plan.header.points"] = "Plan - goal: %d points",
	["plan.header.node"] = "Plan - goal: advantage %d (minimum need, unchecked): %d points",
	["plan.header.challenge"] = "Plan - goal: challenge %d",
	["plan.header.renown"] = "Plan - goal: renown level %d (%d points to go)",
	["plan.reason.renown"] = "renown not read yet",
	["plan.goal.remaining"] = "  %d points missing, available: %d",
	["plan.status.loading"] = "Data still loading, no recommendation.",
	["plan.status.invalid"] = "Goal invalid:",
	["plan.status.none"] = "No confirmed step found:",
	["plan.status.reachable"] = "Goal is already reachable.",
	["plan.reason.account"] = "account data missing",
	["plan.reason.character"] = "character data missing",
	["plan.reason.catalogue"] = "catalogue not read yet",
	["plan.reason.treesMissing"] = "advantage trees not read yet",
	["plan.reason.needInvalid"] = "point need must be a whole number >= 1",
	["plan.reason.needAbove"] = "point need above the limit of %d",
	["plan.reason.challengeUnknown"] = "challenge not in catalogue",
	["plan.reason.challengeUnrated"] = "challenge is not rated",
	["plan.reason.challengeDisabled"] = "the challenge's activity is switched off",
	["plan.reason.needImpossible"] = "need cannot be reached with the remaining Legacy points",
	["plan.reason.nodeRanks"] = "ranks outside the valid range",
	["plan.reason.points"] = "point balance not read yet",
	["plan.header.nodeUnknown"] = "Plan - goal: advantage %d (need unknown)",
	["plan.reason.nodeUnknown"] = "advantage node unknown",
	["plan.reason.nodeOwned"] = "advantage already owned",
	["plan.reason.goalType"] = "unknown goal type",
	["plan.reason.noStep"] = "no suitable task with a known remaining need",
	["plan.reason.noStepOnCurrent"] = "no known step on this character; a twink is offered instead",
	["plan.card.spend"] = "Open the Legacy window and spend points (%d available)",
	["plan.card.chooseGoal"] = "Goal reached - pick a new goal (/lnav goal)",
	["plan.card.line"] = "%d. %s (%s): %s",
	["plan.card.alt"] = "   Alternative: %s (%s): %s",
	["plan.card.local"] = "  Here: %s (%s)",
	["plan.contribution.point"] = "+1 point on completion",
	["plan.contribution.pointLast"] = "+1 point",
	["plan.contribution.progress"] = "progress for %s",
	["plan.missing.level"] = "%d levels missing", ["plan.missing.level.one"] = "%d level missing",
	["plan.missing.skill"] = "%d skill points missing", ["plan.missing.skill.one"] = "%d skill point missing",
	["plan.missing.boss"] = "%d bosses open", ["plan.missing.boss.one"] = "%d boss open",
	["plan.missing.area"] = "%d areas open", ["plan.missing.area.one"] = "%d area open",
	["plan.missing.other"] = "%d sub-goals open", ["plan.missing.other.one"] = "%d sub-goal open",
	["plan.why.goal"] = "serves the goal",
	["plan.why.currentChar"] = "current character",
	["plan.why.switch"] = "character switch",
	["plan.why.soloNoPrep"] = "solo, no preparation",
	["plan.why.groupRequired"] = "group needed",
	["plan.why.reachable"] = "goal reachable",
	["plan.why.alternative"] = "alternative",
	["plan.data.stale"] = "as of %s",
	["plan.data.staleUnknown"] = "as of unknown date",
	["plan.unnamed"] = "Task %d",
	["Use /lnav (overlay), /lnav status, /lnav refresh, /lnav plan, /lnav goal, /lnav set, /lnav unlock, /lnav lock, /lnav reset or /lnav diag."] = "Use /lnav (overlay), /lnav status, /lnav refresh, /lnav plan, /lnav goal, /lnav set, /lnav unlock, /lnav lock, /lnav reset or /lnav diag.",
	["ui.title"] = "Legacy Navigator", ["ui.binding"] = "Toggle Legacy Navigator",
	["ui.goal.none"] = "Goal: none - best next steps (/lnav goal to set one)",
	["ui.goal.points"] = "Goal: %d points", ["ui.goal.renown"] = "Goal: renown level %d",
	["ui.goal.node"] = "Goal: advantage %d", ["ui.goal.nodeNeed"] = "Goal: advantage %d, minimum need %d points (unchecked)",
	["ui.goal.challenge"] = "Goal: %s", ["ui.goal.missing"] = " - %d missing", ["ui.goal.reachable"] = " - reachable",
	["ui.goal.invalid"] = "Goal invalid: %s - /lnav goal clear",
	["ui.pinned"] = "Pinned: %s", ["ui.pinned.done"] = "Pinned: %s - done!",
	["ui.pin"] = "Pin", ["ui.pinnedBtn"] = "Pinned", ["ui.unpin"] = "Unpin",
	["ui.status.loading"] = "Loading data ...", ["ui.status.loadingKept"] = "Loading data - last state from %s",
	["ui.status.planError"] = "Planner error - showing last valid state",
	["ui.status.combat"] = "Updating after combat", ["ui.status.incomplete"] = "Scan incomplete - details: /lnav status",
	["ui.empty"] = "No fitting recommendation with the current settings", ["ui.empty.hint"] = "Try: /lnav set dungeon on, /lnav set raid on or /lnav set switch on",
	["ui.tooltip.why"] = "Why", ["ui.tooltip.open"] = "Open sub-goals", ["ui.tooltip.more"] = "+ %d more",
	["ui.minimap.hint"] = "Left-click: toggle overlay", ["ui.here"] = "Here: %s",
}

local L = enUS
if GetLocale and GetLocale() == "deDE" then L = deDE end
ns.L = setmetatable({}, { __index = function(_, key) return L[key] or enUS[key] or key end })
ns.Locale = { enUS = enUS, deDE = deDE } -- exposed for tests (every enUS key needs a deDE entry)

-- Shared text formatter (R5): one wording for chat, overlay, tracker and tooltip (architecture.md 12.2).
local L2 = ns.L
local Text = {}
ns.Text = Text

local function plural(key, n) return string.format(L2[n == 1 and key .. ".one" or key], n) end

-- "6 bosses open", "24 levels missing"; criteria wording follows missing.ctype (boss | area | other).
function Text.missing(card)
	local m = card.missing
	if m.kind == "criteria" then return plural("plan.missing." .. (m.ctype == "boss" and "boss" or m.ctype == "area" and "area" or "other"), m.n) end
	return plural("plan.missing." .. m.kind, m.n)
end

-- name is the achievement name (the card only carries its ID).
function Text.contribution(card, name)
	if card.contribution ~= "point" then
		return string.format(L2["plan.contribution.progress"], name or card.name or string.format(L2["plan.unnamed"], card.achievementID or 0))
	end
	local m = card.missing
	return L2[(m and m.kind == "criteria" and m.n == 1) and "plan.contribution.pointLast" or "plan.contribution.point"]
end

-- Confirmed data says nothing (""); stale data carries its date. `now` is accepted for callers, unused.
function Text.data(card, _now)
	if card.dataState ~= "stale" then return "" end
	local format = date or (os and os.date)
	if type(card.capturedAt) ~= "number" or not format then return L2["plan.data.staleUnknown"] end
	return string.format(L2["plan.data.stale"], format("%Y-%m-%d", card.capturedAt))
end

function Text.why(card)
	local list = {}
	for _, key in ipairs(card.why or {}) do list[#list + 1] = L2["plan.why." .. key] end
	return list
end

-- "Realm-Name" -> "Name"
function Text.name(charKey)
	return (tostring(charKey):match("^.*%-(.+)$")) or tostring(charKey)
end
