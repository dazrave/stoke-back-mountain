-- Scrap Run. One fugitive, everyone else is Old Bill. All tunables here.
Config = {
    roundSeconds     = 600, -- survive this long = clean getaway
    -- Grace before the countdown even begins. Roles are sent 1.5s after the
    -- round is set up and a client can spend another 2.5s waiting for
    -- collision to load, so a countdown started at round-setup was most of the
    -- way through before anybody could see it.
    readySeconds = 4,

    -- Everyone starts in the same place now, so the gap comes from this
    -- rather than from distance. Three seconds is enough to get moving and
    -- short enough that nobody is stood watching.
    headstartSeconds = 3,   -- >0 holds the cops while the fugitive runs
    finalAlertSeconds = 60, -- citywide alert: fugitive permanently revealed

    -- Sight rules. A cop "sees" the fugitive when they are within range, on
    -- screen, with clear line of sight. Any sighting keeps the live GPS lock
    -- fed for everyone.
    sight = {
        groundRange = 120.0,
        airRange    = 250.0, -- the helicopter's whole job
        holdMs      = 10000, -- a sighting keeps the GPS lock for this long
    },

    -- Every car in the round is pegged to the same top speed, so the round is
    -- decided by driving and by the map rather than by who happened to get the
    -- quickest motor.
    --
    -- Has to sit BELOW the slowest car's own top speed or the slow ones simply
    -- never reach the cap and the whole point is lost. 34 m/s is about 76 mph,
    -- which every model in crewCars, cop.vehicles and fugitive.cars can hold.
    matchedSpeed = {
        enabled = true,
        mps     = 34.0,
    },

    -- How often the live ping actually moves, by how far away they are. Close
    -- up it is a live feed; at distance it is the occasional radio update, so
    -- a long lock stops handing the police a perfect real-time trace across
    -- the map and starts feeling like someone phoning it in.
    pingRate = {
        nearMetres = 150.0,  fastMs = 1000,
        farMetres  = 900.0,  slowMs = 8000,
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
    -- Shoot the car, not the driver. The suspect cannot be killed, so gunfire
    -- had nothing to do; this gives the police a way to actually end a pursuit
    -- and gives the fugitive a reason to keep changing cars.
    -- A police car is not a getaway car. Nicking one turned the chase into the
    -- suspect driving a cruiser while the police chased their own fleet, and it
    -- also handed them the fastest vehicles in the round.
    lockPoliceVehicles = true,

    -- What actually stops the getaway car. Ramming it is (#39): "it needs to be
    -- hit with another vehicle four times to disable it, not shot. When it's
    -- shot it can carry on, shooting only affects the wheels" - and GTA pops
    -- the tyres on its own, so gunfire still has a job.
    carHits = {
        enabled = true,
        hits    = 4,     -- impacts before the engine gives up

        rams    = true,  -- rammed by another vehicle counts
        bullets = false, -- being shot at does not: flip to true to bring it back

        -- A shunt, not a scrape. Body health runs to 1000, so brushing past
        -- traffic costs a couple of points while a proper hit costs tens.
        -- Without this the allowance would evaporate at the first busy
        -- junction, and kerbs would never have been the only worry.
        minRamDamage = 15.0,
    },

    nonLethal = {
        -- Flip this to false and the suspect can be shot dead like anyone else.
        enabled     = false,
        floorHealth = 110, -- 100 is death, so this leaves them on their last legs
        limpBelow   = 140,

        -- Shot on foot, they go down rather than die: a few seconds on the
        -- floor is the window to actually cuff them. Without this the police
        -- could empty a magazine into someone who simply kept jogging, since
        -- the health floor means gunfire can never finish the job.
        knockdown = {
            enabled  = true,
            everyMs  = 6000, -- can't be chain-stunned into a permanent nap
            downMs   = 4500, -- how long they're on the floor
        },
    },

    -- AI units. Armed, but harmless in the only way that counts: the
    -- fugitive's health floor means no amount of NPC gunfire can end the
    -- round. They shoot at the suspect they're chasing and nobody else.
    ai = {
        enabled         = true,
        -- Unarmed. They pursue, box you in and pile out after you, but the
        -- shooting is left to the human police - it is their round to win.
        -- Nothing is lost by taking their pistols away: gunfire no longer
        -- disables a car at all (#39). An AI cruiser that shunts you properly
        -- does count, which is exactly what a cruiser is for.
        armed           = false,
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

    -- Just far enough up the road not to spawn inside the fleet. The lead used
    -- to be 45m; the head start does that job now, and everyone lining up in
    -- the same place is the point.
    fugitiveLead = 8.0,

    cop = {
        weapon   = 'WEAPON_PISTOL', -- tyres, not heads
        ammo     = 250,
        spawn    = vector3(425.1, -979.5, 30.7), -- fallback only
        heading  = 90.0,
        -- Models only: the fleet is laid out along the nearest ROAD at spawn
        -- time. Hand-typed coordinates kept parking the cars inside the
        -- station, which is a very authentic police experience but unhelpful.
        vehicles     = { 'police', 'police2', 'police3', 'fbi2', 'policeb', 'policeb', 'polmav' },
        -- Nose to tail down the kerb. 6.5m is barely a car length, so any
        -- bend in the road had them overlapping and shoving each other about
        -- on spawn.
        fleetSpacing = 9.5,

        -- A copper is never out of the round. A death here is almost always
        -- the scenery at 90mph, and lying in the road until somebody gets
        -- nicked takes a player out of the whole evening with no way back.
        -- They get up where they fell, kit re-issued, and rejoin the pursuit.
        respawn = {
            enabled      = true,
            delaySeconds = 5, -- a beat on the floor to appreciate what you did
        },

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
