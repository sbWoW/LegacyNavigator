local _, ns = ...

-- Pure planner: stored model + settings + goal -> at most 3 cards. No WoW API, no clock, no locale text;
-- every user-facing string is a key that Core translates. Depends only on ns.Model.isAccountComplete.
local Planner = {}
ns.Planner = Planner

local PREP = { solo = 1, dungeon = 2, raid = 3 } -- also the list of plannable activities
local function prep(activity) return PREP[activity] or 4 end -- pvp (explicitly enabled) last
local MAX_CARDS, MAX_LOCAL = 3, 2

local function sortedKeys(t)
	local keys = {}
	for key in pairs(t or {}) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

local function bool(b) return b and 0 or 1 end

-- Account-wide completion: single rule in Model.isAccountComplete (fed with the persisted completed set).
local function accountDone(account, id)
	return ns.Model.isAccountComplete({ completed = account.completed[id] == true }) == true
end

local function allowed(activity, acts)
	return (PREP[activity] ~= nil or activity == "pvp") and acts[activity] == true
end

-- true = open, false = done, nil = unknown (never treated as 0 progress)
local function criterionOpen(c, char, account)
	if c.type == 8 and c.assetID and accountDone(account, c.assetID) then return false end
	local rec = char.criteria and char.criteria[c.id]
	if type(rec) ~= "table" or type(rec.done) ~= "boolean" then return nil end
	return not rec.done
end

local function zoneMap(input, helperID) return input.definitions.zoneMaps[helperID] end

