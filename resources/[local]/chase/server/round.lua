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

-- Air support announces itself once a round, when the helicopter is actually
-- up. Kept out of `state` on purpose: it is a fact about the chat log, not
-- about the round, and the fugitive's client is what decides when it's true.
local airborneAnnounced = false

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

    -- What comes back (and what stays off - squadmates, #18) is core's
    -- call, not this mode's: the stack is data in core/server/modes.lua.
    exports.core:releaseWorld()
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
        shaken   = ('%s shook the tail. A full minute, no eyes, no lock, no ping. Textbook.'):format(state.fugitiveName or '?'),
        arrested = ('%s got nicked. By the book.'):format(state.fugitiveName or '?'),
        shot     = 'You SHOT them. The chief is furious. Tyres, people. TYRES.',
        crashed  = 'The suspect and their bike parted company permanently. Case closes itself.',
        fled     = 'The fugitive left the server. Ultimate escape, technically.',
    }
    tell(lines[result] or 'Round over.')
end

-- ===== whose turn it is =====
-- Everyone gets a go, in order, and nobody does it twice on the bounce.
--
-- Two things were quietly wiping this memory, and both are routine (#51).
--
-- The first: this whole block used to sit INSIDE start(), so `lastFugitive`
-- was a fresh local on every single round. It was nil every time the rota came
-- to read it, which meant the "first suspect of the night is random" branch was
-- the only branch that ever ran. The rota was a coin toss wearing a rota's
-- clothes, and somebody could absolutely go twice on the bounce.
--
-- The second: PUSH LIVE restarts this resource several times an evening, which
-- takes any in-memory answer with it. So it is written to disk. It is kept by
-- NAME rather than by server id, because ids are handed out fresh on every
-- reconnect and would not survive either.
local ROTA_FILE = '.last-fugitive'

local function rememberFugitive(name)
    if not name or name == '' then return end
    SaveResourceFile(GetCurrentResourceName(), ROTA_FILE, name, -1)
end

local function whoWentLast()
    local stored = LoadResourceFile(GetCurrentResourceName(), ROTA_FILE)
    if not stored or stored == '' then return nil end
    return stored
end

local function nextFugitive(players)
    local roster = {}
    for _, src in ipairs(players) do
        local id = tonumber(src)
        if id then roster[#roster + 1] = { id = id, name = GetPlayerName(id) } end
    end

    if #roster == 0 then return nil end

    -- Sorted so the order is the same every round rather than following
    -- whatever order GetPlayers happened to return.
    table.sort(roster, function(a, b) return a.id < b.id end)

    local previous = whoWentLast()
    local at = nil

    for index, player in ipairs(roster) do
        if player.name == previous then at = index break end
    end

    -- Nobody here went last: first round of the night, or they have since left.
    -- Draw at random so the rota doesn't always open with whoever happens to
    -- hold the lowest server id. Otherwise it is strictly the next one along,
    -- which is what makes going twice in a row impossible rather than unlikely.
    local pick = at and roster[(at % #roster) + 1] or roster[math.random(#roster)]

    rememberFugitive(pick.name)
    return pick.id
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
    -- This mode needs a living city, so it claims the world and core stops
    -- everything else.
    exports.core:claimWorld('chase')

    local fugitive = nextFugitive(players)
    local now      = GetGameTimer()

    airborneAnnounced = false

    -- A fresh table, NOT setState. setState merges with pairs(), and a key
    -- written as nil in a table constructor is simply absent - pairs() never
    -- sees it, so `lastSeen = nil` through the merge KEPT last round's final
    -- sighting. Combined with lastSeenAt going back to 0, the shake-off clock
    -- then read "spotted hours ago" the moment round two went active and ended
    -- it on the spot - one good game, then every round after it instantly
    -- called as a getaway (#52). A new round is a new state, not a patch on
    -- the old one.
    state = {
        phase           = 'headstart',
        fugitive        = fugitive,
        fugitiveName    = GetPlayerName(fugitive),
        -- Provisional. The real countdown is started further down, once
        -- everybody has actually been placed - roles go out 1.5s from here and
        -- a client can spend another 2.5s waiting for collision, so counting
        -- from this moment had the countdown most of the way through before
        -- anyone could see it. Seeded long so nothing releases early if the
        -- setup below ever fails.
        headstartEndsAt = now + 60000,
        endsAt          = now + (Config.readySeconds + Config.headstartSeconds + Config.roundSeconds) * 1000,
        lastSeen        = nil,
        lastSeenAt      = 0,
        lastHeading     = nil,
        fugitivePos     = nil,
    }

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

        -- Everyone has their role and has had time to be stood up. NOW start
        -- counting, so the number on screen is the whole head start rather
        -- than whatever was left of it by the time the world loaded.
        Wait(Config.readySeconds * 1000)

        if state.phase == 'headstart' then
            local from = GetGameTimer()
            setState({
                headstartEndsAt = from + Config.headstartSeconds * 1000,
                endsAt          = from + (Config.headstartSeconds + Config.roundSeconds) * 1000,
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

    if Config.shakeOff.enabled then
        tell(('Once they have been spotted, %d seconds with nobody laying eyes on them and they have won.'):format(
            Config.shakeOff.seconds))
    end
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

            -- The shake-off clock. Runs only once they have actually been
            -- spotted, and stops dead during the citywide alert - the whole
            -- city has a live trace by then, so "nobody has seen me" would be
            -- a lie the scoreboard shouldn't reward.
            local shakeIn = nil

            -- lastSeenAt > 0 as well as lastSeen: the pair must be from THIS
            -- round. Belt and braces against any future path that leaves one
            -- half stale - a zero timestamp read as "spotted at server boot"
            -- is exactly what was ending rounds at the whistle.
            if Config.shakeOff.enabled and state.phase == 'active'
                and state.lastSeen and state.lastSeenAt > 0 and not finalAlert then
                shakeIn = math.max(0, math.ceil(
                    (Config.shakeOff.seconds * 1000 - (now - state.lastSeenAt)) / 1000))
            end

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
                shakeIn      = shakeIn,
            })

            -- Losing them outright ends it before the clock does.
            if shakeIn == 0 then
                endRound('shaken')
            elseif remaining <= 0 then
                endRound('escaped')
            end
        end
    end
end)

-- Somebody has eyes on the suspect. Shared by the coppers on the ground and by
-- the helicopter, because a sighting is a sighting: it refreshes the lock and
-- it sets the direction of travel.
local function recordSighting(coords)
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
end

-- A cop laid eyes on the fugitive.
RegisterNetEvent('chase:see', function(coords)
    local source = source
    if state.phase ~= 'active' or source == state.fugitive then return end

    recordSighting(coords)
end)

-- The helicopter has them. This is the exact opposite check to `chase:see`:
-- air support is an NPC flown by the suspect's own client (see client/heli.lua
-- for why), so the ONLY machine allowed to report it is the one `chase:see`
-- refuses to listen to.
--
-- Trusting the fugitive's client with this costs nothing. It gains them
-- nothing to lie in either direction, and the client already reports its own
-- position every second through `chase:heartbeat` regardless.
RegisterNetEvent('chase:airEyes', function(coords)
    local source = source
    if state.phase ~= 'active' or source ~= state.fugitive then return end

    recordSighting(coords)
end)

-- Air support is up. Said once, and only when the helicopter genuinely exists,
-- so the line is never a promise the round doesn't keep.
RegisterNetEvent('chase:airborne', function()
    local source = source
    if state.phase ~= 'active' or source ~= state.fugitive then return end
    if airborneAnnounced then return end

    airborneAnnounced = true
    tell('Air support is up. That helicopter is why the suspect keeps showing on your map.')
    tell('Get under something and the lock goes cold - bridges, tunnels, the multi-storeys.')
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
