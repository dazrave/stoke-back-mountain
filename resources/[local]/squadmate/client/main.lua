-- Lifecycle: keep exactly one squadmate alive per player, wire up the order keys.
local state = { squad = nil }

local function setSquad(squad)
    state = { squad = squad }
end

-- Cross-file accessor (fetch.lua needs the live squad).
function ActiveSquad()
    return state.squad
end

local function giveOrder(orderName)
    if not Squad.isAlive(state.squad) then
        UI.notify('~r~Your squadmate is down. Press F10 to get a new one.')
        return
    end

    local squad, err = Orders.apply(state.squad, orderName)

    if err then
        print(('[squadmate] could not apply order "%s": %s'):format(orderName, err))
        UI.notify('~r~Order failed: ' .. err)
        return
    end

    setSquad(squad)
    UI.notify('~b~Squadmate: ~w~' .. Orders.definitions[orderName].label)
end

local function respawnSquadmate()
    Squad.despawn(state.squad)
    setSquad(nil)

    local squad, err = Squad.spawn()

    if not squad then
        print('[squadmate] spawn failed: ' .. tostring(err))
        UI.notify('~r~Could not spawn squadmate: ' .. tostring(err))
        return
    end

    setSquad(squad)
    UI.notify('~g~Squadmate deployed.')
end

-- Hand him a copy of whatever you are holding right now.
local function mirrorWeapon()
    if not Squad.isAlive(state.squad) then
        UI.notify('~r~Your squadmate is down. Press F10 to get a new one.')
        return
    end

    local weapon = GetSelectedPedWeapon(PlayerPedId())
    if weapon == GetHashKey('WEAPON_UNARMED') then
        UI.notify('~r~You are holding nothing. He is not copying that.')
        return
    end

    local ped = state.squad.ped
    RemoveAllPedWeapons(ped, true)
    GiveWeaponToPed(ped, weapon, Config.bot.ammo, false, true)
    SetPedFiringPattern(ped, GetHashKey('FIRING_PATTERN_FULL_AUTO'))

    UI.notify('~b~Squadmate:~w~ matching your loadout.')
end

for _, binding in ipairs(Config.keys) do
    RegisterCommand(binding.command, function()
        giveOrder(binding.order)
    end, false)
    RegisterKeyMapping(binding.command, binding.label, 'keyboard', binding.key)
end

RegisterCommand(Config.respawnCommand.command, respawnSquadmate, false)
RegisterKeyMapping(
    Config.respawnCommand.command,
    Config.respawnCommand.label,
    'keyboard',
    Config.respawnCommand.key
)

RegisterCommand(Config.mirrorCommand.command, mirrorWeapon, false)
RegisterKeyMapping(
    Config.mirrorCommand.command,
    Config.mirrorCommand.label,
    'keyboard',
    Config.mirrorCommand.key
)

AddEventHandler('playerSpawned', function()
    respawnSquadmate()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Squad.despawn(state.squad)
end)

-- Status readout with health. Also notices when the squadmate has died so the
-- player is told once, rather than silently losing their bot.
CreateThread(function()
    local reportedDown = false

    while true do
        if Squad.isAlive(state.squad) then
            reportedDown = false

            -- GTA peds sit on a 100-floor health scale, so percentage is
            -- (health - 100) / (max - 100).
            local ped     = state.squad.ped
            local span    = GetEntityMaxHealth(ped) - 100
            local current = math.max(0, GetEntityHealth(ped) - 100)
            local pct     = span > 0 and math.floor(current / span * 100) or 0
            local colour  = pct > 60 and '~g~' or (pct > 30 and '~y~' or '~r~')

            UI.drawStatus(('SQUADMATE: %s  %s%d%%'):format(
                Orders.definitions[state.squad.order].label, colour, pct))
        elseif state.squad and not reportedDown then
            reportedDown = true
            UI.notify('~r~Your squadmate is down. Press ' .. Config.respawnCommand.key .. ' for a new one.')
        end

        Wait(0)
    end
end)

