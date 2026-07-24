-- Route telemetry sink. Every player's position lands here a few times a
-- minute, plus context marks from the game modes (mission stages, wipes,
-- chase rounds) and manual /tmark notes. One JSON line per record, one file
-- per server session, under this resource's folder.
--
-- The "learning" half happens offline: the files get pulled and analysed, and
-- spawn points, wreck placement, ambushes and event triggers get retuned to
-- the routes people actually take.
local session = os.date('%Y%m%d-%H%M%S')
local file    = ('data-%s.jsonl'):format(session)
local lines   = {}
local dirty   = false

local function append(record)
    lines[#lines + 1] = json.encode(record)
    dirty = true
end

RegisterNetEvent('telemetry:batch', function(samples)
    local source = source
    if type(samples) ~= 'table' then return end

    local name = GetPlayerName(source) or ('#' .. tostring(source))
    local now  = os.time()

    for _, sample in ipairs(samples) do
        if type(sample) == 'table' and type(sample.x) == 'number' then
            append({
                t = now, p = name,
                x = sample.x, y = sample.y, z = sample.z,
                s = sample.s, v = sample.v, d = sample.d,
            })
        end
    end
end)

-- Game modes stamp context with TriggerEvent('telemetry:mark', 'label').
AddEventHandler('telemetry:mark', function(label)
    append({ t = os.time(), mark = tostring(label) })
end)

-- Players can flag a moment by hand: /tmark that bridge chase was amazing
RegisterCommand('tmark', function(source, args)
    local note = table.concat(args, ' ')
    if note == '' then note = 'moment' end

    append({
        t    = os.time(),
        mark = 'player-note',
        p    = source > 0 and GetPlayerName(source) or 'console',
        note = note,
    })

    if source > 0 then
        TriggerClientEvent('chat:addMessage', source, {
            color = { 160, 160, 160 },
            args  = { 'telemetry', 'marked: ' .. note },
        })
    end
end, false)

local function flush()
    if not dirty then return end
    dirty = false
    SaveResourceFile(GetCurrentResourceName(), file, table.concat(lines, '\n') .. '\n', -1)
end

CreateThread(function()
    while true do
        Wait(20000)
        flush()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    flush()
end)

-- /resetgame - the big red button: stop every mode, restart the game
-- resources (which sweeps their spawned entities), bin leftover vehicles and
-- respawn everyone fresh. Square one.
--
-- Uses StopResource/StartResource, NOT ExecuteCommand('ensure ...'): a
-- resource has no permission for the ensure/start console commands, so that
-- silently stopped the game modes and never brought them back.
-- Somewhere different every reset, but the crew always lands together: one
-- random spot for the whole server, everyone within a few metres of it.
local RESET_SPAWNS = {
    { x = 215.0,   y = -810.0,  z = 30.7,  h = 340.0 }, -- Legion Square
    { x = -1183.0, y = -1494.0, z = 4.4,   h = 120.0 }, -- Vespucci Beach
    { x = 1961.0,  y = 3740.0,  z = 32.3,  h = 210.0 }, -- Sandy Shores
    { x = -292.0,  y = 6256.0,  z = 31.5,  h = 45.0  }, -- Paleto Bay
    { x = 302.0,   y = 180.0,   z = 104.0, h = 160.0 }, -- Vinewood Hills
    { x = -1037.0, y = -2737.0, z = 20.2,  h = 330.0 }, -- LSIA
    { x = 1687.0,  y = 4929.0,  z = 42.1,  h = 190.0 }, -- Grapeseed
    { x = -3172.0, y = 1077.0,  z = 20.8,  h = 90.0  }, -- Chumash
    { x = 1070.0,  y = -750.0,  z = 58.0,  h = 270.0 }, -- Mirror Park
    { x = -1850.0, y = -1231.0, z = 13.0,  h = 30.0  }, -- Del Perro Pier
}

RegisterCommand('resetgame', function()
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 255, 120, 120 },
        args  = { 'server', 'Resetting everything back to square one...' },
    })

    CreateThread(function()
        StopResource('pint')
        StopResource('chase')
        Wait(500)

        -- Restarting infected also takes its dependents down, hence the order.
        StopResource('infected')
        StopResource('squadmate')
        Wait(800)

        StartResource('infected')
        StartResource('squadmate')
        Wait(1200)

        -- Bin orphaned vehicles before the modes come back, so nothing spawns
        -- on top of a leftover from the last round.
        TriggerClientEvent('telemetry:clearworld', -1)
        Wait(1500)

        StartResource('pint')
        StartResource('chase')
        Wait(1500)

        local at = RESET_SPAWNS[math.random(#RESET_SPAWNS)]

        for index, src in ipairs(GetPlayers()) do
            TriggerClientEvent('telemetry:respawn', tonumber(src), at, index)
        end

        TriggerClientEvent('chat:addMessage', -1, {
            color = { 120, 255, 120 },
            args  = { 'server', 'Reset complete. /pint start lastorders | /horde start | /chase start' },
        })
    end)
end, false)


-- ===== live positions + periodic state snapshots =====
-- The positions relay also drives the mate radar (it was lost in an earlier
-- rewrite, so the radar has been dead). On top of it, a state snapshot every
-- few seconds records the whole board - mode, mission, wave, and where everyone
-- was - so an overheard "the zombies are too fast" can be filed alongside the
-- exact situation that prompted it.
local positions = {}

RegisterNetEvent('telemetry:ping', function(pos)
    local source = source
    if type(pos) ~= 'table' or type(pos.x) ~= 'number' then return end

    positions[source] = {
        id = source, name = GetPlayerName(source) or ('#' .. tostring(source)),
        x = pos.x, y = pos.y, z = pos.z,
        v = pos.v and true or false,
        d = pos.d and true or false,
        at = os.time(),
    }
end)

AddEventHandler('playerDropped', function()
    positions[source] = nil
end)

CreateThread(function()
    while true do
        Wait(4000)

        local list = {}
        for _, p in pairs(positions) do
            list[#list + 1] = { id = p.id, name = p.name, x = p.x, y = p.y, z = p.z }
        end

        if #list > 0 then
            TriggerClientEvent('telemetry:mates', -1, list)
        end
    end
end)

-- Ask another resource for its state without caring whether it is running.
local function modeState(resource, fn)
    local ok, result = pcall(function()
        return exports[resource][fn]()
    end)
    return ok and result or nil
end

CreateThread(function()
    while true do
        Wait(8000)

        local now     = os.time()
        local players = {}

        for _, p in pairs(positions) do
            if (now - (p.at or 0)) < 20 then
                players[#players + 1] = {
                    name = p.name,
                    x = math.floor(p.x * 10) / 10,
                    y = math.floor(p.y * 10) / 10,
                    z = math.floor(p.z * 10) / 10,
                    v = p.v, d = p.d,
                }
            end
        end

        if #players > 0 then
            append({
                t       = now,
                kind    = 'state',
                horde   = modeState('infected', 'getState'),
                mission = modeState('pint', 'getState'),
                chase   = modeState('chase', 'getState'),
                players = players,
            })
        end
    end
end)
