-- Cop brain: eyes, blips, arrest, loadout.
local blips = { live = nil, search = nil, searchRadius = 0, pings = {} }

local function clearBlips()
    if blips.live and DoesBlipExist(blips.live) then RemoveBlip(blips.live) end
    if blips.search and DoesBlipExist(blips.search) then RemoveBlip(blips.search) end
    for _, ping in ipairs(blips.pings) do
        if DoesBlipExist(ping.blip) then RemoveBlip(ping.blip) end
    end
    blips = { live = nil, search = nil, searchRadius = 0, pings = {} }
end

local function fugitivePed(status)
    if not status.fugitiveId then return nil end

    local playerId = GetPlayerFromServerId(status.fugitiveId)
    if playerId == -1 then return nil end

    local ped = GetPlayerPed(playerId)
    if not DoesEntityExist(ped) then return nil end

    return ped
end

-- Eyes: report a sighting when the fugitive is in range, on screen, and in
-- clear line of sight. The helicopter sees much further - that's its job.
CreateThread(function()
    while true do
        Wait(800)

        local role, status = ChaseState()

        if role == 'cop' and status.phase == 'active' then
            local ped = fugitivePed(status)

            if ped and not IsEntityDead(ped) then
                local me    = PlayerPedId()
                local dist  = #(GetEntityCoords(ped) - GetEntityCoords(me))
                local range = IsPedInAnyVehicle(me, false) and IsPedInFlyingVehicle(me)
                    and Config.sight.airRange or Config.sight.groundRange

                if dist < range
                    and IsEntityOnScreen(ped)
                    and HasEntityClearLosToEntity(me, ped, 17) then
                    TriggerServerEvent('chase:see', GetEntityCoords(ped))
                end
            end
        end
    end
end)

-- Map: live GPS lock while tracked, frozen last-seen dot plus a growing
-- search circle while hidden.
CreateThread(function()
    while true do
        Wait(500)

        local role, status = ChaseState()

        if role == 'cop' and status.phase and status.phase ~= 'idle' then
            if status.tracking and status.trackPos then
                if not blips.live or not DoesBlipExist(blips.live) then
                    blips.live = AddBlipForCoord(status.trackPos.x, status.trackPos.y, status.trackPos.z)
                    SetBlipSprite(blips.live, 161) -- crosshair-style target
                    SetBlipColour(blips.live, 1)
                    SetBlipScale(blips.live, 1.0)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString('Fugitive')
                    EndTextCommandSetBlipName(blips.live)
                end

                SetBlipCoords(blips.live, status.trackPos.x, status.trackPos.y, status.trackPos.z)
                SetBlipFlashes(blips.live, true)
                SetBlipRoute(blips.live, true) -- the GPS line
                SetBlipRouteColour(blips.live, 1)

                if blips.search and DoesBlipExist(blips.search) then
                    RemoveBlip(blips.search)
                    blips.search = nil
                end
            elseif status.lastKnown then
                if blips.live and DoesBlipExist(blips.live) then
                    SetBlipCoords(blips.live, status.lastKnown.x, status.lastKnown.y, status.lastKnown.z)
                    SetBlipFlashes(blips.live, false)
                    SetBlipRoute(blips.live, true)
                end

                -- The search area swells the longer they stay hidden.
                local radius = math.min(
                    Config.search.baseRadius + (status.unseenFor or 0) * Config.search.growPerSec,
                    Config.search.maxRadius)

                if math.abs(radius - blips.searchRadius) > 10.0
                    or not blips.search or not DoesBlipExist(blips.search) then
                    if blips.search and DoesBlipExist(blips.search) then RemoveBlip(blips.search) end

                    blips.search = AddBlipForRadius(
                        status.lastKnown.x, status.lastKnown.y, status.lastKnown.z, radius)
                    SetBlipColour(blips.search, 1)
                    SetBlipAlpha(blips.search, 80)
                    blips.searchRadius = radius
                end
            end

            -- Expire report pings.
            local kept = {}
            for _, ping in ipairs(blips.pings) do
                if GetGameTimer() < ping.expires then
                    kept[#kept + 1] = ping
                elseif DoesBlipExist(ping.blip) then
                    RemoveBlip(ping.blip)
                end
            end
            blips.pings = kept
        elseif blips.live or blips.search or #blips.pings > 0 then
            clearBlips()
        end
    end
end)

-- 999-call breadcrumbs on the map.
RegisterNetEvent('chase:ping', function(kind, coords, label)
    local role = ChaseState()
    if role ~= 'cop' then return end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, kind == 'stolen' and 225 or 161) -- 225 = car
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.85)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(kind == 'stolen' and 'Reported stolen' or 'Witness report')
    EndTextCommandSetBlipName(blip)

    blips.pings[#blips.pings + 1] = { blip = blip, expires = GetGameTimer() + Config.reports.pingLifeMs }
    ChaseHUD.notify(('~b~999:~w~ %s'):format(label or 'report received'))

    -- A report you can miss is a report that may as well not exist: alert
    -- tone, then the dispatch radio over the top of it.
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', true)
    PlayPoliceReport(kind == 'stolen' and 'CRIME_STOLEN_VEHICLE_01' or 'CRIME_RECKLESS_DRIVING_01', 0.0)
end)

-- Loadout on release, and the arrest.
RegisterNetEvent('chase:release', function()
    local role = ChaseState()
    if role ~= 'cop' then return end

    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    GiveWeaponToPed(ped, GetHashKey(Config.cop.weapon), Config.cop.ammo, false, true)
end)

CreateThread(function()
    while true do
        Wait(0)

        local role, status = ChaseState()

        if role == 'cop' and status.phase == 'active' then
            local ped = fugitivePed(status)
            local me  = PlayerPedId()

            if ped and not IsEntityDead(ped) and not IsPedInAnyVehicle(me, false) then
                local dist = #(GetEntityCoords(ped) - GetEntityCoords(me))

                if dist < Config.arrest.range and GetEntitySpeed(ped) < Config.arrest.maxSpeed then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('~INPUT_PICKUP~ Arrest')
                    EndTextCommandDisplayHelp(0, false, false, -1)

                    if IsControlJustReleased(0, 38) then
                        TriggerServerEvent('chase:arrest')
                    end
                end
            end
        else
            Wait(500)
        end
    end
end)

-- The helicopter's searchlight comes on automatically while flown.
CreateThread(function()
    while true do
        Wait(2000)

        local role = ChaseState()
        if role == 'cop' then
            local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
            if vehicle ~= 0 and IsThisModelAHeli(GetEntityModel(vehicle)) then
                SetVehicleSearchlight(vehicle, true, true)
            end
        end
    end
end)

RegisterNetEvent('chase:end', clearBlips)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    clearBlips()
end)

-- Unlimited ammunition for the law. Running dry mid-pursuit just stalls the
-- round; the interesting constraint here is catching them, not counting
-- rounds. Topped up rather than made infinite so the reload still happens.
CreateThread(function()
    while true do
        Wait(2000)

        local role, status = ChaseState()

        if role == 'cop' and status.phase and status.phase ~= 'idle' then
            local ped    = PlayerPedId()
            local weapon = GetHashKey(Config.cop.weapon)

            if HasPedGotWeapon(ped, weapon, false) then
                SetPedInfiniteAmmo(ped, true, weapon)
                SetPedInfiniteAmmoClip(ped, false) -- still reload, just never empty

                if GetAmmoInPedWeapon(ped, weapon) < Config.cop.ammo then
                    AddAmmoToPed(ped, weapon, Config.cop.ammo)
                end
            end
        end
    end
end)
