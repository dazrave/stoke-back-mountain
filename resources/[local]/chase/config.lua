-- Scrap Run. One fugitive, everyone else is Old Bill. All tunables here.
Config = {
    roundSeconds     = 600, -- survive this long = clean getaway
    -- 0 = everyone goes at once. The 20s hold made the opening a countdown
    -- spent staring at somebody's back; the chase is more fun if it simply
    -- starts. The fugitive still opens up a gap from fugitiveLead below and
    -- from the cops having to get into cars.
    headstartSeconds = 0,   -- >0 holds the cops while the fugitive runs
    finalAlertSeconds = 60, -- citywide alert: fugitive permanently revealed

    -- Sight rules. A cop "sees" the fugitive when they are within range, on
    -- screen, with clear line of sight. Any sighting keeps the live GPS lock
    -- fed for everyone.
    sight = {
        groundRange = 120.0,
        airRange    = 250.0, -- the helicopter's whole job
        holdMs      = 10000, -- a sighting keeps the GPS lock for this long
    },

    -- The search circle around the last-known position grows while hidden.
    search = {
        baseRadius   = 40.0,
        growPerSec   = 8.0,
        maxRadius    = 350.0,
    },

    -- Breadcrumbs the fugitive leaves while hidden.
    reports = {
        stolenDelayMs  = 12000, -- "car reported stolen" ping lands this late
        witnessDelayMs = 9000,  -- collision witness ping
        witnessGapMs   = 20000, -- at most one witness report per this window
        pingLifeMs     = 40000, -- how long a report blip stays on the map
    },

    -- Non-lethal by law. Bullets hurt and slow the suspect but can never put
    -- them down: the only way this ends is a proper arrest. Crashing into a
    -- bridge at 90 is still entirely your own business.
    nonLethal = {
        -- Flip this to false and the suspect can be shot dead like anyone else.
        enabled     = false,
        floorHealth = 110, -- 100 is death, so this leaves them on their last legs
        limpBelow   = 140,
    },

    -- AI units. Armed, but harmless in the only way that counts: the
    -- fugitive's health floor means no amount of NPC gunfire can end the
    -- round. They shoot at the suspect they're chasing and nobody else.
    ai = {
        enabled         = true,
        weapon          = 'WEAPON_PISTOL',
        accuracy        = 25,      -- shooting from a moving car, be fair
        max             = 3,       -- how many are on you at once
        spawnEvery      = 14000,
        spawnDistance   = { 90.0, 170.0 },
        despawnDistance = 340.0,
        models          = { 'police', 'police2', 'police3' },
        driver          = 's_m_y_cop_01',
        -- The officer, not the car. A round should end because somebody got
        -- away or got nicked, not because a cruiser clipped a kerb on the
        -- Vinewood hills and the pursuit quietly evaporated. The car stays
        -- destructible on purpose - bursting tyres is half the chase.
        invincible      = true,

        -- Reinforcements come OUT OF a nick rather than materialising in the
        -- road behind you. Uses the verified `stations` list below, snapped to
        -- the nearest road node - the same trick the opening fleet uses,
        -- because hand-placed points park cars inside the building.
        fromStations    = true,
        -- Past this, the nearest nick is too far to be the source and units
        -- fall back to appearing near the suspect. Without it, a chase out at
        -- Paleto would simply stop producing police.
        stationRange    = 1200.0,
    },

    arrest = {
        range    = 3.0, -- cop on foot this close...
        maxSpeed = 2.5, -- ...to a fugitive moving slower than this
    },

    -- A different nick every round. The muster point, the fleet and the
    -- suspect are all hung off whichever one gets picked.
    stations = {
        { pos = vector3(425.1, -979.5, 30.7),   h = 90.0  }, -- Mission Row
        { pos = vector3(-1108.0, -845.0, 19.3), h = 40.0  }, -- Vespucci
        { pos = vector3(359.0, -1584.0, 29.3),  h = 320.0 }, -- Davis
        { pos = vector3(826.0, -1290.0, 28.2),  h = 180.0 }, -- La Mesa
        { pos = vector3(638.0, 1.0, 82.8),      h = 250.0 }, -- Vinewood
        { pos = vector3(1853.0, 3686.0, 34.3),  h = 210.0 }, -- Sandy Shores
        { pos = vector3(-448.0, 6014.0, 31.7),  h = 50.0  }, -- Paleto Bay
    },

    -- How far up the road the suspect starts, in plain view.
    fugitiveLead = 45.0,

    cop = {
        weapon   = 'WEAPON_PISTOL', -- tyres, not heads
        ammo     = 250,
        spawn    = vector3(425.1, -979.5, 30.7), -- fallback only
        heading  = 90.0,
        -- Models only: the fleet is laid out along the nearest ROAD at spawn
        -- time. Hand-typed coordinates kept parking the cars inside the
        -- station, which is a very authentic police experience but unhelpful.
        vehicles     = { 'police', 'police2', 'police3', 'fbi2', 'policeb', 'policeb', 'polmav' },
        fleetSpacing = 6.5,

        -- Coppers can haul the suspect out of a slow-moving car.
        dragOut = {
            radius   = 4.5,
            maxSpeed = 8.0,  -- m/s, about 18mph
            grabMs   = 1200,
        },
    },

    -- The fugitive starts up the road from the police, in plain view, with a
    -- mediocre car. Everyone watches them go - that's the whole opening beat.
    fugitive = {
        -- An ordinary car. Bikes made the fugitive almost uncatchable - kerbs,
        -- stairs, the storm drain and the hills are all shortcuts a cruiser
        -- simply cannot follow, so the pursuit stopped being a pursuit.
        -- A car keeps everyone on the same roads.
        cars  = { 'futo', 'blista', 'asterope', 'premier' },
        bikes = { 'sanchez', 'sanchez2', 'bf400', 'manchez', 'enduro' }, -- unused
        start = vector4(425.1, -1014.0, 30.7, 180.0),
        spawns = {
            vector4(215.0, -810.0, 30.7, 340.0),  -- Legion car park
            vector4(180.0, -1560.0, 29.3, 50.0),  -- Davis
            vector4(-560.0, -1045.0, 22.2, 180.0), -- La Puerta
            vector4(302.0, 180.0, 104.0, 160.0),  -- Vinewood
            vector4(-1180.0, -885.0, 13.8, 300.0), -- Vespucci
        },
    },

    -- Uniforms make the mode: cops look like cops, the rabbit looks like
    -- anyone else on the street (which is rather the point).
    models = {
        cop      = 's_m_y_cop_01',
        fugitive = 'a_m_y_downtown_01',
    },

    hud = { x = 0.5, y = 0.055, scale = 0.55 },
}
