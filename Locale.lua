local _, ns = ...

-- Status strings only. Keys are the enUS text.
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
	["Use /lnav (Legacy window), /lnav status, /lnav refresh, /lnav plan, /lnav goal, /lnav set, /lnav legacy, /lnav unlock, /lnav lock, /lnav reset, /lnav tracker or /lnav diag."] = "Nutze /lnav (Legacy-Fenster), /lnav status, /lnav refresh, /lnav plan, /lnav goal, /lnav set, /lnav legacy, /lnav unlock, /lnav lock, /lnav reset, /lnav tracker oder /lnav diag.",
	["Incomplete scans logged: %d (newest last; /lnav status log shows all)"] = "Unvollständige Scans protokolliert: %d (neueste zuletzt; /lnav status log zeigt alle)",
	["  %s build %s: %s"] = "  %s Build %s: %s",
	["Tracker locked."] = "Tracker gesperrt.", ["Tracker unlocked."] = "Tracker entsperrt.", ["Positions reset."] = "Positionen zurückgesetzt.",
	-- shared UI texts
	["ui.title"] = "Legacy Navigator", ["ui.binding"] = "Legacy Navigator ein/aus",
	["ui.goal.none"] = "Kein Ziel – beste nächste Schritte",
	["ui.goal.points"] = "Ziel: %d Punkte ausgeben", ["ui.goal.renown"] = "Ziel: Renown-Stufe %d", ["ui.goal.named"] = "Ziel: %s",
	["ui.goal.sub.points"] = "%d Punkte fehlen", ["ui.goal.sub.points.one"] = "%d Punkt fehlt",
	["ui.goal.sub.levels"] = "%d Stufen fehlen", ["ui.goal.sub.levels.one"] = "%d Stufe fehlt",
	["ui.goal.sub.unchecked"] = "Voraussetzungen ungeprüft", ["ui.goal.sub.reachable"] = "erreichbar – zum Legacy-Fenster",
	["ui.goal.invalid"] = "Ziel ungültig: %s - /lnav goal clear",
	["ui.pin"] = "Anheften", ["ui.pinnedBtn"] = "Angeheftet", ["ui.unpin"] = "Lösen",
	["ui.status.loading"] = "Daten werden geladen ...", ["ui.status.loadingKept"] = "Daten werden geladen - letzter Stand vom %s",
	["ui.status.planError"] = "Planer-Fehler - letzter gültiger Stand",
	["ui.status.combat"] = "Aktualisierung nach dem Kampf", ["ui.status.incomplete"] = "Scan unvollständig - Details: /lnav status",
	["ui.empty"] = "Keine passende Empfehlung mit den aktuellen Einstellungen", ["ui.empty.hint"] = "Versuche: /lnav set dungeon on, /lnav set raid on oder /lnav set switch on",
	["ui.tooltip.why"] = "Warum", ["ui.tooltip.open"] = "Offene Teilziele", ["ui.tooltip.more"] = "+ %d weitere",
	["ui.minimap.hint"] = "Linksklick: Legacy-Fenster ein/aus", ["ui.here"] = "Hier: %s",
	-- planner output
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
	["plan.reason.challengeCompleted"] = "Herausforderung bereits abgeschlossen",
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
	["plan.contribution.point"] = "+1 Legacy-Punkt bei Abschluss",
	["plan.contribution.pointLast"] = "Letzter Schritt: +1 Legacy-Punkt",
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
	["plan.unnamed"] = "Aufgabe %d", ["panel.pinned"] = "Angeheftet: %s",
	["Goal set."] = "Ziel gesetzt.",
	["Goal cleared."] = "Ziel gelöscht.",
	["Usage: /lnav goal points N | renown N | challenge ID | node ID [ranks] | clear"] = "Aufruf: /lnav goal points N | renown N | challenge ID | node ID [Ränge] | clear",
	["Usage: /lnav set pvp|dungeon|raid|switch on|off"] = "Aufruf: /lnav set pvp|dungeon|raid|switch on|off",
	["Setting %s: %s"] = "Einstellung %s: %s",
	["on"] = "an", ["off"] = "aus",
	["Planner error: %s"] = "Planer-Fehler: %s",
	-- Legacy window
	["ui.legacy"] = "Zum Legacy-Fenster",
	["legacy.combat"] = "Nicht im Kampf",
	["legacy.error"] = "Legacy-Fenster konnte nicht geöffnet werden: %s",
	["jump.failed"] = "Herausforderung konnte nicht markiert werden - das Legacy-Fenster ist geöffnet. Evtl. durch Suche oder Filter ausgeblendet.",
	["tracker.header"] = "Legacy", ["tracker.here"] = "Hier", ["tracker.done"] = "%s – erledigt!",
	["tracker.next"] = "Nächster: %s · klicken zum Anheften", ["Tracker on."] = "Tracker an.", ["Tracker off."] = "Tracker aus.",
	["Usage: /lnav tracker on|off"] = "Aufruf: /lnav tracker on|off|alpha 0-100",
	["Usage: /lnav tracker alpha 0-100"] = "Aufruf: /lnav tracker alpha 0-100",
	["tracker.unlocked"] = "Entsperrt – ziehen, /lnav lock zum Sperren", ["panel.set.alpha"] = "Tracker-Hintergrund: %d %%",
	["Minimap button on."] = "Minimap-Knopf an.", ["Minimap button off."] = "Minimap-Knopf aus.",
	-- docked panel
	["panel.goal.change"] = "Ziel ändern", ["panel.goal.clear"] = "Ziel löschen",
	["panel.tab.plan"] = "Plan", ["panel.tab.chars"] = "Charaktere", ["panel.tab.settings"] = "Einstellungen",
		["panel.menu.missing"] = "Das Zielmenü braucht MenuUtil, das in diesem Client fehlt. Ziele per Mittelklick oder /lnav goal setzen.",
		["panel.menu.none"] = "Kein Ziel (Orientierung)", ["panel.menu.points"] = "Punkte ausgeben…", ["panel.menu.pointsN"] = "%d Punkte",
	["panel.menu.renown"] = "Renown-Stufe…", ["panel.menu.renownN"] = "Stufe %d", ["panel.menu.renownReward"] = "Stufe %d (Belohnung)",
	["panel.menu.challenge"] = "Herausforderung…", ["panel.menu.node"] = "Vorteil… (ungeprüft)",
	["panel.menu.nodeN"] = "%s (Rang %d/%d)",
	["panel.char.level"] = "Stufe %d", ["panel.char.points"] = "%d Punkte verfügbar",
	["panel.set.dungeon"] = "Dungeons empfehlen", ["panel.set.raid"] = "Schlachtzüge empfehlen", ["panel.set.pvp"] = "PvP empfehlen",
	["panel.set.switch"] = "Charakterwechsel vorschlagen", ["panel.set.tracker"] = "Tracker anzeigen", ["panel.set.minimap"] = "Minimap-Knopf anzeigen",
	["panel.set.unlock"] = "Tracker entsperren", ["panel.set.lock"] = "Tracker sperren", ["panel.set.reset"] = "Positionen zurücksetzen",
	["panel.options.text"] = "Das Legacy-Navigator-Panel erscheint rechts neben dem Legacy-Fenster. Dort stellst du Ziel und Optionen ein.",
	["panel.options.open"] = "Einstellungen öffnen",
	-- Hooks in Blizzard's Legacy window
	["hooks.node"] = "Vorteil %d", ["hooks.goalSet"] = "Ziel gesetzt: %s",
	["hooks.hint.goal"] = "Mittelklick: als Ziel setzen",
	["hooks.reason.unknown"] = "Nicht im Katalog (Daten noch nicht bereit?)", ["hooks.reason.noPoints"] = "Bringt keinen Legacy-Punkt",
	["hooks.reason.completed"] = "Bereits abgeschlossen", ["hooks.reason.unrated"] = "Nicht wertbar (Anforderung unlesbar)",
	["hooks.reason.disabled"] = "Aktivität in den Einstellungen aus", ["hooks.reason.owned"] = "Vorteil bereits voll erworben",
	["tree.1187"] = "Berufe", ["tree.1188"] = "Abenteuer", ["tree.1189"] = "Fortschritt",
}

