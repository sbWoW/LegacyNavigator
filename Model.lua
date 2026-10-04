local _, ns = ...

-- Pure data layer: no WoW API calls. Raw reads come from Provider, facts from Definitions.
-- Rule: a value that could not be read stays nil; nil is never turned into 0.
local Model = {}
ns.Model = Model

Model.DOMAINS = { "account", "character", "points", "location" }
local PERSISTED = { "account", "character", "points" } -- location is session-only

function Model.newStates()
	local states = {}
	for _, domain in ipairs(Model.DOMAINS) do states[domain] = "unknown" end
	return states
end

-- At PLAYER_ENTERING_WORLD: stored data stays visible as stale, everything else is loading.
function Model.beginSession(states, store, charKey)
	local char = store and store.characters and charKey and store.characters[charKey]
	local has = { account = store and store.account, character = char, points = char and char.points }
	for _, domain in ipairs(Model.DOMAINS) do
		states[domain] = has[domain] and "stale" or "loading"
	end
end

-- A persisted domain turns confirmed only if the snapshot was saved; location (session-only) if it was
-- read. Otherwise the old state stays.
function Model.applyScan(states, incomplete, saved)
	for _, domain in ipairs(Model.DOMAINS) do
		if not incomplete[domain] and (saved or domain == "location") then states[domain] = "confirmed" end
	end
end

-- The account-wide completion assumption lives here and nowhere else (product decision 2026-10-04):
-- completed == true counts for the whole account, regardless of wasEarnedByMe.
function Model.isAccountComplete(ach)
	if type(ach) ~= "table" or type(ach.completed) ~= "boolean" then return nil end
	return ach.completed
end

local function inSubtree(categories, categoryID, rootID)
	local seen = {}
	while categoryID ~= nil and not seen[categoryID] do
		if categoryID == rootID then return true end
		seen[categoryID] = true
		local category = categories[categoryID]
		categoryID = category and category.parentID
	end
	return false
end

-- Activity of one achievement; "unrated" whenever the facts are not known.
function Model.activityFor(ach, categories, defs)
	local override = defs.activityOverrides[ach.id]
	if override then return override end
	if inSubtree(categories, ach.categoryID, defs.pvpCategoryID) then return "pvp" end
	if defs.classMilestones[ach.id] then return "solo" end
	local criteria = ach.criteria
	if type(criteria) == "table" and #criteria > 0 then
		local first = criteria[1].type
		local uniform = true
		for _, criterion in ipairs(criteria) do if criterion.type ~= first then uniform = false end end
		if uniform and first == 7 and #criteria == 1 then return "solo" end -- profession skill
		if uniform and first == 8 then return "solo" end -- chain of explorer helpers
	end
	return defs.categoryActivity[ach.categoryID] or "unrated"
end

-- raw = { build, readAt, categories = { [id] = { name, parentID } }, achievements = { raw achievement, ... } }
function Model.buildCatalogue(raw, defs)
	local catalogue = { build = raw.build, readAt = raw.readAt, achievements = {}, categories = raw.categories }
	for _, ach in ipairs(raw.achievements) do
		local entry = {
			id = ach.id, name = ach.name, points = ach.legacyPoints, categoryID = ach.categoryID, criteria = {},
		}
		for _, criterion in ipairs(ach.criteria or {}) do
			entry.criteria[#entry.criteria + 1] = {
				id = criterion.id, type = criterion.type, assetID = criterion.assetID, req = criterion.req, text = criterion.text,
			}
		end
		entry.activity = Model.activityFor(ach, raw.categories, defs)
		if entry.activity ~= "ignore" then
			if ach.legacyPoints == nil then catalogue.incomplete = true end
			catalogue.achievements[ach.id] = entry
		end
	end
	return catalogue
end

function Model.counts(catalogue)
	local total, withPoints, byActivity = 0, 0, {}
	for _, entry in pairs(catalogue.achievements) do
		total = total + 1
		if type(entry.points) == "number" and entry.points > 0 then withPoints = withPoints + 1 end
		byActivity[entry.activity] = (byActivity[entry.activity] or 0) + 1
	end
	return total, withPoints, byActivity
end