-- Remaining need of one achievement for one character: kind, n, items, ctype (boss|area|other), mapID. nil = not
-- suitable or unknown.
local function need(ach, char, input, pinned)
	local def, account = input.definitions, input.account
	local milestone = def.classMilestones[ach.id]
	if milestone then
		if char.classFile ~= milestone.class or type(char.level) ~= "number" then return nil end
		local n = milestone.level - char.level
		if n <= 0 then return nil end
		-- only the next open threshold of the class is a step (Experienced is noise while Novice is open);
		-- a pinned challenge is the player's own choice and keeps its direct progress
		for id, other in pairs(not pinned and def.classMilestones or {}) do
			if other.class == milestone.class and other.level < milestone.level and input.catalogue.achievements[id]
				and not accountDone(account, id) and char.level < other.level then
				return nil
			end
		end
		return { kind = "level", n = n, total = milestone.level }
	end
	local list = ach.criteria
	if type(list) ~= "table" or #list == 0 then return nil end
	if #list == 1 and list[1].type == 7 then -- profession skill
		local skill = char.skills and char.skills[list[1].assetID]
		if type(skill) ~= "table" then return nil end -- skills unknown or profession not learned
		local rec = char.criteria and char.criteria[list[1].id]
		if type(skill.rank) ~= "number" or type(list[1].req) ~= "number" then return nil end
		local have = math.max(rec and type(rec.q) == "number" and rec.q or 0, skill.rank)
		local n = list[1].req - have
		if n <= 0 then return nil end
		return { kind = "skill", n = n, total = list[1].req }
	end
	local items, mapID, total, ctype, whole = {}, nil, 0, nil, 0 -- whole = all criteria/areas of the challenge
	local here = input.location and input.location.mapID
	local function kindOf(t) return (t == 0 or t == 78) and "boss" or t == 43 and "area" or "other" end
	local function note(t)
		local k = t == "area" and t or kindOf(t)
		ctype = (ctype == nil or ctype == k) and k or "other"
	end
	-- Type-8 chains are resolved down to leaf criteria (depth <= 6, cycle guard). Returns false when anything is
	-- unknown (never invented as 0). forced = the subtree is already done (account-complete or done at chain level).
	local MAX_DEPTH = 6
	local function walk(crits, forced, depth, path, helperID)
		local direct = 0
		for _, c in ipairs(crits) do
			local open = false
			if not forced then
				open = criterionOpen(c, char, account)
				if open == nil then return false end
			end
			if c.type == 8 then
				local h = input.catalogue.achievements[c.assetID]
				if depth >= MAX_DEPTH or path[c.assetID] or type(h) ~= "table" or type(h.criteria) ~= "table" or #h.criteria == 0 then
					return false -- total unknown: drop
				end
				path[c.assetID] = true
				local ok = walk(h.criteria, forced or not open, depth + 1, path, c.assetID)
				path[c.assetID] = nil
				if not ok then return false end
			else
				whole = whole + 1
				if open then
					total = total + 1
					if helperID then
						direct = direct + 1
						note("area")
					else
						items[#items + 1] = c.id
						note(c.type)
					end
				end
			end
		end
		if direct > 0 then
			items[#items + 1] = helperID -- lowest-level open helper IDs stay the items (zones)
			local m = zoneMap(input, helperID)
			if m and (mapID == nil or (m == here and mapID ~= here)) then mapID = m end
		end
		return true
	end
	if not walk(list, false, 0, {}, nil) then return nil end
	if total == 0 or whole < total then return nil end -- total unknown: drop, never invent
	return { kind = "criteria", n = total, total = whole, items = items, mapID = mapID, ctype = ctype }
end

-- Minimum need of an advantage node: ranks x 1 + gate shortfall inside its tree. Edge rule unchecked.
local function nodeNeed(goal, trees)
	if type(trees) ~= "table" then return nil, "treesMissing" end
	for _, treeID in ipairs(sortedKeys(trees)) do
		local tree = trees[treeID]
		local node = type(tree) == "table" and tree.nodes and tree.nodes[goal.nodeID]
		if node then
			if tree.incomplete then return nil, "treesMissing" end
			local maxRanks = node.maxRanks or 1
			local ranks = goal.ranks == nil and maxRanks or goal.ranks
			if type(ranks) ~= "number" or ranks % 1 ~= 0 or ranks < 1 or ranks > maxRanks then return nil, "nodeRanks" end
			local more = ranks - (node.currentRank or 0)
			if more <= 0 then return nil, "nodeOwned" end
			local required, spent = 0, 0
			for _, conditionID in ipairs(node.conditionIDs or {}) do
				local cond = tree.conditions and tree.conditions[conditionID]
				if cond and type(cond.spentAmountRequired) == "number" and cond.spentAmountRequired > required then
					required = cond.spentAmountRequired
				end
			end
			for _, other in pairs(tree.nodes) do spent = spent + (other.currentRank or 0) end
			return more + math.max(0, required - spent)
		end
	end
	return nil, "nodeUnknown"
end

local function dataStateOf(key, input, cur)
	if key ~= cur then return "stale" end
	local st = input.states or {}
	local a = st.account or input.account.state
	local c = st.character or input.characters[cur].state
	local p = st.points or "confirmed" -- no states given (offline input): nothing to contradict
	return (a == "confirmed" and c == "confirmed" and p == "confirmed") and "confirmed" or "stale"
end

local function makeWay(ach, key, n, input, cur)
	local char = input.characters[key]
	return {
		ach = ach, charKey = key, kind = n.kind, n = n.n, total = n.total, items = n.items, mapID = n.mapID, ctype = n.ctype,
		-- finishing the card's own achievement earns its points; "progress" only for a 0-point helper step
		contribution = type(ach.points) == "number" and ach.points > 0 and "point" or "progress",
		dataState = dataStateOf(key, input, cur), capturedAt = char.capturedAt,
	}
end

local function cmpWays(a, b)
	if (a.charKey == b.charKey) then return false end
	local ac, bc = a.isCur, b.isCur
	if ac ~= bc then return ac end
	if a.dataState ~= b.dataState then return a.dataState == "confirmed" end
	if a.n ~= b.n then return a.n < b.n end
	return a.charKey < b.charKey
end

-- Total order: hasCur, dataState, prep, relative remainder, proximity, n, achievementID.
local function cmpResults(a, b, here)
	local x, y = a.best, b.best
	if a.hasCur ~= b.hasCur then return a.hasCur end
	if x.dataState ~= y.dataState then return x.dataState == "confirmed" end
	local pa, pb = prep(a.ach.activity), prep(b.ach.activity)
	if pa ~= pb then return pa < pb end
	-- smallest relative remainder open/total first, compared as exact fractions (x.n/x.total < y.n/y.total
	-- <=> x.n*y.total < y.n*x.total, integers only, no float ties). A cross-multiplied fraction order is a total
	-- preorder (totals > 0), so it stays transitive for table.sort.
	local lx, ly = x.n * y.total, y.n * x.total
	if lx ~= ly then return lx < ly end
	-- proximity only breaks an exact ratio tie; then absolute n, then id.
	local la, lb = bool(x.mapID ~= nil and x.mapID == here), bool(y.mapID ~= nil and y.mapID == here)
	if la ~= lb then return la < lb end
	if x.n ~= y.n then return x.n < y.n end
	return a.ach.id < b.ach.id
end

local function card(way, extra)
	local c = {
		achievementID = way.ach.id, charKey = way.charKey, action = "pin", contribution = way.contribution,
		missing = { kind = way.kind, n = way.n, total = way.total, items = way.items, ctype = way.ctype }, dataState = way.dataState, capturedAt = way.capturedAt,
		location = way.mapID and { mapID = way.mapID } or nil,
	}
	for key, value in pairs(extra or {}) do c[key] = value end
	return c
end

local function whyFor(way, goalRelated, isCur)
	local why = {}
	if goalRelated then why[#why + 1] = "goal" end
	why[#why + 1] = isCur and "currentChar" or "switch"
	why[#why + 1] = way.ach.activity == "solo" and "soloNoPrep" or "groupRequired"
	return why
end

function Planner.plan(input)
	local result = { status = "ok", cards = {}, alternatives = {}, ["local"] = {}, pinned = input.pinned, goal = {} }
	local function finish(status, reason)
		result.status, result.reason = status, reason
		return result
	end
	local cur, def = input.currentChar, input.definitions
	local account, chars, catalogue = input.account, input.characters or {}, input.catalogue
	local st = input.states or {}

	-- Rule 1: validity. Unknown/loading is never zero progress.
	local char = cur and chars[cur]
	if type(account) ~= "table" or st.account == "unknown" or st.account == "loading" or account.state == "unknown" or account.state == "loading" then
		return finish("loading", "account")
	end
	if type(char) ~= "table" or type(char.criteria) ~= "table" or st.character == "unknown" or st.character == "loading"
		or char.state == "unknown" or char.state == "loading" then
		return finish("loading", "character")
	end
	if type(catalogue) ~= "table" or type(catalogue.achievements) ~= "table" or type(account.completed) ~= "table" then
		return finish("loading", "catalogue")
	end
	local acts = (input.settings and input.settings.activities) or def.defaultActivities
	local switch = not input.settings or input.settings.allowCharacterSwitch ~= false

	-- Pinned challenge: always a full way, independent of the goal (nil = nothing to pin; status says why).
	local pin = input.pinned
	if pin then
		local ach = catalogue.achievements[pin.achievementID]
		if not ach or ach.activity == "unrated" then
			result.pinnedCard = { achievementID = pin.achievementID, status = "unknown" }
		elseif accountDone(account, pin.achievementID) then
			result.pinnedCard = { achievementID = pin.achievementID, status = "done" }
		else
			-- the character the player pinned with (its own snapshot), not the best way across characters
			local key = chars[pin.charKey] and pin.charKey or cur
			local n = type(chars[key]) == "table" and need(ach, chars[key], input, true)
			local way = n and makeWay(ach, key, n, input, cur)
			result.pinnedCard = way and card(way, { why = whyFor(way, false, key == cur) })
				or { achievementID = pin.achievementID, status = "unknown" }
		end
	end

	-- Goal.
	local goal, g = input.goal, {}
	result.goal = g
	if goal ~= nil then
		g.type = goal.type
		if goal.type == "points" or goal.type == "node" then
			local n, why = goal.need, nil
			if goal.type == "node" then
				g.id, g.unchecked = goal.nodeID, true
				n, why = nodeNeed(goal, input.trees)
				if not n then return finish(why == "treesMissing" and "loading" or "invalid", why) end
			end
			if type(n) ~= "number" or n < 1 or n % 1 ~= 0 then return finish("invalid", "needInvalid") end
			-- the cap is the spendable balance; a node goal may pass its gates in stages
			if goal.type == "points" and n > (def.maxPoints or 16) then
				result.reasonArg = def.maxPoints or 16
				return finish("invalid", "needAbove")
			end
			g.need = n
			local available = char.points and char.points.available
			if st.points == "unknown" or st.points == "loading" or type(available) ~= "number" then
				return finish("loading", "points")
			end
			if type(account.renown) == "number" and n - available > 65 - account.renown then return finish("invalid", "needImpossible") end
			g.reachable, g.remaining, g.available = available >= n, math.max(0, n - available), available
			if g.reachable then
				result.cards = { { charKey = cur, action = "spend", contribution = "point", why = { "goal", "reachable" },
					dataState = dataStateOf(cur, input, cur), capturedAt = char.capturedAt, available = available } }
				return finish("reachable")
			end
		elseif goal.type == "renown" then
			-- lifetime earned points (account.renown), cosmetic levels; never a spend card.
			local level, cap = goal.level, def.maxRenown or 65
			if type(level) ~= "number" or level % 1 ~= 0 or level < 1 then return finish("invalid", "needInvalid") end
			if level > cap then result.reasonArg = cap; return finish("invalid", "needAbove") end
			if type(account.renown) ~= "number" then return finish("loading", "renown") end
			local n = level - account.renown
			g.level, g.need, g.remaining = level, n, math.max(0, n)
			if n <= 0 then
				result.cards = { { charKey = cur, action = "chooseGoal", contribution = "point", why = { "goal", "reachable" },
					dataState = dataStateOf(cur, input, cur), capturedAt = char.capturedAt } }
				return finish("reachable")
			end
		elseif goal.type == "challenge" then
			local ach = catalogue.achievements[goal.id]
			g.id = goal.id
			if not ach then return finish("invalid", "challengeUnknown") end
			if ach.activity == "unrated" then return finish("invalid", "challengeUnrated") end
			if not allowed(ach.activity, acts) then return finish("invalid", "challengeDisabled") end
			if accountDone(account, goal.id) then
				result.cards = { { achievementID = goal.id, charKey = cur, action = "chooseGoal", contribution = "point",
					why = { "goal", "reachable" }, dataState = dataStateOf(cur, input, cur), capturedAt = char.capturedAt } }
				return finish("reachable")
			end
		else
			return finish("invalid", "goalType")
		end
	end

	-- Candidates (rules 3, 4): one result per achievement, several ways (characters).
	local keys = { cur }
	if switch then
		keys = sortedKeys(chars)
	end
	local results = {}
	for _, id in ipairs(sortedKeys(catalogue.achievements)) do
		local ach = catalogue.achievements[id]
		if type(ach.points) == "number" and ach.points > 0 and not accountDone(account, id) and allowed(ach.activity, acts)
			and (not (goal and goal.type == "challenge") or id == goal.id) then
			local ways = {}
			for _, key in ipairs(keys) do
				local c = chars[key]
				if type(c) == "table" then
					local n = need(ach, c, input)
					if n then
						local way = makeWay(ach, key, n, input, cur)
						way.isCur = key == cur
						ways[#ways + 1] = way
					end
				end
			end
			if #ways > 0 then
				table.sort(ways, cmpWays)
				results[#results + 1] = { ach = ach, ways = ways, best = ways[1], hasCur = ways[1].isCur }
			end
		end
	end
	local here = input.location and input.location.mapID
	table.sort(results, function(a, b) return cmpResults(a, b, here) end)

	-- Rule 6: current character first; twink-only results only fill the slots the current character leaves.
	local picked, used = {}, {}
	for _, ownPool in ipairs({ true, false }) do -- current-character results first, twink-only results fill up
		local pool = {}
		for _, r in ipairs(results) do if r.hasCur == ownPool then pool[#pool + 1] = r end end
		while #picked < MAX_CARDS and #pool > 0 do
			local index = 1
			if #picked > 0 then -- prefer another activity
				for i, r in ipairs(pool) do if not used[r.ach.activity] then index = i; break end end
			end
			local r = table.remove(pool, index)
			picked[#picked + 1] = r
			used[r.ach.activity] = true
		end
	end
	local related = goal and goal.type == "challenge"
	for i, r in ipairs(picked) do
		local way = r.best
		result.cards[i] = card(way, { why = whyFor(way, related, way.isCur) })
		for j = 2, #r.ways do
			local alt = r.ways[j]
			result.alternatives[#result.alternatives + 1] = card(alt, { why = { "alternative" } })
		end
	end

	-- Rule 7: local opportunities for the current character, apart from the cards.
	local pinnedID = input.pinned and input.pinned.achievementID
	if here then
		for _, id in ipairs(sortedKeys(catalogue.achievements)) do
			local ach = catalogue.achievements[id]
			if #result["local"] < MAX_LOCAL and id ~= pinnedID and ach.points == 0 and allowed(ach.activity, acts) and not accountDone(account, id)
				and zoneMap(input, id) == here then
				local missing = need(ach, char, input)
				if missing then
					result["local"][#result["local"] + 1] = { achievementID = id, charKey = cur, location = { mapID = here }, missing = missing }
				end
			end
		end
	end

	if #result.cards == 0 then return finish("none", "noStep") end
	if not picked[1].best.isCur then result.reason = "noStepOnCurrent" end
	return result
end

return Planner
