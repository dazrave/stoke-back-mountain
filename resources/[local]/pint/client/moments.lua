-- Scripted vignettes: little disasters that happen NEAR you, not TO you.
-- The server picks one player as the "director" every minute or two; entities
-- are networked, so everyone in the area sees the same show.
local function fwdOf(ped, ahead, right, up)
    local pos = GetEntityCoords(ped)
    local f   = GetEntityForwardVector(ped)
    local r   = vector3(f.y, -f.x, 0.0) -- right-hand perpendicular, z-up

    return vector3(
        pos.x + f.x * ahead + r.x * right,
        pos.y + f.y * ahead + r.y * right,
        pos.z + up
    )
end

local function groundAt(point)
    local found, z = GetGroundZFor_3dCoord(point.x, point.y, point.z + 50.0, false)
    return vector3(point.x, point.y, found and z or point.z)
end

local function loadModel(name)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)

    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(25)
    end

    return hash
end

local moments = {}

-- A light aircraft streaks overhead on fire and comes down off to one side.
-- Whatever was flying it climbs out of the wreck. It was not the pilot.
function moments.planecrash()
    local ped  = PlayerPedId()
    local side = (math.random() < 0.5 and -1.0 or 1.0)
    local from = fwdOf(ped, 260.0, side * -80.0, 130.0)
    local to   = groundAt(fwdOf(ped, 110.0, side * math.random(60, 120), 0.0))

    local hash = loadModel('velum')
    if not hash then return end

    local dir     = to - from
    local unit    = dir * (1.0 / math.max(#dir, 0.01))
    local heading = GetHeadingFromVector_2d(unit.x, unit.y)

    local plane = CreateVehicle(hash, from.x, from.y, from.z, heading, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(plane) then return end

    SetEntityRotation(plane, -18.0, 0.0, heading, 2, true)
    SetVehicleForwardSpeed(plane, 55.0)
    StartEntityFire(plane)
    SetVehicleOutOfControl(plane, false, true)

    PintHUD.notify('~o~Is that... a plane?')

    local deadline = GetGameTimer() + 12000
    while GetGameTimer() < deadline do
        if not DoesEntityExist(plane) or IsEntityDead(plane) then break end
        Wait(250)
    end

    if DoesEntityExist(plane) then
        local at = GetEntityCoords(plane)

        if not IsEntityDead(plane) then
            AddExplosion(at.x, at.y, at.z, 5, 1.0, true, false, 1.0)
        end

        Wait(1500)
        TriggerEvent('infected:garrison', GetEntityCoords(plane), 4)
        SetEntityAsNoLongerNeeded(plane)
    end
end

-- A car tears past, loses it, and piles in. The driver legs it screaming.
-- The back seat was... occupied.
function moments.crashcar()
    local ped    = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local probe  = fwdOf(ped, 150.0, 0.0, 0.0)

    local onRoad, node = GetClosestVehicleNode(probe.x, probe.y, probe.z, 1, 3.0, 0)
    if not onRoad then return end

    local models  = { 'emperor', 'asterope', 'ingot', 'premier' }
    local carHash = loadModel(models[math.random(#models)])
    local civHash = loadModel('a_m_y_downtown_01')
    if not carHash or not civHash then return end

    local toUs    = origin - node
    local unit    = toUs * (1.0 / math.max(#toUs, 0.01))
    local heading = GetHeadingFromVector_2d(unit.x, unit.y)

    local car = CreateVehicle(carHash, node.x, node.y, node.z, heading, true, true)
    SetModelAsNoLongerNeeded(carHash)
    if not DoesEntityExist(car) then return end

    local driver = CreatePedInsideVehicle(car, 4, civHash, -1, true, true)
    SetModelAsNoLongerNeeded(civHash)

    -- Aim it past the players and floor it, no regard for traffic rules.
    local past = vector3(origin.x + unit.x * -80.0, origin.y + unit.y * -80.0, origin.z)
    SetVehicleForwardSpeed(car, 22.0)
    TaskVehicleDriveToCoord(driver, car, past.x, past.y, past.z, 35.0, 0,
        GetEntityModel(car), 786468, 5.0, 0)

    local deadline = GetGameTimer() + 12000
    while GetGameTimer() < deadline do
        if not DoesEntityExist(car) then return end
        if #(GetEntityCoords(car) - origin) < 30.0 then break end
        Wait(100)
    end

    SetVehicleTyreBurst(car, 0, true, 1000.0)
    SetVehicleTyreBurst(car, 1, true, 1000.0)
    SetVehicleOutOfControl(car, false, false)

    Wait(2500)

    local crash = GetEntityCoords(car)

    if DoesEntityExist(driver) and not IsEntityDead(driver) then
        TaskLeaveVehicle(driver, car, 0)
        Wait(1200)
        PlayAmbientSpeech1(driver, 'SCREAM_TERROR', 'SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL')
        SetPedMoveRateOverride(driver, 1.3)
        TaskSmartFleeCoord(driver, crash.x, crash.y, crash.z, 300.0, 30000, false, false)
        SetPedKeepTask(driver, true)
    end

    Wait(500)
    PintHUD.notify('~o~That car was full of them-')
    TriggerEvent('infected:garrison', crash, 3)

    SetEntityAsNoLongerNeeded(car)
    if DoesEntityExist(driver) then SetPedAsNoLongerNeeded(driver) end
end

-- A survivor sprints across your path screaming, pursued. He does not stop to
-- chat. The pursuers, on noticing you, do.
function moments.runner()
    local ped    = PlayerPedId()
    local origin = groundAt(fwdOf(ped, 70.0, math.random(-30, 30) + 0.0, 0.0))

    local hash = loadModel('a_m_y_jogger_01')
    if not hash then return end

    local civ = CreatePed(4, hash, origin.x, origin.y, origin.z, math.random(0, 359) + 0.0, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(civ) then return end

    PlayAmbientSpeech1(civ, 'SCREAM_TERROR', 'SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL')
    SetPedMoveRateOverride(civ, 1.25)
    TaskSmartFleeCoord(civ, origin.x, origin.y, origin.z, 400.0, 40000, false, false)
    SetPedKeepTask(civ, true)

    Wait(800)
    PintHUD.notify('~o~"RUN! THEY\'RE RIGHT-" ...he\'s gone.')
    TriggerEvent('infected:garrison', origin, 3)

    SetPedAsNoLongerNeeded(civ)
end

-- A helicopter crosses high overhead, searchlight sweeping. It is not coming
-- for you. It was never coming for you.
function moments.helicopter()
    local ped  = PlayerPedId()
    local from = fwdOf(ped, -250.0, -150.0, 90.0)
    local to   = fwdOf(ped, 350.0, 150.0, 100.0)

    local heliHash  = loadModel('polmav')
    local pilotHash = loadModel('s_m_y_pilot_01')
    if not heliHash or not pilotHash then return end

    local dir     = to - from
    local unit    = dir * (1.0 / math.max(#dir, 0.01))
    local heading = GetHeadingFromVector_2d(unit.x, unit.y)

    local heli = CreateVehicle(heliHash, from.x, from.y, from.z, heading, true, true)
    SetModelAsNoLongerNeeded(heliHash)
    if not DoesEntityExist(heli) then return end

    SetHeliBladesFullSpeed(heli)

    local pilot = CreatePedInsideVehicle(heli, 4, pilotHash, -1, true, true)
    SetModelAsNoLongerNeeded(pilotHash)

    TaskHeliMission(pilot, heli, 0, 0, to.x, to.y, to.z, 4, 40.0, 20.0, -1.0, 150, 100, -1.0, 0)
    SetVehicleSearchlight(heli, true, true)

    PintHUD.notify('~b~A chopper!~w~ HEY! DOWN HERE! ...it\'s not stopping. Course it\'s not.')

    Wait(25000)
    if DoesEntityExist(heli) then SetEntityAsNoLongerNeeded(heli) end
    if DoesEntityExist(pilot) then SetPedAsNoLongerNeeded(pilot) end
end

-- Every moment runs guarded: a failure prints to the F8 console instead of
-- silently doing nothing, so "it didn't work" is always diagnosable.
local function runMoment(name)
    local moment = moments[name]
    if not moment then return end

    CreateThread(function()
        local ok, err = pcall(moment)
        if not ok then
            print(('[pint] moment "%s" failed: %s'):format(name, tostring(err)))
            PintHUD.notify(('~r~moment %s failed~w~ - see F8'):format(name))
        end
    end)
end

-- Someone sprints toward you shouting for help, gets halfway, and goes down.
-- Then gets back up wrong. The best one, frankly.
function moments.turning()
    local ped    = PlayerPedId()
    local origin = groundAt(fwdOf(ped, 45.0, math.random(-20, 20) + 0.0, 0.0))

    local hash = loadModel('a_m_y_business_01')
    if not hash then return end

    local civ = CreatePed(4, hash, origin.x, origin.y, origin.z, math.random(0, 359) + 0.0, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(civ) then return end

    PlayAmbientSpeech1(civ, 'SCREAM_PANIC', 'SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL')
    SetPedMoveRateOverride(civ, 1.2)
    TaskGoToEntity(civ, ped, -1, 6.0, 2.5, 1073741824.0, 0)

    PintHUD.notify('~o~Someone\'s running at you, shouting...')

    Wait(5000)

    if not DoesEntityExist(civ) then return end

    local at = GetEntityCoords(civ)
    ClearPedTasks(civ)
    SetPedToRagdoll(civ, 2600, 2600, 0, true, true, false)
    PintHUD.notify('~r~...and he just went down.')

    Wait(3200)

    if DoesEntityExist(civ) then
        SetEntityAsMissionEntity(civ, true, true)
        DeleteEntity(civ)
    end

    TriggerEvent('infected:garrison', at, 1)
    PintHUD.notify('~r~He got back up.')
end

-- An ambulance comes past far too fast, loses it, and stops being an
-- ambulance. Whatever was in the back lets itself out.
function moments.ambulance()
    local ped    = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local probe  = fwdOf(ped, 140.0, 0.0, 0.0)

    local onRoad, node = GetClosestVehicleNode(probe.x, probe.y, probe.z, 1, 3.0, 0)
    if not onRoad then return end

    local hash = loadModel('ambulance')
    if not hash then return end

    local toUs    = origin - node
    local unit    = toUs * (1.0 / math.max(#toUs, 0.01))
    local heading = GetHeadingFromVector_2d(unit.x, unit.y)

    local van = CreateVehicle(hash, node.x, node.y, node.z, heading, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(van) then return end

    SetVehicleOnGroundProperly(van)
    SetVehicleSiren(van, true)
    SetVehicleEngineOn(van, true, true, false)
    SetVehicleForwardSpeed(van, 22.0)
    SetVehicleOutOfControl(van, false, true)

    PintHUD.notify('~o~Sirens. Something\'s coming this way fast.')

    Wait(7000)

    if DoesEntityExist(van) then
        local at = GetEntityCoords(van)
        PintHUD.notify('~r~The back doors are open.')
        TriggerEvent('infected:garrison', at, 4)
        SetEntityAsNoLongerNeeded(van)
    end
end

-- Somebody comes off a roof. They don't get up. Then they do.
function moments.faller()
    local ped = PlayerPedId()
    local at  = groundAt(fwdOf(ped, 32.0, math.random(-12, 12) + 0.0, 0.0))

    local hash = loadModel('a_m_y_hipster_01')
    if not hash then return end

    local civ = CreatePed(4, hash, at.x, at.y, at.z + 40.0, 0.0, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(civ) then return end

    PlayAmbientSpeech1(civ, 'SCREAM_TERROR', 'SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL')
    SetPedToRagdoll(civ, 9000, 9000, 0, false, false, false)
    PintHUD.notify('~o~Something just came off the roof.')

    Wait(6500)

    local where = DoesEntityExist(civ) and GetEntityCoords(civ) or at

    if DoesEntityExist(civ) then
        SetEntityAsMissionEntity(civ, true, true)
        DeleteEntity(civ)
    end

    TriggerEvent('infected:garrison', where, 1)
    PintHUD.notify('~r~...and it got up.')
end

-- A handful of people sprint past, all going the same way. Whatever they're
-- running from is the way you're headed.
function moments.stampede()
    local ped    = PlayerPedId()
    local models = { 'a_m_y_downtown_01', 'a_f_y_tourist_01', 'a_m_y_jogger_01', 'a_m_m_business_01' }

    PintHUD.notify('~o~People are running the other way. That is never good.')

    for index = 1, 4 do
        local at   = groundAt(fwdOf(ped, 55.0 + index * 5.0, math.random(-16, 16) + 0.0, 0.0))
        local hash = loadModel(models[math.random(#models)])

        if hash then
            local civ = CreatePed(4, hash, at.x, at.y, at.z, 0.0, true, true)
            SetModelAsNoLongerNeeded(hash)

            if DoesEntityExist(civ) then
                SetPedMoveRateOverride(civ, 1.3)
                TaskSmartFleeCoord(civ, at.x, at.y, at.z, 500.0, 30000, false, false)
                SetPedKeepTask(civ, true)
                SetEntityAsNoLongerNeeded(civ)
            end
        end

        Wait(300)
    end
end

-- A fuel tanker, already burning, sat across the road ahead. It does not stay
-- sat there.
function moments.tanker()
    local ped   = PlayerPedId()
    local probe = fwdOf(ped, 95.0, 0.0, 0.0)

    local onRoad, node = GetClosestVehicleNode(probe.x, probe.y, probe.z, 1, 3.0, 0)
    if not onRoad then return end

    local hash = loadModel('tanker')
    if not hash then return end

    local rig = CreateVehicle(hash, node.x, node.y, node.z, math.random(0, 359) + 0.0, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(rig) then return end

    SetVehicleOnGroundProperly(rig)
    StartEntityFire(rig)
    PintHUD.notify('~r~Tanker burning up ahead. Give it room.')

    Wait(9000)

    if DoesEntityExist(rig) then
        local at = GetEntityCoords(rig)
        AddExplosion(at.x, at.y, at.z, 4, 1.0, true, false, 1.2)
        Wait(2500)
        TriggerEvent('infected:garrison', at, 3)
        SetEntityAsNoLongerNeeded(rig)
    end
end

RegisterNetEvent('pint:moment', runMoment)

-- Dev convenience: /moment planecrash | crashcar | runner | helicopter
-- triggers a vignette on yourself for testing without waiting for the director.
RegisterCommand('moment', function(_, args)
    if moments[args[1] or ''] then
        runMoment(args[1])
    else
        local names = {}
        for name in pairs(moments) do names[#names + 1] = name end
        PintHUD.notify('~y~/moment~w~ ' .. table.concat(names, ' | '))
    end
end, false)
