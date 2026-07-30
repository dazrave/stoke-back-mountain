-- Getting dragged out of the car - GTA's angry-driver carjack, but reliable.
--
-- This deliberately runs on the VICTIM'S client. Asking a remote zombie to
-- perform a jack task depends on which machine owns that ped and on enter-
-- vehicle flag semantics that vary between builds; three attempts at it failed
-- silently. Your own client always owns your own ped, so ejecting you is the
-- one version of this that cannot fail. The zombies then swarm you on foot,
-- which the ordinary melee behaviour already handles.
local infectedHash

-- Decor first: it is set by whoever spawned the ped and survives the trip
-- across the network. The relationship-group check is only a fallback for
-- peds this client spawned itself.
local function isInfected(ped)
    if DecorExistOn(ped, 'SBM_INF') and DecorGetBool(ped, 'SBM_INF') then
        return true
    end

    if not infectedHash then
        infectedHash = GetHashKey(Config.relationshipGroup)
    end

    return GetPedRelationshipGroupHash(ped) == infectedHash
end

-- The campaign's refuel stage requires you to sit still at a pump, and the
-- hijack requires you to be moving to be safe. Left alone the two fight, and
-- the pump always loses: you get flung out every couple of seconds and the
-- tank never fills. Refuelling wins - the garrison that spawns at the pumps is
-- already the intended punishment for lingering.
local refuelling = false
AddEventHandler('pint:refuelling', function(on) refuelling = on and true or false end)

local function infectedOnTheDoors(vehicle)
    local at = GetEntityCoords(vehicle)

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsEntityDead(ped)
            and not IsPedAPlayer(ped)
            and isInfected(ped)
            and #(GetEntityCoords(ped) - at) < Config.hijack.radius then
            return true
        end
    end

    return false
end

-- Hauls the nearest infected to the driver's door. A pathfinding ped cannot
-- reliably catch a car, so once you have been dawdling with them nearby, one
-- of them simply arrives - the same relocation trick the horde already uses
-- when you outrun it. Without this the drag-out almost never triggered,
-- because nothing ever got within arm's reach of the vehicle.
local function summonToDoor(vehicle)
    local at      = GetEntityCoords(vehicle)
    local closest, closestDist

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsEntityDead(ped)
            and not IsPedAPlayer(ped) and isInfected(ped) then
            local dist = #(GetEntityCoords(ped) - at)

            if dist < Config.hijack.summonRange and (not closestDist or dist < closestDist) then
                closest, closestDist = ped, dist
            end
        end
    end

    if not closest then return false end

    NetworkRequestControlOfEntity(closest)

    local angle = math.random() * 6.2832
    SetEntityCoords(closest,
        at.x + math.cos(angle) * 2.5,
        at.y + math.sin(angle) * 2.5,
        at.z, false, false, false, false)

    ClearPedTasks(closest)
    return true
end

CreateThread(function()
    local clingMs    = 0
    local stallMs    = 0
    local nextSummon = 0
    local warned     = false

    while true do
        Wait(200)

        local grabbed = false

        if Survival.engaged and Config.hijack.enabled then
            local ped     = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 and not IsEntityDead(ped)
                and GetEntitySpeed(vehicle) < Config.hijack.maxSpeed then
                -- Slow, with company about? Then one of them reaches you.
                if not infectedOnTheDoors(vehicle) then
                    stallMs = stallMs + 200

                    if stallMs >= Config.hijack.stallMs and GetGameTimer() >= nextSummon then
                        stallMs    = 0
                        nextSummon = GetGameTimer() + Config.hijack.summonEvery
                        summonToDoor(vehicle)
                    end
                else
                    stallMs = 0
                end
            end

            if vehicle ~= 0 and not IsEntityDead(ped)
                and not refuelling
                and GetEntitySpeed(vehicle) < Config.hijack.maxSpeed
                and infectedOnTheDoors(vehicle) then
                grabbed  = true
                clingMs = clingMs + 200

                if not warned then
                    warned = true
                    HUD.notify('~r~THEY\'RE ON THE DOORS!~w~ Drive!')
                end

                if clingMs >= Config.hijack.grabMs then
                    clingMs = 0
                    warned  = false

                    -- Out you come. 4160 = flung out rather than a polite exit.
                    TaskLeaveVehicle(ped, vehicle, 4160)
                    SetPedToRagdoll(ped, 1200, 1200, 0, true, true, false)
                    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.3)
                    HUD.notify('~r~DRAGGED OUT.')
                end
            end
        end

        if not grabbed then
            clingMs = 0
            warned  = false
        end

        local inCar = GetVehiclePedIsIn(PlayerPedId(), false) ~= 0
        if not inCar then stallMs = 0 end
    end
end)
