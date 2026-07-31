-- AI police units.
--
-- Spawned by the FUGITIVE'S own client, deliberately: that machine owns the
-- area the action is happening in, so the units always exist where they
-- matter and their driving AI runs locally instead of at the mercy of entity
-- ownership.
--
-- They're armed, and that's safe: the fugitive's health floor means NPC
-- gunfire can never end the round, only sting. Their aggression is aimed
-- through the chase task, so they shoot at the suspect they are chasing
-- rather than declaring war on the human coppers as well.
local units = {}

local loadModel = SBM.loadModel

local function despawn(unit)
    if unit.ped and DoesEntityExist(unit.ped) then
        SetEntityAsMissionEntity(unit.ped, true, true)
        DeleteEntity(unit.ped)
    end
    if unit.vehicle and DoesEntityExist(unit.vehicle) then
        SetEntityAsMissionEntity(unit.vehicle, true, true)
        DeleteEntity(unit.vehicle)
    end
end

local function clearAll()
    for _, unit in ipairs(units) do despawn(unit) end
    units = {}
end

RegisterNetEvent('chase:end', clearAll)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    clearAll()
end)

-- Finds a bit of road to come screaming out of, far enough away that they
-- don't simply appear in the mirror.
-- The nearest nick, if one is close enough to plausibly have sent the car.
local function nearestStation(from)
    local best, bestDist = nil, nil

    for _, station in ipairs(Config.stations or {}) do
        local distance = #(vector3(from.x, from.y, from.z) - station.pos)
        if distance <= Config.ai.stationRange and (not bestDist or distance < bestDist) then
            best, bestDist = station, distance
        end
    end

    return best
end

-- A road node just outside a station. Sampled around it rather than at it,
-- because the station coordinate is the building and cars spawned there end up
-- in the lobby.
local function stationPoint(from)
    local station = nearestStation(from)
    if not station then return nil end

    for _ = 1, 8 do
        local angle = math.random() * 6.2832
        local out   = 25.0 + math.random() * 35.0

        local ok, node, heading = GetClosestVehicleNodeWithHeading(
            station.pos.x + math.cos(angle) * out,
            station.pos.y + math.sin(angle) * out,
            station.pos.z, 1, 3.0, 0)

        if ok then return node, heading end
    end

    return nil
end

local function approachPoint(from)
    for _ = 1, 8 do
        local angle    = math.random() * 6.2832
        local distance = Config.ai.spawnDistance[1]
            + math.random() * (Config.ai.spawnDistance[2] - Config.ai.spawnDistance[1])

        local x = from.x + math.cos(angle) * distance
        local y = from.y + math.sin(angle) * distance

        local ok, node, heading = GetClosestVehicleNodeWithHeading(x, y, from.z, 1, 3.0, 0)
        if ok then
            return node, heading
        end
    end

    return nil
end

-- The suspect's ped, resolved from the server's id rather than assumed to be
-- whoever is holding this keyboard. These units are only ever spawned on the
-- fugitive's own client, so PlayerPedId() was right - but it was right by
-- accident, and anything that ever runs this elsewhere would have had NPC
-- police hunting a copper. Naming the target explicitly makes that impossible
-- rather than merely unlikely.
local function fugitivePed()
    local _, status = ChaseState()
    local id = status and status.fugitiveId

    if id then
        local player = GetPlayerFromServerId(id)
        if player ~= -1 then
            local ped = GetPlayerPed(player)
            if ped and ped ~= 0 and DoesEntityExist(ped) then return ped end
        end
    end

    return nil
end

