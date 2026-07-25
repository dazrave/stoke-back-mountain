-- core: free-roam event director. Two gears so hanging about is never dead but
-- also never exhausting:
--   ambient (default) - a gentle drip of plausible city events, always on, so
--                       walking around always has something going on nearby.
--   chaos  (/chaos)   - the full catalogue, cranked, for a set-piece.
-- Reuses the mission "moments" (pint:moment) that already exist client-side.

-- Gentle, non-apocalyptic events for the always-on layer.
local AMBIENT = { 'runner', 'faller', 'crashcar', 'helicopter' }

-- Everything, including the loud/zombie-flavoured ones, for chaos.
local FULL = {
    'planecrash', 'crashcar', 'runner', 'helicopter',
    'turning', 'ambulance', 'faller', 'stampede', 'tanker',
}

local mode = 'ambient' -- 'ambient' | 'chaos' | 'off'

local function say(msg)
    TriggerClientEvent('chat:addMessage', -1, { color = { 200, 120, 66 }, args = { 'director', msg } })
end

-- /chaos        -> crank it   | /chaos off -> back to gentle ambient
-- /chaos stop   -> silence everything
RegisterCommand('chaos', function(_, args)
    local a = args[1]
    if a == 'stop' then
        mode = 'off';      say('All events off. Eerie quiet.')
    elseif a == 'off' then
        mode = 'ambient';  say('Back to a gentle simmer.')
    else
        mode = 'chaos';    say('Chaos on. Something is about to happen to somebody.')
    end
end, false)

local function fire()
    local players = GetPlayers()
    if #players == 0 then return end
    local pool   = mode == 'chaos' and FULL or AMBIENT
    local moment = pool[math.random(#pool)]
    TriggerClientEvent('pint:moment', tonumber(players[math.random(#players)]), moment)
    TriggerEvent('telemetry:mark', mode .. ':' .. moment)
end

CreateThread(function()
    while true do
        -- Chaos comes thick and fast; ambient is a long, easy drip.
        local wait = mode == 'chaos' and math.random(45000, 90000)
            or math.random(150000, 300000)
        Wait(wait)
        if mode ~= 'off' then fire() end
    end
end)
