-- All tunables live here. Nothing below this file should hardcode a number.
Config = {
    -- No AI allies during a pint mission. The campaign is written around a
    -- crew of humans running out of petrol and shouting at each other; an
    -- extra bot each turns a tense drive into a firing squad, and they were
    -- deliberately made poor shots, so they mostly just added noise.
    -- Set false to have them come along on missions again.
    suppressDuringMissions = true,

    bot = {
        model         = 'a_m_m_bevhills_02',
        weapon        = 'WEAPON_PISTOL', -- fallback when you are unarmed at spawn
        ammo          = 120,
        maxHealth     = 250,
        armour        = 25, -- mortal: a bad wave WILL take him down
        regenPerSecond = 2, -- slow trickle: recovers between waves, not mid-fight
        accuracy      = 20, -- 0-100: he TRIES. Collateral damage, mostly.
        combatAbility = 0,  -- 0 poor, 1 average, 2 professional
        combatRange   = 1,  -- 0 near, 1 medium, 2 far
        spawnDistance = 2.0,
        modelTimeoutMs = 10000,
    },

    group = {
        formation = 0, -- 0 default, 1 circle, 2 alt circle, 3 line
        spacing   = { close = 1.0, mid = 2.5, far = 5.0 },
    },

    guard = {
        defensiveRadius = 15.0,
        patrolRange     = 25.0,
    },

    blip = {
        sprite = 1,
        colour = 2,
        scale  = 0.7,
        name   = 'Squadmate',
    },

    -- F8 is the FiveM console - deliberately avoided. All rebindable in-game
    -- under Settings > Key Bindings > FiveM.
    keys = {
        { command = 'squad_follow',     order = 'follow',     key = 'F6',  label = 'Squadmate: Follow me' },
        { command = 'squad_aggressive', order = 'aggressive', key = 'F7',  label = 'Squadmate: Be aggressive' },
        { command = 'squad_hold',       order = 'hold',       key = 'F9',  label = 'Squadmate: Hold this position' },
    },

    respawnCommand = { command = 'squad_respawn', key = 'F10', label = 'Squadmate: Respawn squadmate' },
    mirrorCommand  = { command = 'squad_weapon',  key = 'F11', label = 'Squadmate: Use my weapon' },
    fetchCommand   = { command = 'squad_fetch',   key = 'G',   label = 'Squadmate: Fetch a jerry can' },

    fetch = {
        searchRadius = 80.0, -- how far he'll look for a can
        canRefuel    = 40.0, -- % of tank per can, same as pouring one yourself
    },

    ui = {
        statusX = 0.5,
        statusY = 0.94,
        scale   = 0.42,
    },
}
