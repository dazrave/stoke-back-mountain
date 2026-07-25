-- core: free-roam chaos director. The mission "moments" (burning plane, zombie
-- ambulance, stampede, the bloke who turns) are too good to only fire during a
-- mission — /chaos lets them loose in free roam so hanging about is never
-- boring and always clip-worthy. Reuses the existing pint:moment handler.

local MOMENTS = {
    'planecrash', 'crashcar', 'runner', 'helicopter',
    'turning', 'ambulance', 'faller', 'stampede', 'tanker',
}

local on = false

RegisterCommand('chaos', function(source, args)
    on = (args[1] ~= 'off')
    TriggerClientEvent('chat:addMessage', -1, { color = { 200, 120, 66 },
        args = { 'chaos', on and 'Chaos on. Something is about to happen to somebody.' or 'Chaos off.' } })
end, false)

CreateThread(function()
    while true do
        Wait(math.random(45000, 90000))
        if on then
            local players = GetPlayers()
            if #players > 0 then
                local moment = MOMENTS[math.random(#MOMENTS)]
                TriggerClientEvent('pint:moment', tonumber(players[math.random(#players)]), moment)
                TriggerEvent('telemetry:mark', 'chaos:' .. moment)
            end
        end
    end
end)
