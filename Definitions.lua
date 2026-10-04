local _, ns = ...

-- Versioned facts the client API does not provide. Everything else is read live.
local classes = {
	WARRIOR = { 61499, 61500, 61501 }, DRUID = { 61502, 61503, 61504 }, HUNTER = { 61989, 61992, 61993 },
	MAGE = { 61994, 61995, 61996 }, PALADIN = { 61997, 61998, 61999 }, PRIEST = { 62000, 62001, 62002 },
	ROGUE = { 62003, 62004, 62005 }, SHAMAN = { 62006, 62007, 62008 }, WARLOCK = { 62009, 62010, 62011 },
}
local LEVELS = { 25, 45, 60 } -- Novice / Experienced / Master, confirmed in client

-- [achievementID] = { class = "MAGE", level = 25 }; "for the first time on a <Class>"
local classMilestones = {}
for classFile, ids in pairs(classes) do
	for tier = 1, 3 do classMilestones[ids[tier]] = { class = classFile, level = LEVELS[tier] } end
end

local LEGACY_TREE_PROFESSIONS_ID, LEGACY_TREE_ADVENTURE_ID, LEGACY_TREE_PROGRESSION_ID = 1187, 1188, 1189

ns.Definitions = {
	LEGACY_TREE_PROFESSIONS_ID = LEGACY_TREE_PROFESSIONS_ID, LEGACY_TREE_ADVENTURE_ID = LEGACY_TREE_ADVENTURE_ID,
	LEGACY_TREE_PROGRESSION_ID = LEGACY_TREE_PROGRESSION_ID,
	verifiedBuild = "70205",
	rewardTrackFactionID = 2802,
	pointsCurrencyID = 4225,
	treeIDs = { LEGACY_TREE_PROFESSIONS_ID, LEGACY_TREE_ADVENTURE_ID, LEGACY_TREE_PROGRESSION_ID },
	pvpCategoryID = 15595, -- whole subtree is PvP
	maxPoints = 16, -- GetMaxAvailableTraitCurrency(4225, true)
	renownRewardLevels = { 15, 25, 40, 55 }, -- reward-track levels, confirmed in client
	maxRenown = 65, -- lifetime earned points = cap of the cosmetic renown goal
	-- Product decision 2026-10-04.
	defaultActivities = { solo = true, dungeon = true, raid = false, pvp = false },
	classMilestones = classMilestones,
	-- No criteria, requirement unreadable: never recommended.
	activityOverrides = { [684] = "unrated", [62054] = "unrated" },
	-- Client category IDs, confirmed. [categoryID] = "dungeon" | "raid" | "solo" | "pvp" | "ignore".
	categoryActivity = {
		[15593] = "dungeon", [15594] = "raid", [15626] = "raid",
		[15586] = "solo", [15587] = "solo", [15588] = "solo", [15589] = "solo", [15590] = "solo", [15591] = "solo", [15592] = "solo",
		[15568] = "solo", [15577] = "solo", [15578] = "solo", [15579] = "solo", [15580] = "solo", [15581] = "solo",
		[15582] = "solo", [15583] = "solo", [15584] = "solo", [15585] = "solo",
		[15596] = "solo", [15607] = "solo", [14777] = "solo", [14778] = "solo",
		[15595] = "pvp", [15597] = "pvp", [15598] = "pvp", [15620] = "pvp",
		[15425] = "ignore", -- "Do Not Display"
	},
	-- uiMapID per explorer helper achievement ([achievementID] = uiMapID); only these two are confirmed.
	zoneMaps = { [728] = 1411, [768] = 1420 }, -- Explore Durotar, Explore Tirisfal Glades
}
