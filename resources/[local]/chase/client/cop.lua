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

                -- Trace car to car, not ped to ped. The line-of-sight test
                -- ignores the two entities you name and nothing else, so with
                -- both people sat in vehicles the ray leaves through your own
                -- bodywork and arrives at theirs: BOTH cars block it. Sitting
                -- right on the suspect's bumper at 70mph therefore never
                -- counted as a sighting, which is why the map stayed blank for
                -- entire pursuits. Name the vehicles and the ray is clear.
                local myVehicle    = GetVehiclePedIsIn(me, false)
                local theirVehicle = GetVehiclePedIsIn(ped, false)
                local from = myVehicle ~= 0 and myVehicle or me
                local to   = theirVehicle ~= 0 and theirVehicle or ped

                if dist < range
                    and IsEntityOnScreen(to)
                    and HasEntityClearLosToEntity(from, to, 17) then
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
                    blips.nextPing = 0
                    blips.live = AddBlipForCoord(status.trackPos.x, status.trackPos.y, status.trackPos.z)
                    SetBlipSprite(blips.live, 161) -- crosshair-style target
                    SetBlipColour(blips.live, 1)
                    SetBlipScale(blips.live, 1.0)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString('Fugitive')
                    EndTextCommandSetBlipName(blips.live)
                end

                -- The further off they are, the staler the ping. Distance is
                -- measured to where we last plotted them, not to the truth,
                -- so a suspect who is genuinely miles away cannot be tracked
                -- any better by standing still and waiting for a fresh fix.
                local rate = Config.pingRate
                local me   = GetEntityCoords(PlayerPedId())
                local gap  = #(vector3(status.trackPos.x, status.trackPos.y, status.trackPos.z) - me)

                local span     = math.max(1.0, rate.farMetres - rate.nearMetres)
                local howFar   = math.min(1.0, math.max(0.0, (gap - rate.nearMetres) / span))
                local interval = rate.fastMs + (rate.slowMs - rate.fastMs) * howFar

                if GetGameTimer() >= (blips.nextPing or 0) then
                    blips.nextPing = GetGameTimer() + interval
                    SetBlipCoords(blips.live, status.trackPos.x, status.trackPos.y, status.trackPos.z)
                end

                SetBlipFlashes(blips.live, true)
                SetBlipRoute(blips.live, true) -- the GPS line
                SetBlipRouteColour(blips.live, 1)
                ShowHeadingIndicatorOnBlip(blips.live, false)

                -- A ring around them while we actually have eyes on, so the
                -- live lock reads differently from a cold last-known dot.
                if blips.ring and DoesBlipExist(blips.ring) then
                    -- Follows the plotted ping, not the live position, or the
                    -- ring would quietly give away the lag.
                    local at = GetBlipCoords(blips.live)
                    SetBlipCoords(blips.ring, at.x, at.y, at.z)
                else
                    blips.ring = AddBlipForRadius(
                        status.trackPos.x, status.trackPos.y, status.trackPos.z, 45.0)
                    SetBlipColour(blips.ring, 1)
                    SetBlipAlpha(blips.ring, 110)
                end

                if blips.search and DoesBlipExist(blips.search) then
                    RemoveBlip(blips.search)
                    blips.search = nil
                end
            elseif status.lastKnown then
                if blips.live and DoesBlipExist(blips.live) then
                    SetBlipCoords(blips.live, status.lastKnown.x, status.lastKnown.y, status.lastKnown.z)
                    SetBlipFlashes(blips.live, false)
                    SetBlipRoute(blips.live, true)

                    -- All they get once it goes cold: which way he went.
                    if status.lastHeading then
                        SetBlipRotation(blips.live, math.floor(status.lastHeading))
                        ShowHeadingIndicatorOnBlip(blips.live, true)
                    end
                end

                if blips.ring and DoesBlipExist(blips.ring) then
                    RemoveBlip(blips.ring)
                    blips.ring = nil
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
local function issueKit()
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    GiveWeaponToPed(ped, GetHashKey(Config.cop.weapon), Config.cop.ammo, false, true)
end

RegisterNetEvent('chase:release', function()
    local role = ChaseState()
    if role ~= 'cop' then return end

    issueKit()
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

-- Nothing stands between a copper and their own fleet.
--
-- A door lock lives on the VEHICLE and rides along with it, so anything that
-- ever locked a cruiser - a previous round, another mode, or a client that
-- meant to lock it only against itself - can leave the law stood outside their
-- own car while the suspect drives off. Same for an engine that never started
-- or a motor flagged undriveable. Assert the opposite every second, because
-- being unable to set off is the one failure that ends the round on its own.
local POLICE_MODELS = {}
for _, list in ipairs({ Config.cop.vehicles or {}, Config.ai.models or {} }) do
    for _, model in ipairs(list) do
        POLICE_MODELS[GetHashKey(model)] = true
    end
end

CreateThread(function()
    while true do
        Wait(1000)

        local role, status = ChaseState()

        if role == 'cop' and status.phase and status.phase ~= 'idle' then
            local ped = PlayerPedId()
            local me  = GetEntityCoords(ped)

            for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(vehicle)
                    and POLICE_MODELS[GetEntityModel(vehicle)]
                    and #(GetEntityCoords(vehicle) - me) < 40.0 then
                    SetVehicleDoorsLocked(vehicle, 1) -- 1 = unlocked
                    SetVehicleDoorsLockedForAllPlayers(vehicle, false)
                    SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false)
                end
            end

            -- And whatever we are sat behind the wheel of actually drives.
            local mine = GetVehiclePedIsIn(ped, false)

            if mine ~= 0 and GetPedInVehicleSeat(mine, -1) == ped then
                SetVehicleUndriveable(mine, false)

                if not GetIsVehicleEngineRunning(mine) then
                    SetVehicleEngineOn(mine, true, true, false)
                end
            end
        end
    end
end)