-- Cover the case where the resource is hot-reloaded mid-session: there is no
-- playerSpawned event coming, so deploy immediately if we are already in game.
CreateThread(function()
    Wait(1000)
    if not Squad.isAlive(state.squad) and NetworkIsPlayerActive(PlayerId()) then
        respawnSquadmate()
    end
end)

-- Follow behaviour ON FOOT. Group membership alone does not reliably make a
-- CreatePed'd network ped physically follow its leader in FiveM, so the task
-- is issued and re-issued whenever he drifts past his formation spacing.
-- Gated off entirely when either of you is in a vehicle - the vehicle thread
-- below owns that situation.
CreateThread(function()
    local FOLLOW_SPEED = 3.0

    while true do
        Wait(500)

        local squad = state.squad
        if Squad.isAlive(squad) and Orders.definitions[squad.order].inGroup then
            local ped    = squad.ped
            local player = PlayerPedId()

            if not IsPedShooting(ped)
                and GetVehiclePedIsIn(player, false) == 0
                and GetVehiclePedIsIn(ped, false) == 0
                and not (FetchBusy and FetchBusy()) then
                local spacing = Config.group.spacing[Orders.definitions[squad.order].spacing]
                local dist    = #(GetEntityCoords(ped) - GetEntityCoords(player))

                if dist > spacing + 2.0 then
                    TaskFollowToOffsetOfEntity(
                        ped, player,
                        0.0, -spacing, 0.0,
                        FOLLOW_SPEED,
                        -1,
                        spacing,
                        true
                    )
                end
            end
        end
    end
end)

-- Vehicle etiquette: you get in, he gets in the first free seat; you get out,
-- he gets out. NO warping: if you drive off while he is still fumbling with
-- the door handle, he chases the car for as long as his legs and the horde
-- allow. If he's left behind, he's left behind.
CreateThread(function()
    local enterSince = nil

    while true do
        Wait(600)

        local squad = state.squad
        if Squad.isAlive(squad) and Orders.definitions[squad.order].inGroup then
            local ped    = squad.ped
            local player = PlayerPedId()
            local myVeh  = GetVehiclePedIsIn(player, false)
            local hisVeh = GetVehiclePedIsIn(ped, false)

            if myVeh ~= 0 and hisVeh ~= myVeh and not (FetchBusy and FetchBusy()) then
                local seat = nil
                for candidate = 0, GetVehicleMaxNumberOfPassengers(myVeh) - 1 do
                    if IsVehicleSeatFree(myVeh, candidate) then
                        seat = candidate
                        break
                    end
                end

                -- Re-issue every so often: the task itself makes him chase the
                -- vehicle, so a moving car means a running squadmate behind it.
                -- Timeout MUST be -1: any positive timeout WARPS the ped into
                -- the seat when it expires, which is exactly what we don't want.
                if seat ~= nil and (not enterSince or (GetGameTimer() - enterSince) > 8000) then
                    enterSince = GetGameTimer()
                    TaskEnterVehicle(ped, myVeh, -1, seat, 2.0, 1, 0)
                end
            else
                enterSince = nil

                if myVeh == 0 and hisVeh ~= 0 then
                    TaskLeaveVehicle(ped, hisVeh, 0)
                end
            end
        else
            enterSince = nil
        end
    end
end)

-- Slow health trickle. The horde targets him too; this lets him recover
-- between waves while damage still outpaces it inside a fight.
CreateThread(function()
    while true do
        Wait(1000)

        local squad = state.squad
        if Squad.isAlive(squad) then
            local ped    = squad.ped
            local health = GetEntityHealth(ped)
            local max    = GetEntityMaxHealth(ped)

            if health < max then
                SetEntityHealth(ped, math.min(max, health + Config.bot.regenPerSecond))
            end
        end
    end
end)