local enUS = {
	["plan.header.none"] = "Plan (orientation, no goal)",
	["plan.header.points"] = "Plan - goal: %d points",
	["plan.header.node"] = "Plan - goal: perk %d (minimum need, unchecked): %d points",
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
	["plan.reason.treesMissing"] = "perk trees not read yet",
	["plan.reason.needInvalid"] = "point need must be a whole number >= 1",
	["plan.reason.needAbove"] = "point need above the limit of %d",
	["plan.reason.challengeUnknown"] = "challenge not in catalogue",
	["plan.reason.challengeUnrated"] = "challenge is not rated",
	["plan.reason.challengeDisabled"] = "the challenge's activity is switched off",
	["plan.reason.challengeCompleted"] = "challenge already completed",
	["plan.reason.needImpossible"] = "need cannot be reached with the remaining Legacy points",
	["plan.reason.nodeRanks"] = "ranks outside the valid range",
	["plan.reason.points"] = "point balance not read yet",
	["plan.header.nodeUnknown"] = "Plan - goal: perk %d (need unknown)",
	["plan.reason.nodeUnknown"] = "perk node unknown",
	["plan.reason.nodeOwned"] = "perk already owned",
	["plan.reason.goalType"] = "unknown goal type",
	["plan.reason.noStep"] = "no suitable task with a known remaining need",
	["plan.reason.noStepOnCurrent"] = "no known step on this character; a twink is offered instead",
	["plan.card.spend"] = "Open the Legacy window and spend points (%d available)",
	["plan.card.chooseGoal"] = "Goal reached - pick a new goal (/lnav goal)",
	["plan.card.line"] = "%d. %s (%s): %s",
	["plan.card.alt"] = "   Alternative: %s (%s): %s",
	["plan.card.local"] = "  Here: %s (%s)",
	["plan.contribution.point"] = "+1 Legacy point on completion",
	["plan.contribution.pointLast"] = "Last step: +1 Legacy point",
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
	["plan.unnamed"] = "Task %d", ["panel.pinned"] = "Pinned: %s",
	["Use /lnav (Legacy window), /lnav status, /lnav refresh, /lnav plan, /lnav goal, /lnav set, /lnav legacy, /lnav unlock, /lnav lock, /lnav reset, /lnav tracker or /lnav diag."] = "Use /lnav (Legacy window), /lnav status, /lnav refresh, /lnav plan, /lnav goal, /lnav set, /lnav legacy, /lnav unlock, /lnav lock, /lnav reset, /lnav tracker or /lnav diag.",
	["ui.title"] = "Legacy Navigator", ["ui.binding"] = "Toggle Legacy Navigator",
	["ui.goal.none"] = "No goal – best next steps",
	["ui.goal.points"] = "Goal: spend %d points", ["ui.goal.renown"] = "Goal: renown level %d", ["ui.goal.named"] = "Goal: %s",
	["ui.goal.sub.points"] = "%d points missing", ["ui.goal.sub.points.one"] = "%d point missing",
	["ui.goal.sub.levels"] = "%d levels missing", ["ui.goal.sub.levels.one"] = "%d level missing",
	["ui.goal.sub.unchecked"] = "prerequisites unchecked", ["ui.goal.sub.reachable"] = "reachable – go to the Legacy window",
	["ui.goal.invalid"] = "Goal invalid: %s - /lnav goal clear",
	["ui.pin"] = "Pin", ["ui.pinnedBtn"] = "Pinned", ["ui.unpin"] = "Unpin",
	["ui.status.loading"] = "Loading data ...", ["ui.status.loadingKept"] = "Loading data - last state from %s",
	["ui.status.planError"] = "Planner error - showing last valid state",
	["ui.status.combat"] = "Updating after combat", ["ui.status.incomplete"] = "Scan incomplete - details: /lnav status",
	["ui.empty"] = "No fitting recommendation with the current settings", ["ui.empty.hint"] = "Try: /lnav set dungeon on, /lnav set raid on or /lnav set switch on",
	["ui.tooltip.why"] = "Why", ["ui.tooltip.open"] = "Open sub-goals", ["ui.tooltip.more"] = "+ %d more",
	["ui.minimap.hint"] = "Left-click: toggle Legacy window", ["ui.here"] = "Here: %s",
	["ui.legacy"] = "To Legacy window",
	["legacy.combat"] = "Not in combat",
	["legacy.error"] = "Could not open the Legacy window: %s",
	["jump.failed"] = "Could not select the challenge - the Legacy window is open. It may be hidden by the search or a filter.",
	["tracker.header"] = "Legacy", ["tracker.here"] = "Here", ["tracker.done"] = "%s – done!",
	["tracker.next"] = "Next: %s · click to pin", ["Tracker on."] = "Tracker on.", ["Tracker off."] = "Tracker off.",
	["Usage: /lnav tracker on|off"] = "Usage: /lnav tracker on|off|alpha 0-100",
	["Usage: /lnav tracker alpha 0-100"] = "Usage: /lnav tracker alpha 0-100",
	["tracker.unlocked"] = "Unlocked – drag, /lnav lock to lock", ["panel.set.alpha"] = "Tracker background: %d %%",
	["Minimap button on."] = "Minimap button on.", ["Minimap button off."] = "Minimap button off.",
	-- docked panel
	["panel.goal.change"] = "Change goal", ["panel.goal.clear"] = "Clear goal",
	["panel.tab.plan"] = "Plan", ["panel.tab.chars"] = "Characters", ["panel.tab.settings"] = "Settings",
		["panel.menu.missing"] = "The goal menu needs MenuUtil, which this client lacks. Set goals by middle-click or /lnav goal.",
		["panel.menu.none"] = "No goal (orientation)", ["panel.menu.points"] = "Spend points…", ["panel.menu.pointsN"] = "%d points",
	["panel.menu.renown"] = "Renown level…", ["panel.menu.renownN"] = "Level %d", ["panel.menu.renownReward"] = "Level %d (reward)",
	["panel.menu.challenge"] = "Challenge…", ["panel.menu.node"] = "Perk… (unchecked)",
	["panel.menu.nodeN"] = "%s (rank %d/%d)",
	["panel.char.level"] = "Level %d", ["panel.char.points"] = "%d points available",
	["panel.set.dungeon"] = "Recommend dungeons", ["panel.set.raid"] = "Recommend raids", ["panel.set.pvp"] = "Recommend PvP",
	["panel.set.switch"] = "Suggest character switch", ["panel.set.tracker"] = "Show tracker", ["panel.set.minimap"] = "Show minimap button",
	["panel.set.unlock"] = "Unlock tracker", ["panel.set.lock"] = "Lock tracker", ["panel.set.reset"] = "Reset positions",
	["panel.options.text"] = "The Legacy Navigator panel appears next to the Legacy window. Set your goal and options there.",
	["panel.options.open"] = "Open settings",
	-- Hooks in Blizzard's Legacy window
	["hooks.node"] = "Perk %d", ["hooks.goalSet"] = "Goal set: %s",
	["hooks.hint.goal"] = "Middle-click: set as goal",
	["hooks.reason.unknown"] = "Not in the catalogue (data not ready yet?)", ["hooks.reason.noPoints"] = "Grants no Legacy point",
	["hooks.reason.completed"] = "Already completed", ["hooks.reason.unrated"] = "Not rated (requirement unreadable)",
	["hooks.reason.disabled"] = "Activity is off in the settings", ["hooks.reason.owned"] = "Perk already fully owned",
	["tree.1187"] = "Professions", ["tree.1188"] = "Adventure", ["tree.1189"] = "Progression",
}