RegisterNetEvent('chase:end', clearBlips)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    clearBlips()
end)

-- ===== a copper is never out of the round =====
-- Nothing was putting dead police back on their feet. spawnmanager is what
-- normally does that, but chase stops `pint` for the duration and pint owns
-- the auto-spawn settings: it switches auto-spawn OFF while a mission runs
-- (mission deaths are final), and its spawn callback belongs to a resource
-- that is no longer running. So a cop who wrapped a cruiser round a lamppost
-- either lay there for the rest of the round or got dropped at a default
-- spawn point on the far side of the map. Take the decision off spawnmanager
-- and put people back ourselves, where they fell.
-- Guarded: a missing spawnmanager must never take this whole file down.
local function setAutoSpawn(enabled)
    pcall(function() exports.spawnmanager:setAutoSpawn(enabled) end)
end

RegisterNetEvent('chase:role', function()
    setAutoSpawn(false)
end)

-- Put it back ourselves. This used to rely on `pint` restarting seconds later
-- and re-enabling it, which is true when a round ends normally and false when
-- the round is torn down some other way - /resetgame stops chase outright, and
-- then nothing re-enabled it and dying in free roam left you on the floor.
-- Turning back on what we turned off is the resource's own job.
RegisterNetEvent('chase:end', function()
    setAutoSpawn(true)
end)

CreateThread(function()
    while true do
        Wait(500)

        local role, status = ChaseState()

        if role == 'cop' and Config.cop.respawn.enabled
            and status.phase and status.phase ~= 'idle' then
            local ped = PlayerPedId()

            if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
                ChaseHUD.notify('~r~You\'re down.~w~ Back on shift shortly.')
                Wait(Config.cop.respawn.delaySeconds * 1000)

                -- Check again: a death on the whistle must not haul somebody
                -- upright after the end-of-round shard has already played.
                role, status = ChaseState()

                if role == 'cop' and status.phase and status.phase ~= 'idle' then
                    local at = GetEntityCoords(PlayerPedId())

                    DoScreenFadeOut(400)
                    Wait(500)

                    -- Up where you fell rather than back at the nick: a chase
                    -- out at Paleto would otherwise end your round anyway, just
                    -- with a very long drive attached.
                    NetworkResurrectLocalPlayer(at.x, at.y, at.z + 1.0,
                        GetEntityHeading(PlayerPedId()), true, false)

                    local up = PlayerPedId()
                    ClearPedTasksImmediately(up)
                    SetEntityHealth(up, GetEntityMaxHealth(up))
                    ClearPedBloodDamage(up)
                    SetPlayerInvincible(PlayerId(), false)
                    issueKit()

                    DoScreenFadeIn(600)
                    ChaseHUD.notify('~b~Back on shift.~w~ Get after them.')
                end
            end
        end
    end
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


-- ===== your colleagues, in blue =====
-- Every other copper on the map. Chase turns off the mate radar that free roam
-- uses, so without this a cop can see the suspect and not a single one of the
-- people they are supposed to be coordinating with.
local mates = {}

CreateThread(function()
    while true do
        Wait(1000)

        local role, status = ChaseState()
        local show = role == 'cop' and status.phase and status.phase ~= 'idle'

        for _, id in ipairs(GetActivePlayers()) do
            local server = GetPlayerServerId(id)
            local ped    = GetPlayerPed(id)

            -- Not us, not the suspect, and only while we are actually on duty.
            local wanted = show
                and id ~= PlayerId()
                and server ~= status.fugitiveId
                and DoesEntityExist(ped)

            if wanted and not (mates[server] and DoesBlipExist(mates[server])) then
                local blip = AddBlipForEntity(ped)
                SetBlipSprite(blip, 1)
                SetBlipColour(blip, 3)   -- blue
                SetBlipScale(blip, 0.75)
                SetBlipAsShortRange(blip, false)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(GetPlayerName(id))
                EndTextCommandSetBlipName(blip)
                mates[server] = blip
            elseif not wanted and mates[server] and DoesBlipExist(mates[server]) then
                RemoveBlip(mates[server])
                mates[server] = nil
            end
        end
    end
end)

RegisterNetEvent('chase:end', function()
    for id, blip in pairs(mates) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        mates[id] = nil
    end
end)
