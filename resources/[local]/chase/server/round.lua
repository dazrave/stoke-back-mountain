-- Round director. The server owns the phase, the clock, the fugitive's
-- identity and the sighting state; clients own eyes, blips and wheels.
local state = {
    phase          = 'idle', -- idle | headstart | active
    fugitive       = nil,    -- server id
    fugitiveName   = nil,
    headstartEndsAt = 0,
    endsAt         = 0,
    lastSeen       = nil,    -- vector3-ish table
    lastSeenAt     = 0,
    fugitivePos    = nil,    -- heartbeat, used only for the final alert
}

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

local function tell(message)
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 66, 150, 245 },
        args  = { 'chase', message },
    })
end

local function endRound(result)
    if state.phase == 'idle' then return end

    setState({ phase = 'idle' })
    TriggerClientEvent('chase:end', -1, result, state.fugitiveName)

    -- Hand the world back to the zombie stack.
    CreateThread(function()
        Wait(8000)
        if state.phase == 'idle' then
            StartResource('infected')
            StartResource('squadmate')
            Wait(1000)
            StartResource('pint')
        end
    end)

    local lines = {
        escaped  = ('%s got clean away. Drinks on the police budget.'):format(state.fugitiveName or '?'),
        arrested = ('%s got nicked. By the book.'):format(state.fugitiveName or '?'),
        shot     = 'You SHOT them. The chief is furious. Tyres, people. TYRES.',
        crashed  = 'The suspect and their bike parted company permanently. Case closes itself.',
        fled     = 'The fugitive left the server. Ultimate escape, technically.',
    }
    tell(lines[result] or 'Round over.')
end