local L = enUS
if GetLocale and GetLocale() == "deDE" then L = deDE end
ns.L = setmetatable({}, { __index = function(_, key) return L[key] or enUS[key] or key end })
ns.Locale = { enUS = enUS, deDE = deDE } -- exposed for tests (every enUS key needs a deDE entry)

-- Shared text formatter: one wording for chat, overlay, tracker and tooltip.
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

-- progress of the pinned step as { done, total, text = "done/total" }; nil without a reliable total.
-- level: total = threshold level, done = current level (= total - n); criteria: total = all criteria.
function Text.ProgressFor(card)
	local m = card and card.missing
	if not m or card.status == "done" or card.status == "unknown" then return nil end
	if type(m.total) ~= "number" or m.total <= 0 or type(m.n) ~= "number" then return nil end
	local done = math.max(0, math.min(m.total, m.total - m.n))
	return { done = done, total = m.total, text = done .. "/" .. m.total }
end

-- name is the achievement name (the card only carries its ID).
function Text.contribution(card, name)
	if card.contribution == "point" then return "" end -- every challenge gives one point, not worth a segment
	return string.format(L2["plan.contribution.progress"], name or card.name or string.format(L2["plan.unnamed"], card.achievementID or 0))
end

-- Tooltip line for point cards: "+1 Legacy point on completion" or, with exactly one open sub-goal, "Last step: ...".
function Text.pointNote(card)
	if card.contribution ~= "point" then return "" end
	local m = card.missing
	return L2[(m and m.kind == "criteria" and m.n == 1) and "plan.contribution.pointLast" or "plan.contribution.point"]
end

-- Goal block: big line = what the goal is; sub line = what is missing + caveat, once. name = node/challenge name.
function Text.goalLine(goal, name)
	if not goal then return L2["ui.goal.none"] end
	if goal.type == "points" then return string.format(L2["ui.goal.points"], goal.need or 0) end
	if goal.type == "renown" then return string.format(L2["ui.goal.renown"], goal.level or 0) end
	return string.format(L2["ui.goal.named"], name or "?")
end

function Text.goalSub(goal, result)
	if not goal or not result or result.status == "invalid" or result.status == "loading" then return "" end
	local g, parts = result.goal or {}, {}
	if result.status == "reachable" then parts[1] = L2["ui.goal.sub.reachable"] end
	if g.remaining and g.remaining > 0 and result.status ~= "reachable" then parts[1] = plural(goal.type == "renown" and "ui.goal.sub.levels" or "ui.goal.sub.points", g.remaining) end
	if goal.type == "node" then parts[#parts + 1] = L2["ui.goal.sub.unchecked"] end
	return table.concat(parts, " · ")
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