local function spawnUnit(me)
    -- Out of a nick where there is one in range; otherwise the old behaviour,
    -- so a chase in the hills still gets police at all.
    local node, heading
    if Config.ai.fromStations then
        node, heading = stationPoint(me)
    end
    if not node then
        node, heading = approachPoint(me)
    end
    if not node then return end

    local carHash = loadModel(Config.ai.models[math.random(#Config.ai.models)])
    local copHash = loadModel(Config.ai.driver)
    if not carHash or not copHash then return end

    local vehicle = CreateVehicle(carHash, node.x, node.y, node.z + 0.5, heading, true, true)
    SetModelAsNoLongerNeeded(carHash)
    if not DoesEntityExist(vehicle) then return end

    SetEntityRotation(vehicle, 0.0, 0.0, heading, 2, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleSiren(vehicle, true)
    SetVehicleHasMutedSirens(vehicle, false)
    SetVehicleTyresCanBurst(vehicle, true)
    SetVehicleWheelsCanBreak(vehicle, true)
    SetEntityProofs(vehicle, false, false, false, false, false, false, false, false)
    SetVehicleEngineOn(vehicle, true, true, false)

    -- Same cap as the players, or the cruisers either cannot keep up or walk
    -- away from everyone.
    if Config.matchedSpeed.enabled then
        SetVehicleMaxSpeed(vehicle, Config.matchedSpeed.mps)
    end

    local driver = CreatePedInsideVehicle(vehicle, 26, copHash, -1, true, true)
    SetModelAsNoLongerNeeded(copHash)

    if not DoesEntityExist(driver) then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteEntity(vehicle)
        return
    end

    if Config.ai.invincible then
        SBM.hardenPed(driver) -- proofs included: fall damage is COLLISION damage
        SetPedCanRagdollFromPlayerImpact(driver, false)
    end

    -- Fearless, and a genuinely good driver. Armed only if configured.
    RemoveAllPedWeapons(driver, true)

    if Config.ai.armed then
        GiveWeaponToPed(driver, GetHashKey(Config.ai.weapon), 250, false, true)
        SetPedInfiniteAmmo(driver, true, GetHashKey(Config.ai.weapon))
        SetPedAccuracy(driver, Config.ai.accuracy)
        SetPedFiringPattern(driver, GetHashKey('FIRING_PATTERN_BURST_FIRE_DRIVEBY'))
    end

    SetPedFleeAttributes(driver, 0, false)
    SetPedCombatAttributes(driver, 46, true) -- always fight
    -- 2 is "lean out and shoot", which an unarmed copper can only mime.
    SetPedCombatAttributes(driver, 2, Config.ai.armed and true or false)
    SetPedCombatAttributes(driver, 3, true)  -- will get out and give chase on foot

    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 1.0)
    SetPedKeepTask(driver, true)

    TaskVehicleChase(driver, fugitivePed() or PlayerPedId())

    units[#units + 1] = { vehicle = vehicle, ped = driver, at = GetGameTimer() }
end

CreateThread(function()
    local nextSpawn = 0

    while true do
        Wait(1000)

        local role, status = ChaseState()
        local hunting = Config.ai.enabled
            and role == 'fugitive'
            and status.phase == 'active'

        -- Not the suspect? Then this client has no business running police.
        -- Any unit left over from a previous role goes now, rather than
        -- circling whoever happens to be standing here.
        if not hunting and #units > 0 then
            for _, unit in ipairs(units) do despawn(unit) end
            units = {}
        end

        if hunting then
            local me  = GetEntityCoords(PlayerPedId())
            local now = GetGameTimer()

            -- Bin units that have lost you, crashed out, or died.
            local kept = {}
            for _, unit in ipairs(units) do
                local alive = unit.vehicle and DoesEntityExist(unit.vehicle)
                    and unit.ped and DoesEntityExist(unit.ped) and not IsEntityDead(unit.ped)

                if alive and #(GetEntityCoords(unit.vehicle) - me) < Config.ai.despawnDistance then
                    kept[#kept + 1] = unit
                else
                    despawn(unit)
                end
            end
            units = kept

            -- Re-task survivors: a chase task can quietly expire.
            for _, unit in ipairs(units) do
                if (now - unit.at) > 8000 then
                    unit.at = now
                    TaskVehicleChase(unit.ped, fugitivePed() or PlayerPedId())
                    SetVehicleSiren(unit.vehicle, true)
                end
            end

            -- Units keep arriving through the round. Being out of sight slows
            -- them down rather than stopping them: an unseen suspect still has
            -- half the division looking.
            local interval = status.tracking and Config.ai.spawnEvery or (Config.ai.spawnEvery * 2)

            if #units < Config.ai.max and now >= nextSpawn then
                nextSpawn = now + interval
                spawnUnit(me)
            end
        elseif #units > 0 then
            clearAll()
        end
    end
end)