local function flag(incomplete, domain, detail)
	local list = incomplete[domain]
	if not list then list = {}; incomplete[domain] = list end
	list[#list + 1] = detail
end

-- raw = Provider scan result (see Core). Returns snap = { key, account, character, incomplete }.
-- account/character are always filled with what was read; nothing is written unless incomplete is empty
-- for the persisted domains (see Model.persist).
function Model.snapshot(raw, now)
	local incomplete = {}
	local account = { state = "confirmed", capturedAt = now, capturedBy = raw.key, build = raw.build, completed = {} }
	local character = {
		state = "confirmed", capturedAt = now, build = raw.build,
		guid = raw.guid, classFile = raw.classFile, level = raw.level, points = raw.points, criteria = {},
		earnedByMe = {}, -- O2: evidence per completed achievement; isAccountComplete stays the only rule
	}
	if type(now) ~= "number" then flag(incomplete, "character", "time") end
	if not raw.key then flag(incomplete, "character", "key") end
	if not raw.guid or not raw.classFile or type(raw.level) ~= "number" then flag(incomplete, "character", "identity") end
	-- skills stay nil (unknown) and do not block the snapshot
	if type(raw.skills) == "table" then
		character.skills = { capturedAt = now, state = "confirmed" } -- O4: own stamp; string keys never clash with skillLineIDs
		for id, skill in pairs(raw.skills) do character.skills[id] = skill end
	else flag(incomplete, "skills", "unreadable") end
	if not raw.achievementsComplete then
		flag(incomplete, "account", "achievements")
		flag(incomplete, "character", "criteria")
	end
	if type(raw.renown) ~= "number" then flag(incomplete, "account", "renown") else account.renown = raw.renown end
	local p = raw.points
	if type(p) ~= "table" or type(p.available) ~= "number" or type(p.spent) ~= "number" or (p.assumed and raw.renown ~= 0) then
		flag(incomplete, "points", "currency")
		character.points = nil
	end
	for _, ach in ipairs(raw.achievements) do
		local complete = Model.isAccountComplete(ach)
		if complete == nil then flag(incomplete, "account", "completed:" .. tostring(ach.id))
		elseif complete then
			account.completed[ach.id] = true
			if ach.wasEarnedByMe ~= nil or ach.earnedBy ~= nil then
				character.earnedByMe[ach.id] = { me = ach.wasEarnedByMe, by = ach.earnedBy }
			end
		end
		if ach.incomplete then flag(incomplete, "character", "achievement:" .. tostring(ach.id)) end
		for _, criterion in ipairs(ach.criteria or {}) do
			if criterion.id == nil or type(criterion.done) ~= "boolean" or criterion.quantity == nil then
				flag(incomplete, "character", "criterion:" .. tostring(ach.id))
			else
				character.criteria[criterion.id] = { q = criterion.quantity, done = criterion.done }
			end
		end
	end
	return { key = raw.key, account = account, character = character, incomplete = incomplete }
end

function Model.isComplete(snap)
	for _, domain in ipairs(PERSISTED) do
		if snap.incomplete[domain] then return false end
	end
	return true
end

-- Writes only a complete snapshot; an incomplete one never overwrites an older complete one.
function Model.persist(store, snap)
	if not Model.isComplete(snap) then return false end
	store.account = snap.account
	store.characters = store.characters or {}
	local old = store.characters[snap.key]
	if snap.character.skills == nil and old and old.skills then -- unreadable now: keep the last known, with its OLD stamp
		snap.character.skills = old.skills
		snap.character.skills.state = "stale"
	end
	store.characters[snap.key] = snap.character
	return true
end

function Model.summarizeIncomplete(incomplete)
	local parts = {}
	for _, domain in ipairs({ "account", "character", "points", "skills", "location" }) do
		local list = incomplete[domain]
		if list then parts[#parts + 1] = domain .. "(" .. (list[1] or "?") .. (#list > 1 and ("+" .. (#list - 1)) or "") .. ")" end
	end
	return table.concat(parts, ", ")
end

-- Known characters. Everything loaded from storage is stale, only the current character
-- becomes confirmed, and only after a complete scan in this session.
function Model.listCharacters(store, currentKey, currentConfirmed, build)
	local list = {}
	for key, char in pairs(store and store.characters or {}) do
		local state = "stale"
		if key == currentKey and currentConfirmed then state = "confirmed" end
		list[#list + 1] = {
			key = key, state = state, capturedAt = char.capturedAt, build = char.build,
			buildMismatch = build ~= nil and char.build ~= nil and tostring(char.build) ~= tostring(build),
		}
	end
	table.sort(list, function(a, b) return a.key < b.key end)
	return list
end

-- Pin = one challenge. Same achievement again unpins, another one replaces. Returns the new pin (nil = none).
function Model.togglePin(profile, card, now)
	local pinned = profile.pinned
	if pinned and pinned.achievementID == card.achievementID then
		profile.pinned = nil
	else
		profile.pinned = { achievementID = card.achievementID, charKey = card.charKey, pinnedAt = now }
	end
	return profile.pinned
end

-- True only when the pinned achievement became newly completed and is worth points.
function Model.pinCompleted(beforeCompleted, afterCompleted, pinned, catalogue)
	local id = pinned and pinned.achievementID
	if not id or (beforeCompleted and beforeCompleted[id]) or not (afterCompleted and afterCompleted[id]) then return false end
	local ach = catalogue and catalogue.achievements and catalogue.achievements[id]
	return ach ~= nil and type(ach.points) == "number" and ach.points > 0
end
