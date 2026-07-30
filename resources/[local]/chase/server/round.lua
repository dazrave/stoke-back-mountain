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
    lastHeading    = nil,    -- degrees, the way they were going when last seen
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

-- Declared here, defined much further down. endRound puts a fresh round on
-- after a death, and a call to a `local function` that hasn't been declared yet
-- resolves to a global instead - nil at runtime, invisible to a syntax check,
-- and it would show up only as a round that never comes back.
local start

-- Hand the world back to the zombie stack.
local function handBackToTheZombies()
    Wait(8000)
    if state.phase ~= 'idle' then return end

    StartResource('infected')
    -- Squadmates are off (#18); see server.cfg. Restoring the mode
    -- stack after a chase must not quietly bring them back.
    -- StartResource('squadmate')
    Wait(1000)
    StartResource('pint')
end

-- The two endings that leave a body. Every other ending is tidy by its nature:
-- an arrest happens with the police stood over the suspect, an escape happens
-- on the whistle. A death happens wherever it happened - the suspect face down
-- at the bottom of a ravine, the fleet abandoned across half the map, everyone
-- else scattered and miles apart - and free roam simply inherited all of it,
-- with the fugitive left on the floor waiting on a backstop to peel them up.
local ENDS_IN_A_BODY = { shot = true, crashed = true }

-- Square one, then straight back out again. resetWorld() is telemetry's own
-- half of /resetgame: it bins the leftover cars and wrecks and puts everybody
-- back on their feet together in one place, the body included. Then the mode
-- goes again, which is what a death ought to mean - another go, not an evening
-- spent driving back from wherever the round died.
local function resetAndGoAgain()
    Wait(6000) -- let the end-of-round shard finish playing first
    if state.phase ~= 'idle' then return end

    tell('Putting everything back where it belongs. Then we go again.')
    pcall(function() exports.telemetry:resetWorld() end)

    Wait(7000) -- it fades everyone out, gathers them up and fades back in

    -- Somebody may have started a round by hand in the gap, and people do
    -- leave: with nobody left to chase, hand the city back instead.
    if state.phase ~= 'idle' then return end
    if #GetPlayers() < 2 then return handBackToTheZombies() end

    start()
end

local function endRound(result)
    if state.phase == 'idle' then return end

    setState({ phase = 'idle' })
    TriggerClientEvent('chase:end', -1, result, state.fugitiveName)
    TriggerClientEvent('core:heatSuppress', -1, false) -- free roam gets its police back

    CreateThread(ENDS_IN_A_BODY[result] and resetAndGoAgain or handBackToTheZombies)

    local lines = {
        escaped  = ('%s got clean away. Drinks on the police budget.'):format(state.fugitiveName or '?'),
        arrested = ('%s got nicked. By the book.'):format(state.fugitiveName or '?'),
        shot     = 'You SHOT them. The chief is furious. Tyres, people. TYRES.',
        crashed  = 'The suspect and their bike parted company permanently. Case closes itself.',
        fled     = 'The fugitive left the server. Ultimate escape, technically.',
    }
    tell(lines[result] or 'Round over.')
end

-- Assigns the local declared at the top of the file, so endRound can reach it.
function start()
    if state.phase ~= 'idle' then return tell('Round already running. /chase stop first.') end

    local players = GetPlayers()
    if #players < 2 then return tell('Need at least 2 players: one rabbit, some hounds.') end

    -- The only cops tonight are human, so mute core's scripted police heat -
    -- otherwise NPC units would gatecrash the manhunt.
    TriggerClientEvent('core:heatSuppress', -1, true)

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
        lastHeading     = nil,
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

    -- With no hold there is nothing to count down, and "0s head start" reads
    -- like something broke.
    if Config.headstartSeconds > 0 then
        tell(('%s is the fugitive - stood right there. %ds head start and you can watch them go.'):format(
            state.fugitiveName, Config.headstartSeconds))
    else
        tell(('%s is the fugitive - stood right there. GO.'):format(state.fugitiveName))
    end
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
                -- The suspect is always on the map now. Losing line of sight
                -- no longer freezes the dot at a last-known position; it just
                -- means the ping the police get is a stale one, and how stale
                -- is decided client-side by how far away they are.
                --
                -- `tracking` still means "eyes on" - the client uses it for
                -- the ring and the flashing - so the difference between a live
                -- lock and a cold trace is still visible at a glance.
                tracking     = tracking or finalAlert or headstart,
                trackPos     = state.fugitivePos or state.lastSeen,
                lastKnown    = state.lastSeen,
                lastHeading  = state.lastHeading,
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

    -- Which way they were travelling between the last two sightings. Once the
    -- trail goes cold this is all the police get, and it is the difference
    -- between searching a circle and searching the right half of one.
    local heading = state.lastHeading

    if state.lastSeen then
        local dx, dy = coords.x - state.lastSeen.x, coords.y - state.lastSeen.y
        if (dx * dx + dy * dy) > 4.0 then   -- ignore standing still
            heading = math.deg(math.atan(dx, -dy)) % 360.0
        end
    end

    setState({ lastSeen = coords, lastSeenAt = GetGameTimer(), lastHeading = heading })
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
