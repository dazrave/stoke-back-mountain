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

local function loadModel(name)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)

    local deadline = GetGameTimer() + 8000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(25)
    end

    return hash
end

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

local function spawnUnit(me)
    local node, heading = approachPoint(me)
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

    local driver = CreatePedInsideVehicle(vehicle, 26, copHash, -1, true, true)
    SetModelAsNoLongerNeeded(copHash)

    if not DoesEntityExist(driver) then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteEntity(vehicle)
        return
    end

    if Config.ai.invincible then
        SetEntityInvincible(driver, true)
        -- Invincibility alone does not stop a fall: fall damage arrives as
        -- COLLISION damage, which is the fourth proof here and the reason a
        -- cop could still be killed by a drop off the hills.
        -- (bullet, fire, explosion, collision, melee, steam, p7, drown)
        SetEntityProofs(driver, true, true, true, true, true, true, true, true)
        SetPedSuffersCriticalHits(driver, false)
        SetPedDiesInWater(driver, false)
        SetPedCanRagdollFromPlayerImpact(driver, false)
    end

    -- Armed, fearless, and a genuinely good driver.
    RemoveAllPedWeapons(driver, true)
    GiveWeaponToPed(driver, GetHashKey(Config.ai.weapon), 250, false, true)
    SetPedInfiniteAmmo(driver, true, GetHashKey(Config.ai.weapon))
    SetPedAccuracy(driver, Config.ai.accuracy)
    SetPedFiringPattern(driver, GetHashKey('FIRING_PATTERN_BURST_FIRE_DRIVEBY'))

    SetPedFleeAttributes(driver, 0, false)
    SetPedCombatAttributes(driver, 46, true) -- always fight
    SetPedCombatAttributes(driver, 2, true)  -- will lean out and shoot
    SetPedCombatAttributes(driver, 3, true)  -- will get out and give chase on foot

    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 1.0)
    SetPedKeepTask(driver, true)

    TaskVehicleChase(driver, PlayerPedId())

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
                    TaskVehicleChase(unit.ped, PlayerPedId())
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
