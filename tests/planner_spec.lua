-- Run from the addon folder: lua tests/planner_spec.lua
local function check(value, message)
	if not value then error(message or "assertion failed", 2) end
end
local function eq(actual, expected, message)
	if actual ~= expected then
		error((message or "mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

-- Coupling guard: no WoW API stubs exist, and any read of an undefined global fails loudly.
local ns = {}
assert(loadfile("Definitions.lua"))("LegacyNavigator", ns)
assert(loadfile("Model.lua"))("LegacyNavigator", ns)
assert(loadfile("Planner.lua"))("LegacyNavigator", ns)
local fx = {
	cat = assert(loadfile("tests/fixtures/catalogue.lua"))(),
	chars = assert(loadfile("tests/fixtures/characters.lua"))(),
}
setmetatable(_G, { __index = function(_, key) error("planner touched undefined global " .. tostring(key), 2) end })

local Planner = ns.Planner
local A, B = "Realm-Alpha", "Realm-Beta"
local function char(cat, o) return fx.chars.char(cat, o) end
local function input(cat, chars, o) return fx.chars.input(ns, cat, chars, o) end
local function ids(list)
	local out = {}
	for i, c in ipairs(list) do out[i] = c.achievementID end
	return out
end
local function has(list, id)
	for _, c in ipairs(list) do if c.achievementID == id then return c end end
end

-- 1. Account-wide completion is not offered again on any character.
do
	local cat = fx.cat.subset(62012)
	local skills = { [2937] = { rank = 20, max = 75 } }
	local inp = input(cat, { [A] = char(cat, { skills = skills }), [B] = char(cat, { skills = skills }) })
	local first = Planner.plan(inp)
	check(#first.cards == 1, "open alchemy should be offered before completion")
	eq(first.cards[1].missing.n, 130, "rank 20 needs 130 for 150")
	inp.characters[A].criteria[111540].q = 60 -- a stored quantity above the rank wins
	eq(Planner.plan(inp).cards[1].missing.n, 90)
	inp.characters[A].criteria[111540].q = 5 -- a lower one never lowers the rank
	eq(Planner.plan(inp).cards[1].missing.n, 130)
	inp.account.completed[62012] = true
	local r = Planner.plan(inp)
	eq(#r.cards, 0, "completed achievement still offered"); eq(#r.alternatives, 0); eq(r.status, "none")
end

-- 2. Several characters are alternative ways to one result, not extra results.
do
	local cat = fx.cat.subset(61994)
	local r = Planner.plan(input(cat, { [A] = char(cat, { level = 5 }), [B] = char(cat, { level = 10 }) }))
	eq(#r.cards, 1, "one result expected"); eq(#r.alternatives, 1, "second character is an alternative way")
	eq(r.cards[1].charKey, A); eq(r.alternatives[1].charKey, B); eq(r.alternatives[1].achievementID, 61994)
end

-- 3. A partial criterion is not a full completion.
do
	local cat = fx.cat.subset(90001)
	local five = Planner.plan(input(cat, { [A] = char(cat, { done = { 91001, 91002, 91003, 91004, 91005 } }) }))
	eq(five.cards[1].contribution, "point"); eq(five.cards[1].missing.n, 1)
	-- finishing the dungeon earns its point even when several criteria remain
	local four = Planner.plan(input(cat, { [A] = char(cat, { done = { 91001, 91002, 91003, 91004 } }) }))
	eq(four.cards[1].contribution, "point"); eq(four.cards[1].missing.n, 2)
	eq(Planner.plan(input(cat, { [A] = char(cat) })).cards[1].missing.n, 6)
end

-- 4. A point balance invents no completions; a reachable goal claims no achievement.
do
	local cat = fx.cat.subset(61994, 90001)
	local inp = input(cat, { [A] = char(cat, { points = { available = 16, spent = 0 } }) })
	inp.account.renown = 16
	local r = Planner.plan(inp)
	eq(r.status, "ok"); eq(#r.cards, 2, "both achievements stay open"); eq(inp.account.completed[61994], nil)
	inp.goal = { type = "points", need = 3 }
	r = Planner.plan(inp)
	eq(r.status, "reachable"); eq(r.cards[1].achievementID, nil, "reachable card must not name an achievement")
end

-- 5. Missing or loading data is never zero progress.
do
	local cat = fx.cat.subset(61994)
	local inp = input(cat, { [A] = char(cat) })
	inp.account.state = "loading"
	local r = Planner.plan(inp)
	eq(r.status, "loading"); eq(#r.cards, 0)
	inp = input(cat, { [A] = char(cat, { criteria = false }) })
	eq(Planner.plan(inp).status, "loading", "missing criteria")
	inp = input(cat, { [A] = char(cat) }, { states = { account = "confirmed", character = "loading" } })
	eq(Planner.plan(inp).status, "loading", "character still loading")
	inp = input(cat, { [A] = char(cat) }, { catalogue = false })
	eq(Planner.plan(inp).status, "loading", "no catalogue")
	inp = input(cat, { [A] = char(cat) }, { states = { account = "confirmed", character = "confirmed", points = "stale" } })
	eq(Planner.plan(inp).cards[1].dataState, "stale", "stale points must not read as confirmed")
	-- unknown skills: no profession candidate instead of 0 skill
	local alch = fx.cat.subset(62012)
	local c = char(alch); c.skills = nil
	eq(#Planner.plan(input(alch, { [A] = c })).cards, 0, "unknown skills produced a card")
end

-- 6. Suitable step on the current character stays first; the nearer twink is an alternative.
do
	local cat = fx.cat.subset(62000)
	local r = Planner.plan(input(cat, {
		[A] = char(cat, { classFile = "PRIEST", level = 17 }),
		[B] = char(cat, { classFile = "PRIEST", level = 19, state = "stale", capturedAt = 500 }),
	}))
	eq(r.cards[1].charKey, A); eq(r.cards[1].missing.n, 8); eq(r.cards[1].dataState, "confirmed")
	eq(r.alternatives[1].charKey, B); eq(r.alternatives[1].missing.n, 6); eq(r.alternatives[1].dataState, "stale")
	eq(r.alternatives[1].capturedAt, 500)
	-- no step on current (wrong class): twink becomes card 1 with a reason
	local r2 = Planner.plan(input(cat, {
		[A] = char(cat, { classFile = "MAGE", level = 17 }),
		[B] = char(cat, { classFile = "PRIEST", level = 19 }),
	}))
	eq(r2.cards[1].charKey, B); eq(r2.reason, "noStepOnCurrent"); eq(r2.cards[1].why[1], "switch")
end

-- 7. PvP never without explicit enabling; unrated never.
do
	local cat = fx.cat.subset(61994, 90001, 62046, 684, 900003)
	local defs = setmetatable({ zoneMaps = { [900003] = 1411 } }, { __index = ns.Definitions })
	local inp = input(cat, { [A] = char(cat) }, { definitions = defs, location = { mapID = 1411 } })
	local r = Planner.plan(inp)
	check(not has(r.cards, 62046) and not has(r.alternatives, 62046) and not has(r["local"], 62046), "pvp without enable")
	check(not has(r["local"], 900003), "pvp helper leaked into local")
	check(not has(r.cards, 684) and not has(r.alternatives, 684) and not has(r["local"], 684), "unrated produced a card")
	check(has(r.cards, 90001), "positive control: rated dungeon offered")
	inp.settings.activities.pvp = true
	r = Planner.plan(inp)
	check(has(r.cards, 62046), "enabled pvp was not allowed")
	check(has(r["local"], 900003), "positive control: enabled pvp helper is local")
	check(not has(r.cards, 684), "unrated produced a card with pvp on")
end

-- 8. A local opportunity does not displace the pinned step.
do
	local cat = fx.cat.subset(62382, 728, 900002)
	local pinned = { achievementID = 62012, charKey = A, pinnedAt = 1 }
	local inp = input(cat, { [A] = char(cat) }, { pinned = pinned, location = { mapID = 1411 } })
	local r = Planner.plan(inp)
	check(r.pinned == pinned, "pinned step not passed through unchanged")
	eq(pinned.achievementID, 62012)
	eq(#r["local"], 1); eq(r["local"][1].achievementID, 728); eq(r["local"][1].location.mapID, 1411)
	check(not has(r.cards, 728), "local opportunity leaked into cards")
end

-- 9. No zone map: no location, so no waypoint can be derived.
do
	local cat = fx.cat.subset(62382, 728, 900002)
	local c = char(cat, { done = { 112686 } }) -- only the unmapped helper remains
	local r = Planner.plan(input(cat, { [A] = c }, { location = { mapID = 9999 } }))
	eq(r.cards[1].achievementID, 62382); eq(r.cards[1].location, nil, "location invented"); eq(#r["local"], 0)
	local mapped = Planner.plan(input(cat, { [A] = char(cat) }))
	eq(mapped.cards[1].location.mapID, 1411)
end

-- 10. An optional provider (Nav) failing or absent changes nothing in the core result.
do
	local cat = fx.cat.subset(61994, 90001)
	local inp = input(cat, { [A] = char(cat) })
	local function digest(r) return table.concat(ids(r.cards), ",") .. "|" .. r.status end
	ns.Nav = nil
	local without = digest(Planner.plan(inp))
	ns.Nav = { available = function() error("provider down") end }
	eq(digest(Planner.plan(inp)), without, "planner depends on the optional provider")
	ns.Nav = nil
end

-- 11. No goal: useful overview with distinct cards, at most three.
do
	local cat = fx.cat.subset(61994, 62012, 62382, 728, 900002, 90001, 90002)
	local r = Planner.plan(input(cat, { [A] = char(cat, { skills = { [2937] = { rank = 10, max = 75 } } }) }))
	eq(r.status, "ok"); eq(#r.cards, 3)
	local seen = {}
	for _, c in ipairs(r.cards) do check(not seen[c.achievementID], "duplicate card"); seen[c.achievementID] = true end
	check(not has(r.cards, 90002), "raid default must be off")
	local acts = {}
	for _, c in ipairs(r.cards) do acts[cat.achievements[c.achievementID].activity] = true end
	check(acts.dungeon and acts.solo, "cards should span activities")
end

-- 12. Already reachable goal: goal view, no acquisition cards.
do
	local cat = fx.cat.subset(61994, 90001)
	local inp = input(cat, { [A] = char(cat, { points = { available = 5, spent = 0 } }) }, { goal = { type = "points", need = 5 } })
	local r = Planner.plan(inp)
	eq(r.status, "reachable"); eq(#r.cards, 1); eq(r.cards[1].action, "spend"); eq(r.goal.reachable, true)
	inp.characters[A].points.available = 4
	r = Planner.plan(inp)
	eq(r.status, "ok"); eq(r.goal.remaining, 1); eq(r.goal.reachable, false)
end

-- Stability: same input, same order; character order of insertion is irrelevant.
do
	local cat = fx.cat.subset(61994, 62012, 62382, 728, 900002, 90001, 90002)
	local C = "Realm-Gamma"
	local function build(order)
		local all = {
			[A] = char(cat), [B] = char(cat, { level = 7, state = "stale" }), [C] = char(cat, { level = 7, capturedAt = 900 }),
		}
		local chars = {}
		for _, key in ipairs(order) do chars[key] = all[key] end
		return chars
	end
	local function digest(r)
		local out = {}
		for _, list in ipairs({ r.cards, r.alternatives }) do
			for _, c in ipairs(list) do out[#out + 1] = c.achievementID .. "@" .. c.charKey end
			out[#out + 1] = "|"
		end
		return table.concat(out, ",")
	end
	local base = digest(Planner.plan(input(cat, build({ A, B, C }))))
	check(base:find(B, 1, true) and base:find(C, 1, true), "three characters should show up")
	for _, order in ipairs({ { A, C, B }, { B, A, C }, { B, C, A }, { C, A, B }, { C, B, A } }) do
		eq(digest(Planner.plan(input(cat, build(order)))), base, "order of insertion changed the result")
	end
end

-- Extras: switch off, invalid need, challenge goal, class rules, node goal.
do
	local cat = fx.cat.subset(61994)
	local chars = { [A] = char(cat, { classFile = "ROGUE" }), [B] = char(cat, { level = 3 }) }
	eq(#Planner.plan(input(cat, chars)).cards, 1, "twink offered with switching on")
	local r = Planner.plan(input(cat, chars, { settings = { activities = { solo = true }, allowCharacterSwitch = false } }))
	eq(r.status, "none", "current rogue has no Novice Mage step and switching is off")
	eq(Planner.plan(input(cat, chars, { goal = { type = "points", need = 17 } })).status, "invalid")
	eq(Planner.plan(input(cat, chars, { goal = { type = "challenge", id = 123 } })).reason, "challengeUnknown")
	local un = fx.cat.subset(684)
	eq(Planner.plan(input(un, { [A] = char(un) }, { goal = { type = "challenge", id = 684 } })).reason, "challengeUnrated")
	local g = Planner.plan(input(cat, chars, { goal = { type = "challenge", id = 61994 } }))
	eq(g.cards[1].charKey, B); eq(g.cards[1].why[1], "goal")
	local done = input(cat, chars, { goal = { type = "challenge", id = 61994 } }); done.account.completed[61994] = true
	eq(Planner.plan(done).status, "reachable")
	-- class level: Mage level 1 needs 24 levels
	local mage = Planner.plan(input(cat, { [A] = char(cat, { level = 1 }) }))
	eq(mage.cards[1].missing.n, 24); eq(mage.cards[1].missing.kind, "level")
	-- node goal: 2 ranks + (gate 5 - 1 spent in tree) = 6
	local trees = { [1187] = { nodes = { [10] = { currentRank = 0, maxRanks = 2, conditionIDs = { 1 } }, [11] = { currentRank = 1, maxRanks = 1 } },
		conditions = { [1] = { spentAmountRequired = 5 } } } }
	local node = input(cat, { [A] = char(cat, { points = { available = 3, spent = 0 } }) }, { goal = { type = "node", nodeID = 10, ranks = 2 }, trees = trees })
	r = Planner.plan(node)
	eq(r.goal.need, 6); eq(r.goal.unchecked, true); eq(r.goal.remaining, 3)
	node.characters[A].points.available = 6
	eq(Planner.plan(node).status, "reachable")
	node.trees = nil
	eq(Planner.plan(node).status, "loading")
end

-- Type-8 chain (Explorer over helper achievements): open helpers are counted, partial helpers are not done.
do
	local cat = fx.cat.subset(62382, 728, 900002)
	local all = Planner.plan(input(cat, { [A] = char(cat) })).cards[1]
	eq(all.achievementID, 62382); eq(all.missing.n, 3, "open areas (2 + 1), not open helpers (O5)")
	-- one helper done on the character, the other has 2 unvisited areas (one of its criteria partly done)
	local c = char(cat, { done = { 112687, 831 } })
	local one = Planner.plan(input(cat, { [A] = c })).cards[1]
	eq(one.missing.n, 1, "helper with unvisited areas must count as open"); eq(one.missing.items[1], 728)
	eq(one.contribution, "point")
	-- helper completed account-wide drops out
	local inp = input(cat, { [A] = char(cat) }); inp.account.completed[728] = true
	local r = Planner.plan(inp).cards[1]
	eq(r.missing.n, 1); eq(r.missing.items[1], 900002)
end

-- Next open class threshold only.
do
	local cat = fx.cat.subset(62003, 62004)
	local rogue = { [A] = char(cat, { classFile = "ROGUE", level = 1 }) }
	local r = Planner.plan(input(cat, rogue))
	eq(#r.cards, 1, "only the next threshold is a step"); eq(r.cards[1].achievementID, 62003); eq(r.cards[1].missing.n, 24)
	local inp = input(cat, rogue); inp.account.completed[62003] = true
	r = Planner.plan(inp)
	eq(r.cards[1].achievementID, 62004); eq(r.cards[1].missing.n, 44)
	r = Planner.plan(input(cat, { [A] = char(cat, { classFile = "ROGUE", level = 30 }) }))
	eq(#r.cards, 1); eq(r.cards[1].achievementID, 62004); eq(r.cards[1].missing.n, 15)
end

-- Proximity beats kind and size; without a matching location the smaller need wins.
do
	local cat = fx.cat.subset(62382, 728, 900002, 90003)
	local chars = { [A] = char(cat) }
	eq(Planner.plan(input(cat, chars)).cards[1].achievementID, 90003)
	local near = Planner.plan(input(cat, chars, { location = { mapID = 1411 } }))
	eq(near.cards[1].achievementID, 62382, "card in the current zone should come first")
	eq(Planner.plan(input(cat, chars, { location = { mapID = 1420 } })).cards[1].achievementID, 90003)
end

-- D19: within one activity the smallest RELATIVE remainder (open/total, exact fractions) comes first.
do
	local cat = fx.cat.subset(62003, 62382, 728, 900002, 90001)
	local chars = { [A] = char(cat, { classFile = "ROGUE", level = 1, done = { 91001, 91002, 91003, 91004, 91005 } }) }
	local on = { settings = { activities = { solo = true, dungeon = true }, allowCharacterSwitch = false } }
	local r = Planner.plan(input(cat, chars, on))
	local novice, explorer, dungeon = has(r.cards, 62003), has(r.cards, 62382), has(r.cards, 90001)
	check(novice and explorer and dungeon, "all three candidates offered")
	eq(novice.missing.total, 25); eq(novice.missing.n, 24)
	eq(explorer.missing.total, 3); eq(explorer.missing.n, 3)
	eq(dungeon.missing.total, 6); eq(dungeon.missing.n, 1)
	-- 24/25 = 0.96 < 3/3 = 1.0: Novice before Explorer (both solo); dungeon 1/6 has the smallest share but prep ranks solo first
	eq(table.concat(ids(r.cards), ","), "62003,90001,62382", "card 1 = Novice (0.96 < 1.0); selection rule 6 then prefers the other activity for card 2")
	local again = Planner.plan(input(cat, chars, on))
	eq(table.concat(ids(again.cards), ","), table.concat(ids(r.cards), ","), "order must stay stable")
	-- fraction beats absolute size: 1 of 25 levels left beats 1 of 3 areas
	local c2 = char(cat, { classFile = "ROGUE", level = 24 })
	eq(Planner.plan(input(cat, { [A] = c2 })).cards[1].achievementID, 62003)
end

-- D20: proximity only breaks an exact ratio tie; it never beats a smaller relative remainder.
do
	local cat = fx.cat.subset(62003, 62382, 728, 900002)
	local chars = { [A] = char(cat, { classFile = "ROGUE", level = 1 }) }
	local r = Planner.plan(input(cat, chars, { location = { mapID = 1411 } }))
	eq(has(r.cards, 62382).missing.n, 3); eq(has(r.cards, 62382).missing.total, 3)
	eq(r.cards[1].achievementID, 62003, "near explorer (3/3) must lose to far level milestone (24/25)")
	-- exact tie 1/1 vs 1/1: proximity decides, then absolute n
	local function crit(id, t, assetID) return { id = id, type = t, req = 1, assetID = assetID } end
	local function ach(id, criteria, pts) return { id = id, name = "A" .. id, points = pts or 0, categoryID = 10, activity = "solo", criteria = criteria } end
	local tie = { build = "70205", readAt = 1000, categories = {}, achievements = {
		[1001] = ach(1001, { crit(1, 8, 728) }, 1), [1002] = ach(1002, { crit(2, 8, 768) }, 1),
		[728] = ach(728, { crit(20, 43), crit(21, 43) }), [768] = ach(768, { crit(10, 43), crit(11, 43), crit(12, 43) }),
	} }
	local function first(loc) return Planner.plan(input(tie, { [A] = char(tie) }, { location = loc and { mapID = loc } })).cards[1].achievementID end
	eq(first(nil), 1001, "no location: smaller absolute n"); eq(first(1411), 1001)
	eq(first(1420), 1002, "ratio tie: the near one wins over smaller n")
	-- nested helper: the local entry carries the zone helper id and its own open count, not the chain's
	local loc = Planner.plan(input(tie, { [A] = char(tie, { done = { 10 } }) }, { location = { mapID = 1420 } }))["local"]
	eq(loc[1].achievementID, 768); eq(loc[1].missing.n, 2); eq(loc[1].missing.total, 3); eq(loc[1].charKey, A)
end

-- Cards 2-3: current character first, twink-only results fill the rest (only with switching allowed).
do
	local cat = fx.cat.subset(61994, 62000, 90001)
	local chars = { [A] = char(cat, { classFile = "MAGE" }), [B] = char(cat, { classFile = "PRIEST", level = 5 }) }
	local r = Planner.plan(input(cat, chars))
	eq(table.concat(ids(r.cards), ","), "61994,90001,62000")
	eq(r.cards[2].charKey, A); eq(r.cards[3].charKey, B); eq(r.cards[3].why[1], "switch")
	check(has(r.alternatives, 90001) and not has(r.alternatives, 62000), "same-achievement twink ways stay alternatives")
	r = Planner.plan(input(cat, chars, { settings = { activities = { solo = true, dungeon = true }, allowCharacterSwitch = false } }))
	eq(table.concat(ids(r.cards), ","), "61994,90001"); eq(#r.alternatives, 0)
end

-- Challenge goal on a disabled activity.
do
	local cat = fx.cat.subset(90001)
	local inp = input(cat, { [A] = char(cat) }, { goal = { type = "challenge", id = 90001 } })
	eq(Planner.plan(inp).status, "ok")
	inp.settings.activities.dungeon = false
	local r = Planner.plan(inp)
	eq(r.status, "invalid"); eq(r.reason, "challengeDisabled")
end

-- Goal validity: impossible need, points state, node ranks and node gates beyond 16.
do
	local cat = fx.cat.subset(61994)
	local function pts(o, n, extra)
		local inp = input(cat, { [A] = char(cat, { points = o }) }, { goal = { type = "points", need = n } })
		for k, v in pairs(extra or {}) do inp[k] = v end
		return inp
	end
	local inp = pts({ available = 0, spent = 0 }, 16); inp.account.renown = 60
	local r = Planner.plan(inp)
	eq(r.status, "invalid"); eq(r.reason, "needImpossible")
	inp.account.renown = 0
	eq(Planner.plan(inp).status, "ok")
	inp.account.renown = 60; inp.characters[A].points.available = 11 -- 5 missing, 5 left
	eq(Planner.plan(inp).status, "ok")
	-- unknown/loading points or no balance: no verdict
	r = Planner.plan(pts({ available = 5, spent = 0 }, 3, { states = { account = "confirmed", character = "confirmed", points = "loading" } }))
	eq(r.status, "loading"); eq(r.reason, "points"); eq(#r.cards, 0)
	r = Planner.plan(pts({ spent = 0 }, 3))
	eq(r.status, "loading"); eq(r.reason, "points")
	-- stale points: reachable, but not as confirmed
	r = Planner.plan(pts({ available = 5, spent = 0 }, 3, { states = { account = "confirmed", character = "confirmed", points = "stale" } }))
	eq(r.status, "reachable"); eq(r.cards[1].dataState, "stale")
	-- node goal: gates above 16 are allowed, bad ranks are not
	local trees = { [1187] = { nodes = { [10] = { currentRank = 0, maxRanks = 2, conditionIDs = { 1 } } }, conditions = { [1] = { spentAmountRequired = 20 } } } }
	local node = input(cat, { [A] = char(cat) }, { goal = { type = "node", nodeID = 10, ranks = 2 }, trees = trees })
	r = Planner.plan(node)
	eq(r.status, "ok"); eq(r.goal.need, 22)
	for _, bad in ipairs({ 3, 0, 1.5 }) do
		node.goal.ranks = bad
		r = Planner.plan(node)
		eq(r.status, "invalid"); eq(r.reason, "nodeRanks")
	end
	node.goal.ranks = nil
	eq(Planner.plan(node).goal.need, 22, "default ranks = maxRanks")
end

-- O1: goal types. renown = lifetime earned (account.renown), cap 65, never a spend card.
do
	local cat = fx.cat.subset(61994, 90001)
	local function rn(level, renown, available)
		local inp = input(cat, { [A] = char(cat, { points = { available = available or 0, spent = 0 } }) }, { goal = { type = "renown", level = level } })
		inp.account.renown = renown
		return Planner.plan(inp)
	end
	local r = rn(40, 25, 16)
	eq(r.status, "ok", "enough spendable points must not make a renown goal reachable")
	eq(r.goal.type, "renown"); eq(r.goal.need, 15); eq(r.goal.remaining, 15); eq(r.goal.reachable, nil)
	for _, c in ipairs(r.cards) do check(c.action ~= "spend", "renown goal offered a spend card") end
	r = rn(65, 0); eq(r.status, "ok"); eq(r.goal.need, 65)
	r = rn(66, 0); eq(r.status, "invalid"); eq(r.reason, "needAbove"); eq(r.reasonArg, 65)
	eq(rn(0, 0).reason, "needInvalid"); eq(rn(1.5, 0).reason, "needInvalid")
	r = rn(20, 20); eq(r.status, "reachable"); eq(r.cards[1].action, "chooseGoal")
	r = rn(10, nil); eq(r.status, "loading"); eq(r.reason, "renown")
	-- points goal keeps its 16 cap and spend card
	local inp = input(cat, { [A] = char(cat, { points = { available = 16, spent = 0 } }) }, { goal = { type = "points", need = 16 } })
	eq(Planner.plan(inp).cards[1].action, "spend")
	inp.goal.need = 17; eq(Planner.plan(inp).reason, "needAbove")
end

-- O5: Explorer counts open AREAS of open helpers; helpers with unknown criteria drop the achievement.
do
	local cat = fx.cat.subset(62382, 728, 900002)
	local card = Planner.plan(input(cat, { [A] = char(cat) })).cards[1]
	eq(card.missing.n, 3, "728 has 2 open areas, 900002 has 1"); eq(card.missing.ctype, "area")
	eq(card.missing.items[1], 728); eq(card.missing.items[2], 900002, "items keep the helper IDs")
	local part = Planner.plan(input(cat, { [A] = char(cat, { done = { 831 } }) })).cards[1]
	eq(part.missing.n, 2, "one area of 728 done")
	local c = char(cat); c.criteria[831] = nil -- one area unknown
	eq(#Planner.plan(input(cat, { [A] = c })).cards, 0, "unknown helper criterion must drop the achievement, not count 0")
	local broken = fx.cat.subset(62382, 728, 900002)
	broken.achievements[900002] = nil
	eq(#Planner.plan(input(broken, { [A] = char(broken) })).cards, 0, "missing helper must drop the achievement")
end

-- missing.ctype from the criteria type of the open criteria.
do
	local cat = fx.cat.subset(90001, 62012)
	local card = Planner.plan(input(cat, { [A] = char(cat) })).cards[1]
	eq(card.achievementID, 90001); eq(card.missing.ctype, "boss")
	check(has(Planner.plan(input(cat, { [A] = char(cat, { skills = { [2937] = { rank = 1, max = 75 } } }) })).cards, 62012))
end

-- Recursive type-8 chains: Explorer -> Azeroth -> 2 continents -> zones -> areas; ctype 78; nested local zone.
do
	local function crit(id, t, assetID) return { id = id, type = t, req = 1, assetID = assetID } end
	local function ach(id, activity, criteria, pts) return { id = id, name = "A" .. id, points = pts or 0, categoryID = 10, activity = activity, criteria = criteria } end
	local cat = { build = "70205", readAt = 1000, categories = {}, achievements = {
		[62382] = ach(62382, "solo", { crit(1, 8, 62053) }, 1),
		[62053] = ach(62053, "solo", { crit(2, 8, 62353), crit(3, 8, 62355) }),
		[62353] = ach(62353, "solo", { crit(4, 8, 768), crit(5, 8, 728) }),
		[62355] = ach(62355, "solo", { crit(6, 8, 900002) }),
		[768] = ach(768, "solo", { crit(10, 43), crit(11, 43), crit(12, 43) }),
		[728] = ach(728, "solo", { crit(20, 43), crit(21, 43) }),
		[900002] = ach(900002, "solo", { crit(30, 43), crit(31, 43) }),
		[90010] = ach(90010, "dungeon", { crit(40, 78), crit(41, 0), crit(42, 0), crit(43, 0), crit(44, 0), crit(45, 0) }, 1),
	} }
	local function explorer(c, o)
		local inp = input(cat, { [A] = c }, o)
		return inp, Planner.plan(inp)
	end
	local c = char(cat, { done = { 10, 11 } })
	local inp, r = explorer(c)
	local card = has(r.cards, 62382); check(card, "explorer offered")
	eq(card.missing.n, 1 + 2 + 2, "open leaves at any depth (768: 1, 728: 2, 900002: 2)")
	eq(card.missing.total, 7); eq(card.missing.ctype, "area")
	eq(table.concat(card.missing.items, ","), "768,728,900002", "lowest-level zone helpers")
	-- one zone account-complete: all its leaves done, total still counts them
	inp.account.completed[728] = true
	card = has(Planner.plan(inp).cards, 62382)
	eq(card.missing.n, 3); eq(card.missing.total, 7); eq(table.concat(card.missing.items, ","), "768,900002")
	-- chain level done on the character marks the whole subtree done
	local c2 = char(cat, { done = { 3 } })
	card = has(select(2, explorer(c2)).cards, 62382)
	eq(card.missing.n, 5); eq(card.missing.total, 7)
	-- account-complete zone with unknown criteria: drop, never invent
	local broken = char(cat); inp = input(cat, { [A] = broken }); inp.account.completed[728] = true
	cat.achievements[728] = nil
	eq(has(Planner.plan(inp).cards, 62382), nil, "unknown leaf count must drop the candidate")
	cat.achievements[728] = ach(728, "solo", { crit(20, 43), crit(21, 43) })
	-- cycle: drop instead of looping
	cat.achievements[768].criteria = { crit(10, 8, 62382) }
	eq(has(select(2, explorer(char(cat))).cards, 62382), nil, "cycle must drop")
	cat.achievements[768].criteria = { crit(10, 43), crit(11, 43), crit(12, 43) }
	-- local opportunity finds the nested zone helper
	local loc = Planner.plan(input(cat, { [A] = char(cat) }, { location = { mapID = 1420 } }))["local"]
	eq(loc[1] and loc[1].achievementID, 768, "nested zone helper is the local opportunity")
	-- Spelunker-like: one type 78 + five type 0 = boss
	local sp = has(Planner.plan(input(cat, { [A] = char(cat) }, { settings = { activities = { solo = true, dungeon = true }, allowCharacterSwitch = true } })).cards, 90010)
	check(sp, "spelunker offered"); eq(sp.missing.ctype, "boss"); eq(sp.missing.n, 6)
end

-- Local opportunities exclude the pinned challenge.
do
	local cat = fx.cat.subset(62382, 728, 900002)
	local inp = input(cat, { [A] = char(cat) }, { location = { mapID = 1411 } })
	eq(Planner.plan(inp)["local"][1].achievementID, 728)
	inp.pinned = { achievementID = 728, charKey = A, pinnedAt = 1 }
	eq(#Planner.plan(inp)["local"], 0, "pinned challenge listed as local opportunity")
end

print("planner_spec: all checks passed")
