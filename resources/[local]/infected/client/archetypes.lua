-- The three flavours of infected. Adding a fourth is just another entry here
-- plus a weight in mixForWave.
Archetypes = {}

Archetypes.definitions = {
    shambler = {
        label      = 'Shambler',
        health     = 260,
        -- Has to be plainly slower than a player on foot: a shambler wins by
        -- never stopping, not by being quick. Was 0.55, which read in-game as
        -- keeping pace with us and left nowhere to walk away to.
        moveRate   = 0.40,
        clipset    = 'move_m@drunk@verydrunk', -- the classic shuffle
        -- no trigger: it walks the whole way
        sprintAt   = nil,
        sprintRate = nil,
    },

    runner = {
        label      = 'Runner',
        health     = 180,
        moveRate   = 1.45,
        clipset    = nil,
        sprintAt   = nil,
        sprintRate = nil,
    },

    -- The nasty one. Walks in like a shambler, then breaks into a sprint once
    -- it is close enough that you have already stopped worrying about it.
    stalker = {
        label      = 'Stalker',
        health     = 220,
        -- Tracks the shambler rate deliberately. The whole trick is that you
        -- cannot pick one out of the shuffling crowd, so if it walks in faster
        -- than the shamblers around it that IS the tell and the sprint stops
        -- being a surprise. Move this whenever the shambler moves.
        moveRate   = 0.36,
        clipset    = 'move_m@drunk@verydrunk',
        sprintAt   = 25.0,
        sprintRate = 1.7,
    },

    -- The boss. Leads every Nth wave: a walking tank with crits OFF, so
    -- headshots do NOT drop it - you pour shells into it or you run. Also
    -- works with the dev tools: /here brute.
    brute = {
        label      = 'Brute',
        health     = 2500,
        moveRate   = 0.9,
        clipset    = nil,
        sprintAt   = nil,
        sprintRate = nil,
        model      = 'u_m_y_juggernaut_01',
        crits      = false,
        bossBlip   = true,
    },
}

-- How many brutes lead a given wave. Zero except on the boss cadence.
function Archetypes.bruteCountForWave(wave, count)
    if wave < Config.waves.bruteEvery or wave % Config.waves.bruteEvery ~= 0 then
        return 0
    end
    return math.max(1, math.floor(count / 10))
end

-- Set by the /clipset dev command to audition a different walk across the whole
-- horde without editing archetypes. nil means "use each archetype's own".
-- { clipset = <string> } or { clipset = false } for no clipset at all.
Archetypes.override = nil

function Archetypes.effectiveClipset(archetypeName)
    if Archetypes.override then
        return Archetypes.override.clipset or nil
    end

    local archetype = Archetypes.definitions[archetypeName]
    return archetype and archetype.clipset or nil
end

-- Weighted mix that sours as the night goes on: early waves are mostly
-- shamblers, later waves are mostly things that run at you.
function Archetypes.mixForWave(wave)
    local runners  = math.min(0.45, 0.05 * wave)
    local stalkers = math.min(0.35, 0.03 * wave)

    return {
        shambler = 1.0 - runners - stalkers,
        runner   = runners,
        stalker  = stalkers,
    }
end

function Archetypes.pick(mix)
    local roll  = math.random()
    local floor = 0.0

    for name, weight in pairs(mix) do
        floor = floor + weight
        if roll <= floor then
            return name
        end
    end

    return 'shambler'
end
