-- Wave director. The server owns wave number and score; clients own peds.
local state = {
    running   = false,
    wave      = 0,
    kills     = 0,
    alive     = 0,
    spawned   = 0,  -- spawned in the current wave
    dead      = 0,  -- dead in the current wave
    ready     = {},
    scores    = {}, -- kills per player server id
    intensity = 1.0, -- wave-size multiplier, set by the pint mission
    engagedExt = false, -- a mission holds the apocalypse on without waves
}

-- Best-wave record, persisted across restarts in record.json.
local record = json.decode(LoadResourceFile(GetCurrentResourceName(), 'record.json') or 'null')
    or { bestWave = 0 }

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next)  do merged[key] = value end
    state = merged
end

local function engagedNow()
    return state.running or state.engagedExt
end

-- Tells every client whether the apocalypse is "on". Off = the city populates
-- normally and free-roam is just GTA.
local function broadcastEngaged()
    TriggerClientEvent('infected:engaged', -1, engagedNow())
end

local function readyPlayers()
    local players = {}

    for source in pairs(state.ready) do
        if GetPlayerName(source) then
            players[#players + 1] = source
        end
    end

    return players
end

local function broadcastState()
    TriggerClientEvent('infected:waveState', -1, state.wave, state.kills, state.alive, state.scores)
end

local function waveSize(wave)
    local size = math.floor(
        (Config.waves.startingSize + Config.waves.growthPerWave * (wave - 1)) * state.intensity)
    return math.min(math.max(size, 1), Config.waves.sizeCap, Config.budget.maxAliveGlobal - state.alive)
end

-- Difficulty dial for mission scripts: <1 quietens the waves, >1 swells them.
exports('setIntensity', function(factor)
    setState({ intensity = math.max(0.2, math.min(2.0, tonumber(factor) or 1.0)) })
    return state.intensity
end)

-- Splits a wave across the clients so no single machine runs the whole horde's
-- AI. Remainder is handed out one each from the front.
local function splitQuota(total, players)
    local count = #players
    if count == 0 then return {} end

    local base      = math.floor(total / count)
    local remainder = total % count
    local quotas    = {}

    for index, source in ipairs(players) do
        quotas[source] = base + (index <= remainder and 1 or 0)
    end

    return quotas
end

local function startWave()
    local players = readyPlayers()

    if #players == 0 then
        return false, 'nobody ready'
    end

    local wave  = state.wave + 1
    local total = waveSize(wave)

    if total <= 0 then
        return false, 'no global headroom for another wave'
    end

    setState({ wave = wave, spawned = 0, dead = 0 })

    -- Brutes lead every Nth wave (the boss cadence): a red-blip set-piece worth
    -- clipping. Mark it here, where the server already knows the number, using
    -- the same rule Archetypes.bruteCountForWave applies client-side.
    if wave >= Config.waves.bruteEvery and wave % Config.waves.bruteEvery == 0 then
        TriggerEvent('telemetry:mark', 'brute-wave:' .. wave)
    end

    for source, quota in pairs(splitQuota(total, players)) do
        if quota > 0 then
            TriggerClientEvent('infected:spawnShare', source, quota, wave)
        end
    end

    print(('[infected] wave %d: %d infected across %d players'):format(wave, total, #players))
    broadcastState()

    return true
end

local function waveCleared()
    if state.spawned == 0 then return false end
    return state.dead >= math.floor(state.spawned * Config.waves.clearFraction)
end

RegisterNetEvent('infected:playerReady', function()
    local source = source
    state.ready[source] = true
    TriggerClientEvent('infected:engaged', source, engagedNow())
end)

RegisterNetEvent('infected:reportSpawned', function(count, wave)
    if wave ~= state.wave then return end
    setState({ spawned = state.spawned + count, alive = state.alive + count })
    broadcastState()
end)

RegisterNetEvent('infected:reportDead', function(killed, culled, killers)
    local removed = (killed or 0) + (culled or 0)

    local scores = {}
    for id, n in pairs(state.scores) do scores[id] = n end
    for id, n in pairs(killers or {}) do
        local key = tonumber(id) or id
        scores[key] = (scores[key] or 0) + n
    end

    setState({
        kills  = state.kills + (killed or 0),
        alive  = math.max(0, state.alive - removed),
        dead   = state.dead + removed,
        scores = scores,
    })

    broadcastState()
end)

AddEventHandler('playerDropped', function()
    local source = source
    state.ready[source] = nil
    -- Their peds die with them; let the next wave resync rather than guess.
end)

CreateThread(function()
    Wait(Config.waves.firstDelayMs)

    while true do
        if state.running and (state.wave == 0 or waveCleared()) then
            -- The breather goes BEFORE the next wave, not after it. Players are
            -- told the wave is cleared, get the jittered gap to breathe and
            -- resupply, and only then does the next one land. The old order
            -- spawned the next wave the instant one cleared, which is why it
            -- never felt like discrete waves.
            if state.wave > 0 then
                TriggerClientEvent('infected:waveCleared', -1, state.wave)
                print(('[infected] wave %d cleared'):format(state.wave))

                -- A clean clear, especially a last-second one, clips well, so
                -- flag it for the highlight pass alongside the moments.
                TriggerEvent('telemetry:mark', 'wave-cleared:' .. state.wave)

                if state.wave > record.bestWave then
                    record = { bestWave = state.wave, set = os.date('%Y-%m-%d') }
                    SaveResourceFile(GetCurrentResourceName(), 'record.json', json.encode(record), -1)
                    TriggerClientEvent('chat:addMessage', -1, {
                        color = { 255, 180, 0 },
                        args  = { 'infected', ('NEW RECORD: wave %d cleared!'):format(state.wave) },
                    })
                end
                Wait(math.random(Config.waves.gapMinMs, Config.waves.gapMaxMs))
            end

            if state.running then
                local started, err = startWave()

                if not started then
                    print('[infected] wave not started: ' .. tostring(err))
                    Wait(5000)
                end
            end
        else
            Wait(2000)
        end
    end
end)

-- Hooks for the optional infected_dev resource.
exports('setRunning', function(running)
    setState({ running = running and true or false })
    broadcastEngaged()

    if state.running and record.bestWave > 0 then
        TriggerClientEvent('chat:addMessage', -1, {
            color = { 255, 180, 0 },
            args  = { 'infected', ('Record to beat: wave %d (set %s)'):format(record.bestWave, record.set or '?') },
        })
    end

    return state.running
end)

exports('setEngaged', function(on)
    setState({ engagedExt = on and true or false })
    broadcastEngaged()
    return engagedNow()
end)

-- One-shot: spawns a single wave WITHOUT switching the director on. Mission
-- ambushes use this; only setRunning (/horde start, mission holdouts) makes
-- waves keep coming.
exports('forceNextWave', function()
    setState({ spawned = 0, dead = 0 })
    return startWave()
end)

exports('jumpToWave', function(wave)
    local target = math.max(0, math.floor(tonumber(wave) or 0))
    setState({ running = true, wave = target - 1, spawned = 0, dead = 0 })
    return startWave()
end)

exports('resetAll', function()
    setState({ running = false, wave = 0, kills = 0, alive = 0, spawned = 0, dead = 0 })
    TriggerClientEvent('infected:reset', -1)
    broadcastState()
end)

exports('getState', function()
    return {
        running = state.running,
        wave    = state.wave,
        kills   = state.kills,
        alive   = state.alive,
        spawned = state.spawned,
        dead    = state.dead,
    }
end)

RegisterCommand('infected', function(source, args)
    local action = args[1]

    if action == 'start' then
        setState({ running = true })
        print('[infected] director started')
    elseif action == 'stop' then
        setState({ running = false })
        TriggerClientEvent('infected:reset', -1)
        print('[infected] director stopped, horde cleared')
    elseif action == 'reset' then
        setState({ running = false, wave = 0, kills = 0, alive = 0, spawned = 0, dead = 0 })
        TriggerClientEvent('infected:reset', -1)
        broadcastState()
        print('[infected] reset')
    else
        print('[infected] usage: infected start|stop|reset')
    end
end, true)

-- /score - kill leaderboard, for arguing about who carried the night.
RegisterCommand('score', function(source)
    local rows = {}
    for id, kills in pairs(state.scores) do
        rows[#rows + 1] = { name = GetPlayerName(id) or ('#' .. tostring(id)), kills = kills }
    end
    table.sort(rows, function(a, b) return a.kills > b.kills end)

    local lines = {}
    for rank, row in ipairs(rows) do
        lines[#lines + 1] = ('%d. %s - %d'):format(rank, row.name, row.kills)
    end
    local text = #lines > 0 and table.concat(lines, '  |  ') or 'No kills yet.'

    if source > 0 then
        TriggerClientEvent('chat:addMessage', source, { color = { 255, 180, 0 }, args = { 'score', text } })
    else
        print('[infected] ' .. text)
    end
end, false)

-- ===== player-facing controls =====
-- These live here, not in infected_dev: they are how the horde game mode is
-- played, not cheats, and stopping the dev tools for game night must not take
-- them away with it.
local function say(source, message)
    if source > 0 then
        TriggerClientEvent('chat:addMessage', source, {
            color = { 220, 120, 120 },
            args  = { 'horde', message },
        })
    else
        print('[infected] ' .. message)
    end
end

RegisterCommand('horde', function(source, args)
    local action = args[1] or 'state'

    if action == 'start' then
        setState({ running = true })
        broadcastEngaged()
        say(source, 'Director running. Good luck.')

    elseif action == 'stop' then
        setState({ running = false })
        broadcastEngaged()
        TriggerClientEvent('infected:reset', -1)
        say(source, 'Director stopped, horde cleared.')

    elseif action == 'reset' then
        setState({ running = false, wave = 0, kills = 0, alive = 0, spawned = 0, dead = 0, scores = {} })
        broadcastEngaged()
        TriggerClientEvent('infected:reset', -1)
        broadcastState()
        say(source, 'Reset to wave 0.')

    else
        say(source, ('running=%s wave=%d alive=%d kills=%d (%d/%d cleared)'):format(
            tostring(state.running), state.wave, state.alive, state.kills, state.dead, state.spawned))
    end
end, false)

RegisterCommand('wave', function(source, args)
    local target = tonumber(args[1])

    if target then
        setState({ running = true, wave = target - 1, spawned = 0, dead = 0 })
        broadcastEngaged()
        local ok, err = startWave()
        say(source, ok and ('Jumped to wave %d.'):format(target)
            or ('Could not start wave: ' .. tostring(err)))
    else
        setState({ spawned = 0, dead = 0 })
        local ok, err = startWave()
        say(source, ok and 'Next wave incoming.'
            or ('Could not start wave: ' .. tostring(err)))
    end
end, false)

-- Random events during sandbox horde, using the mission moments. The pint
-- resource registers the client handler whether or not a mission is running.
CreateThread(function()
    local names = { 'planecrash', 'crashcar', 'runner', 'helicopter', 'turning',
                    'ambulance', 'faller', 'stampede', 'tanker' }

    while true do
        Wait(math.random(55000, 115000))

        if state.running then
            local players = GetPlayers()
            if #players > 0 then
                local name = names[math.random(#names)]
                TriggerClientEvent('pint:moment',
                    tonumber(players[math.random(#players)]), name)

                -- Same mark the campaign director stamps, so the clipper treats
                -- a sandbox set-piece and a mission one identically.
                TriggerEvent('telemetry:mark', 'moment:' .. name)
            end
        end
    end
end)