local function start()
    if state.phase ~= 'idle' then return tell('Round already running. /chase stop first.') end

    local players = GetPlayers()
    if #players < 2 then return tell('Need at least 2 players: one rabbit, some hounds.') end

    -- The zombie stack owns the world (empty streets, fog, one-hit-kill).
    -- This mode needs a LIVING city, so it turns all that off - with the
    -- resource natives, because a script has no permission to run the console
    -- stop/ensure commands and those calls were being silently denied.
    StopResource('infected_dev')
    StopResource('pint')
    StopResource('infected')
    StopResource('squadmate')

    local fugitive = tonumber(players[math.random(#players)])
    local now      = GetGameTimer()

    setState({
        phase           = 'headstart',
        fugitive        = fugitive,
        fugitiveName    = GetPlayerName(fugitive),
        headstartEndsAt = now + Config.headstartSeconds * 1000,
        endsAt          = now + (Config.headstartSeconds + Config.roundSeconds) * 1000,
        lastSeen        = nil,
        lastSeenAt      = 0,
        fugitivePos     = nil,
    })

    local spawnIndex   = math.random(#Config.fugitive.spawns)
    local stationIndex = math.random(#Config.stations)
    local firstCop   = nil

    for _, src in ipairs(players) do
        local id = tonumber(src)
        if id ~= fugitive and not firstCop then firstCop = id end
    end

    -- Clear the yard first and give it a moment to actually happen, otherwise
    -- the new fleet spawns into last round's wreckage.
    TriggerClientEvent('chase:clearArea', -1, stationIndex)

    CreateThread(function()
        Wait(1500)

        for _, src in ipairs(players) do
            local id = tonumber(src)
            TriggerClientEvent('chase:role', id, {
                isFugitive   = (id == fugitive),
                fugitiveId   = fugitive,
                fugitiveName = state.fugitiveName,
                spawnIndex   = spawnIndex,
                stationIndex = stationIndex,
                spawnFleet   = (id == firstCop), -- exactly one client spawns the cars
            })
        end
    end)

    tell(('%s is the fugitive - stood right there. %ds head start and you can watch them go.'):format(
        state.fugitiveName, Config.headstartSeconds))
    tell('You CANNOT shoot them dead - shoot the tyres, corner them, drag them out, nick them.')
end

-- The tick: release the hounds, broadcast status, call time.
CreateThread(function()
    while true do
        Wait(1000)

        if state.phase ~= 'idle' then
            local now = GetGameTimer()

            if state.phase == 'headstart' and now >= state.headstartEndsAt then
                setState({ phase = 'active' })
                TriggerClientEvent('chase:release', -1)
                tell('Units released. Go get them.')
            end

            local remaining  = math.max(0, math.ceil((state.endsAt - now) / 1000))
            local finalAlert = state.phase == 'active' and remaining <= Config.finalAlertSeconds
            local tracking   = state.lastSeen ~= nil and (now - state.lastSeenAt) < Config.sight.holdMs

            -- During the head start the suspect is in plain sight: everyone
            -- watches which way they went, then the leash comes off.
            local headstart = state.phase == 'headstart'

            TriggerClientEvent('chase:status', -1, {
                phase        = state.phase,
                remaining    = remaining,
                headstart    = math.max(0, math.ceil((state.headstartEndsAt - now) / 1000)),
                fugitiveId   = state.fugitive,
                fugitiveName = state.fugitiveName,
                tracking     = tracking or finalAlert or headstart,
                trackPos     = (finalAlert or headstart) and state.fugitivePos
                    or (tracking and state.lastSeen or nil),
                lastKnown    = state.lastSeen,
                unseenFor    = state.lastSeen and math.floor((now - state.lastSeenAt) / 1000) or nil,
                finalAlert   = finalAlert,
            })

            if remaining <= 0 then
                endRound('escaped')
            end
        end
    end
end)

-- A cop laid eyes on the fugitive.
RegisterNetEvent('chase:see', function(coords)
    local source = source
    if state.phase ~= 'active' or source == state.fugitive then return end
    setState({ lastSeen = coords, lastSeenAt = GetGameTimer() })
end)

-- Fugitive position heartbeat; only ever shown during the final alert.
RegisterNetEvent('chase:heartbeat', function(coords)
    local source = source
    if source ~= state.fugitive then return end
    setState({ fugitivePos = coords })
end)

-- Breadcrumbs: stolen-car and witness reports, delivered late like a real
-- 999 call.
RegisterNetEvent('chase:report', function(kind, coords, label)
    local source = source
    if source ~= state.fugitive or state.phase ~= 'active' then return end

    local delay = kind == 'stolen' and Config.reports.stolenDelayMs or Config.reports.witnessDelayMs

    CreateThread(function()
        Wait(delay)
        if state.phase ~= 'active' then return end

        TriggerClientEvent('chase:ping', -1, kind, coords, label)
        tell(kind == 'stolen'
            and ('999 call: %s just got taken.'):format(label or 'a vehicle')
            or  ('999 call: reports of a collision, %s.'):format(label or 'somewhere'))
    end)
end)

RegisterNetEvent('chase:arrest', function()
    local source = source
    if state.phase ~= 'active' or source == state.fugitive then return end
    TriggerEvent('core:stat', source, 'arrests', 1) -- season scoreboard
    endRound('arrested')
end)

-- Gunfire can no longer finish the suspect, so a death here is the suspect's
-- own driving. The 'shot' ending is kept for the day someone finds a way.
RegisterNetEvent('chase:died', function(byCop)
    local source = source
    if source ~= state.fugitive or state.phase == 'idle' then return end
    endRound(byCop and 'shot' or 'crashed')
end)

AddEventHandler('playerDropped', function()
    local source = source
    if state.phase ~= 'idle' and source == state.fugitive then
        endRound('fled')
    end
end)

exports('getState', function()
    local tracking = state.lastSeen ~= nil
        and (GetGameTimer() - state.lastSeenAt) < Config.sight.holdMs

    return {
        phase    = state.phase,
        fugitive = state.fugitiveName,
        tracking = tracking and true or false,
    }
end)

RegisterCommand('chase', function(source, args)
    local action = args[1] or 'start'

    if action == 'start' then
        start()
    elseif action == 'stop' then
        endRound('escaped')
        tell('Round abandoned.')
    end
end, false)
