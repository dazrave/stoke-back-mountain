-- core: the universal death detector. Every death, in every mode, reported once
-- so the season scoreboard counts it — no mode has to wire anything up. Also
-- the trigger the AI director hangs its digs on.
CreateThread(function()
    local wasDead = false
    while true do
        Wait(400)
        local dead = IsEntityDead(PlayerPedId())
        if dead and not wasDead then
            wasDead = true
            TriggerServerEvent('core:died')
        elseif not dead then
            wasDead = false
        end
    end
end)
