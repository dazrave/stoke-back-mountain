-- 28 Frags Later. Every tunable lives here.
Config = {
    -- ~110 networked peds per player is FiveM's practical ceiling before it
    -- starts silently despawning them. We stay well under and check headroom
    -- with CanRegisterMissionEntities before every spawn batch.
    budget = {
        maxAliveGlobal   = 50,
        maxPerClient     = 16,   -- AI cost is paid by the OWNING client
        -- GTA's CPointRoute pool is FORTY SLOTS for the whole game. Every ped
        -- on a navmesh task (TaskGoToCoordAnyMeans / TaskGoToEntity) holds
        -- one, and exhausting it hard-crashes the client with
        -- "PointRoute Pool Full, Size == 40". So only this many infected may
        -- path at once; the rest walk straight at you, which for a shambling
        -- horde looks the same anyway.
        navBudget        = 10,
        headroomRequired = 1,    -- refuse to spawn if this many slots aren't free
        cullDistance     = 250.0,
        -- Outrun a zombie past this and it does not die - it comes BACK,
        -- respawned just out of sight around you. You cannot get away.
        relocateDistance = 130.0,
        -- How long a body stays before it is deleted. Without this, corpses
        -- accumulate against maxPerClient and spawning silently stops.
        corpseLingerMs   = 2500,
    },

    waves = {
        firstDelayMs   = 15000,
        gapMinMs       = 9000,   -- random interval between waves...
        gapMaxMs       = 26000,  -- ...so they never feel metronomic
        startingSize   = 8,
        growthPerWave  = 4,
        sizeCap        = 80,
        bruteEvery     = 5,      -- every Nth wave is led by brutes
        -- A wave ends when this fraction of it is dead - stops one stuck
        -- zombie on a rooftop stalling the whole night.
        clearFraction  = 0.9,
    },

    spawn = {
        -- Ahead of you, in the direction you're travelling, anywhere from
        -- across the street to the far end of it. Spawning in a ring around
        -- the player meant walking into a wave you'd already passed.
        minDistance   = 50.0,
        maxDistance   = 200.0,
        deadAheadGap  = 18.0,     -- degrees either side of dead-ahead left empty
        forwardArc    = 120.0,    -- degrees of cone ahead to scatter within
        preferBehind  = false,
        groundProbes  = 8,
    },

    survival = {
        oneHitKill        = true,
        suppressAmbient   = true, -- kills pedestrians+traffic: frees ped pool AND sells the apocalypse
        maxWantedLevel    = 0,
        -- Permanent gloom while the mode runs; weather is restored on stop.
        atmosphere        = true,
        clockHour         = 22,
        weather           = 'FOGGY',
    },

    hud = {
        x = 0.5, y = 0.02, scale = 0.5,
    },

    -- What the survivor spawns with. A pump shotgun is deliberately slow: one
    -- or two shots then you reload or run - which is the whole point.
    -- Sidearm era: a pistol, two magazines, and your legs. Headshots matter.
    player = {
        weapon         = 'WEAPON_PISTOL',
        ammo           = 24,
        resupplyPerWave = 14, -- rounds granted to everyone on each wave clear
    },

    -- Getting hauled out of the car. Slow down or stop with them on you and
    -- you are walking. See client/hijack.lua for why this lives victim-side.
    -- Roughly one in twenty infected was a copper, and coppers carry spare
    -- magazines. They wear the uniform, so you can pick your target.
    carrier = {
        chance = 20,
        model  = 's_m_y_cop_01',
        props  = { 'prop_box_ammo01a', 'prop_box_ammo04a', 'prop_box_ammo03a', 'prop_mil_crate_01' },
        ammo   = 24,
        lifeMs = 90000,
    },

    hijack = {
        enabled  = true,
        radius      = 6.0,  -- how close one has to get to the vehicle
        maxSpeed    = 14.0, -- m/s - about 30mph; faster than this and they can't hold on
        grabMs      = 900,  -- how long they cling before you come out
        summonRange = 60.0,  -- dawdle with them this close and one WILL reach you
        stallMs     = 2500,  -- how long you have to be slow before that happens
        summonEvery = 12000, -- ...and no more often than this, so they don't pile up
    },

    relationshipGroup = 'INFECTED',

    -- Swap live in game with /clipset <key> to see which reads best.
    -- 'zombie' (very drunk) is what most GTA zombie mods settle on.
    clipsets = {
        zombie    = 'move_m@drunk@verydrunk',
        tipsy     = 'move_m@drunk@moderatedrunk',
        headup    = 'move_m@drunk@moderatedrunk_head_up',
        limp      = 'move_injured_generic',
        depressed = 'move_m@depressed@a',
        normal    = nil,
    },

    models = {
        'a_m_m_skater_01', 'a_m_y_methhead_01', 'a_m_m_tramp_01',
        'a_f_y_tourist_01', 'a_m_y_downtown_01', 'a_m_m_hillbilly_01',
        's_m_y_construct_01', 'a_f_m_downtown_01',
    },
}
