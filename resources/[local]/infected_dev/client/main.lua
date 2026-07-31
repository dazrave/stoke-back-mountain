-- Command surface for solo testing. Everything here is client-side, so it only
-- ever affects the person who typed it.
local say = SBM.notify

local function onOff(value)
    return value and '~g~ON' or '~r~OFF'
end

RegisterCommand('god', function()
    say('God mode: ' .. onOff(Tools.toggleGod()))
end, false)

RegisterCommand('noclip', function()
    say('Noclip: ' .. onOff(Noclip.toggle()) .. ' ~w~(Q/E up-down, wheel for speed)')
end, false)

RegisterCommand('dbg', function()
    say('Zombie labels: ' .. onOff(Overlay.toggle()))
end, false)

RegisterCommand('perf', function()
    say('Perf readout: ' .. onOff(Perf.toggle()))
end, false)

RegisterCommand('guns', function()
    say(('~g~Loadout given (%d weapons).'):format(Tools.giveLoadout()))
end, false)

RegisterCommand('slow', function(_, args)
    say(('Timescale: ~y~%.2f'):format(Tools.setTimescale(args[1] or 1.0)))
end, false)

-- Spawning goes via an event, not an export: it yields internally and exports
-- cannot yield. The count comes back asynchronously on spawnResult.
AddEventHandler('infected:dev:spawnResult', function(spawned, err)
    if err then
        say('~r~Spawn stopped: ' .. err)
        return
    end
    say(('~g~Spawned %d'):format(spawned))
end)

-- Spawn a specific archetype right next to you. This is how you inspect the
-- stalker trigger without waiting for a wave to wander over.
RegisterCommand('here', function(_, args)
    local archetype = args[1] or 'stalker'
    local count     = tonumber(args[2]) or 1

    if not ({ shambler = true, runner = true, stalker = true })[archetype] then
        say('~r~Unknown type. Use: shambler, runner or stalker.')
        return
    end

    TriggerEvent('infected:dev:spawnHere', archetype, count, 12.0)
end, false)

-- Deliberately overshoot to find the ceiling. Watch /perf while it runs.
RegisterCommand('stress', function(_, args)
    local count = math.min(tonumber(args[1]) or 40, 200)

    say(('~y~Stress test: spawning %d...'):format(count))
    TriggerEvent('infected:dev:spawnHere', 'runner', count, 30.0)
end, false)

AddEventHandler('infected:dev:clipsetResult', function(applied, err)
    if err then
        say('~r~' .. err)
        return
    end
    say(('~g~Walk applied to %d infected.'):format(applied))
end)

-- Audition zombie walks live. /clipset with no argument lists the options.
RegisterCommand('clipset', function(_, args)
    local key = args[1]

    if not key then
        local keys = exports.infected:getClipsetKeys()
        say('~y~Walks: ~w~' .. table.concat(keys, ', '))
        return
    end

    TriggerEvent('infected:dev:setClipset', key)
end, false)

RegisterCommand('clearmine', function()
    say(('~y~Cleared %d of my infected.'):format(exports.infected:clearLocal()))
end, false)

RegisterCommand('tp', function(_, args)
    local name = args[1]

    if not name then
        local names = {}
        for key in pairs(Tools.locations) do names[#names + 1] = key end
        say('~y~Locations: ~w~' .. table.concat(names, ', '))
        return
    end

    local target, err = Tools.teleport(name)

    if not target then
        say('~r~' .. err)
        return
    end

    say('~g~Teleported to ' .. name)
end, false)

RegisterKeyMapping('noclip', 'Dev: toggle noclip',       'keyboard', 'F2')
RegisterKeyMapping('dbg',    'Dev: toggle zombie labels', 'keyboard', 'F3')
RegisterKeyMapping('perf',   'Dev: toggle perf readout',  'keyboard', 'F4')

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    SetTimeScale(1.0)

    if Noclip.isEnabled() then Noclip.toggle() end
    if Tools.isGod()      then Tools.toggleGod() end
end)

CreateThread(function()
    Wait(3000)
    say('~b~infected_dev loaded. ~w~/god /noclip /dbg /perf /guns /here /stress /wave /tp')
end)

-- When the dev tools are stopped for game night, nobody keeps their cheats.
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetGravityLevel(0)
end)
