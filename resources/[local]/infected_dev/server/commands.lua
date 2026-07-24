-- Wave director controls, callable in-game so you do not need console access
-- while testing. Registered unrestricted deliberately - this is a private LAN
-- server and this whole resource is meant to be stopped for game night.
local function tell(source, message)
    TriggerClientEvent('chat:addMessage', source, {
        color = { 120, 200, 255 },
        args  = { 'infected', message },
    })
end

RegisterCommand('wave', function(source, args)
    local target = tonumber(args[1])

    if target then
        exports.infected:jumpToWave(target)
        tell(source, ('Jumped to wave %d.'):format(target))
        return
    end

    local started, err = exports.infected:forceNextWave()

    if not started then
        tell(source, 'Could not start next wave: ' .. tostring(err))
        return
    end

    tell(source, 'Next wave incoming.')
end, false)

RegisterCommand('horde', function(source, args)
    local action = args[1] or 'state'

    if action == 'start' then
        exports.infected:setRunning(true)
        tell(source, 'Director running.')

    elseif action == 'stop' then
        exports.infected:setRunning(false)
        TriggerClientEvent('infected:reset', -1)
        tell(source, 'Director stopped, horde cleared.')

    elseif action == 'reset' then
        exports.infected:resetAll()
        tell(source, 'Reset to wave 0.')

    else
        local state = exports.infected:getState()
        tell(source, ('running=%s wave=%d alive=%d kills=%d (%d/%d cleared this wave)')
            :format(tostring(state.running), state.wave, state.alive, state.kills, state.dead, state.spawned))
    end
end, false)
