-- Position sampler: one fix every few seconds, shipped to the server in small
-- batches. Cheap enough to forget it exists.
local SAMPLE_MS  = 3000
local BATCH_SIZE = 7

local buffer = {}

CreateThread(function()
    while true do
        Wait(SAMPLE_MS)

        if NetworkIsPlayerActive(PlayerId()) then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)

            buffer[#buffer + 1] = {
                x = math.floor(pos.x * 10) / 10,
                y = math.floor(pos.y * 10) / 10,
                z = math.floor(pos.z * 10) / 10,
                s = math.floor(GetEntitySpeed(ped) * 10) / 10, -- m/s
                v = IsPedInAnyVehicle(ped, false) and 1 or 0,
                d = IsEntityDead(ped) and 1 or 0,
            }

            if #buffer >= BATCH_SIZE then
                TriggerServerEvent('telemetry:batch', buffer)
                buffer = {}
            end
        end
    end
end)

-- Part of /resetgame: everyone gets a clean respawn at a normal map spawn.
RegisterNetEvent('telemetry:respawn', function(at, index)
    DoScreenFadeOut(400)
    Wait(500)

    exports.spawnmanager:setAutoSpawn(true)

    if at then
        -- Fan out around the shared point so three people don't land inside
        -- each other, but stay close enough to see who you're with.
        local angle = ((index or 1) - 1) * 1.7

        exports.spawnmanager:spawnPlayer({
            x        = at.x + math.cos(angle) * 4.5,
            y        = at.y + math.sin(angle) * 4.5,
            z        = at.z,
            heading  = at.h or 0.0,
            model    = GetEntityModel(PlayerPedId()),
            skipFade = true,
        })

        -- Settle onto the ground once collision has streamed in.
        Wait(900)
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 30.0, false)
        if found then
            SetEntityCoords(ped, pos.x, pos.y, groundZ + 1.0, false, false, false, false)
        end
    else
        exports.spawnmanager:spawnPlayer()
        Wait(900)
    end

    DoScreenFadeIn(600)
end)

-- ===== mate radar =====
-- In free roam (no mission, no horde, no chase round) every human shows as a
-- dot on the map. Positions are relayed through the server so mates show up
-- at ANY distance, not just network scope.
local mates    = {}
local blips    = {}
local engaged  = false
local inChase  = false

RegisterNetEvent('infected:engaged', function(on) engaged = on and true or false end)
RegisterNetEvent('chase:role', function() inChase = true end)
RegisterNetEvent('chase:end', function() inChase = false end)

CreateThread(function()
    while true do
        Wait(4000)

        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        TriggerServerEvent('telemetry:ping', {
            x = pos.x, y = pos.y, z = pos.z,
            v = GetVehiclePedIsIn(ped, false) ~= 0, -- in a vehicle
            d = IsEntityDead(ped),                  -- down / dead
        })
    end
end)

RegisterNetEvent('telemetry:mates', function(list)
    mates = list or {}
end)

CreateThread(function()
    while true do
        Wait(2000)

        local me   = GetPlayerServerId(PlayerId())
        local show = not engaged and not inChase
        local seen = {}

        if show then
            for _, mate in ipairs(mates) do
                if mate.id ~= me then
                    seen[mate.id] = true

                    if not blips[mate.id] or not DoesBlipExist(blips[mate.id]) then
                        local blip = AddBlipForCoord(mate.x, mate.y, mate.z)
                        SetBlipSprite(blip, 1)
                        SetBlipColour(blip, 3)
                        SetBlipScale(blip, 0.85)
                        BeginTextCommandSetBlipName('STRING')
                        AddTextComponentString(mate.name or 'Mate')
                        EndTextCommandSetBlipName(blip)
                        blips[mate.id] = blip
                    end

                    SetBlipCoords(blips[mate.id], mate.x, mate.y, mate.z)
                end
            end
        end

        for id, blip in pairs(blips) do
            if not seen[id] then
                if DoesBlipExist(blip) then RemoveBlip(blip) end
                blips[id] = nil
            end
        end
    end
end)

-- Part of /resetgame: bin every empty vehicle nearby, which clears mission
-- wrecks, spawned bangers and anything orphaned by an earlier session.
-- Ambient traffic repopulates on its own within seconds.
RegisterNetEvent('telemetry:clearworld', function()
    local cleared = 0

    -- Bodies first: corpses at mission points were surviving every restart.
    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            NetworkRequestControlOfEntity(ped)
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
            cleared = cleared + 1
        end
    end

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle)
            and IsVehicleSeatFree(vehicle, -1)
            and GetVehicleNumberOfPassengers(vehicle) == 0 then
            NetworkRequestControlOfEntity(vehicle)
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteEntity(vehicle)
            cleared = cleared + 1
        end
    end

    print(('[telemetry] cleared %d empty vehicles'):format(cleared))
end)

-- Who's on. Top-left, always, so you know who you're playing with without
-- opening the pause menu.
CreateThread(function()
    while true do
        Wait(0)

        local me = GetPlayerServerId(PlayerId())
        local y  = 0.020

        SetTextFont(4)
        SetTextScale(0.30, 0.30)
        SetTextColour(255, 220, 120, 220)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName('~y~STOKEBACK MOUNTAIN')
        EndTextCommandDisplayText(0.015, y)

        y = y + 0.024

        for _, mate in ipairs(mates) do
            SetTextFont(4)
            SetTextScale(0.28, 0.28)
            SetTextColour(255, 255, 255, 200)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(
                (mate.id == me and '~g~' or '~w~') .. (mate.name or '?'))
            EndTextCommandDisplayText(0.015, y)

            y = y + 0.022
        end
    end
end)
