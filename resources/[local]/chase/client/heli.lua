-- Police air support.
--
-- Spawned by the FUGITIVE'S own client for the same reason the cars are (see
-- ai.lua): that machine owns the airspace over the action, so the helicopter
-- always exists where it matters and its flight AI runs locally instead of at
-- the mercy of entity ownership.
--
-- It cannot arrest, it is not armed and it cannot be shot down. Its job is to
-- be the REASON the suspect keeps turning up on everyone's map: while it has
-- clear line of sight the police get a live lock, and the moment the suspect
-- gets under something - a tunnel, a bridge, a multi-storey - the eye breaks
-- and the ping goes stale like any other. Tracking stops being a thing the HUD
-- simply knows and becomes a thing you can hear coming.
local air = { vehicle = nil, pilot = nil, taskedAt = 0, nextReport = 0 }

local loadModel = SBM.loadModel

local function despawn()
    if air.pilot and DoesEntityExist(air.pilot) then
        SetEntityAsMissionEntity(air.pilot, true, true)
        DeleteEntity(air.pilot)
    end
    if air.vehicle and DoesEntityExist(air.vehicle) then
        SetEntityAsMissionEntity(air.vehicle, true, true)
        DeleteEntity(air.vehicle)
    end

    air = { vehicle = nil, pilot = nil, taskedAt = 0, nextReport = 0 }
end

RegisterNetEvent('chase:end', despawn)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    despawn()
end)

local function alive()
    return air.vehicle and DoesEntityExist(air.vehicle)
        and air.pilot and DoesEntityExist(air.pilot) and not IsEntityDead(air.pilot)
end

local function spawn(from)
    local settings  = Config.ai.heli
    local heliHash  = loadModel(settings.model)
    local pilotHash = loadModel(settings.pilot)
    if not heliHash or not pilotHash then return end

    -- Comes in from off to one side rather than appearing directly overhead,
    -- so the first anybody knows about it is the noise.
    local angle = math.random() * 6.2832
    local vehicle = CreateVehicle(heliHash,
        from.x + math.cos(angle) * settings.arriveDistance,
        from.y + math.sin(angle) * settings.arriveDistance,
        from.z + settings.arriveHeight,
        0.0, true, true)

    SetModelAsNoLongerNeeded(heliHash)
    if not DoesEntityExist(vehicle) then return end

    SetVehicleEngineOn(vehicle, true, true, false)
    SetHeliBladesFullSpeed(vehicle)
    SetVehicleSiren(vehicle, true)
    SetVehicleHasMutedSirens(vehicle, false)
    -- Steady, and it stays up. A helicopter that clips a mast and drops out of
    -- the sky ends the pursuit for no good reason, and nobody in this round is
    -- carrying anything that ought to bring one down.
    SetHeliTurbulenceScalar(vehicle, 0.0)
    SetEntityInvincible(vehicle, true)
    SetEntityProofs(vehicle, true, true, true, true, true, true, true, true)

    local pilot = CreatePedInsideVehicle(vehicle, 26, pilotHash, -1, true, true)
    SetModelAsNoLongerNeeded(pilotHash)

    if not DoesEntityExist(pilot) then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteEntity(vehicle)
        return
    end

    SBM.hardenPed(pilot)
    SetPedCanBeDraggedOut(pilot, false)
    RemoveAllPedWeapons(pilot, true)
    SetPedFleeAttributes(pilot, 0, false)
    SetDriverAbility(pilot, 1.0)
    SetPedKeepTask(pilot, true)

    air.vehicle, air.pilot = vehicle, pilot
end

local function keepOnThem(ped)
    local offset = Config.ai.heli.offset

    TaskHeliChase(air.pilot, ped, offset.x, offset.y, offset.z)
    SetVehicleSearchlight(air.vehicle, true, true)
    air.taskedAt = GetGameTimer()
end

-- Eyes, on exactly the same terms as a copper's: in range, clear line of
-- sight. Traced to the car where they are in one, because the line-of-sight
-- test ignores only the two entities it is given - name the ped while they are
-- sat in a vehicle and their own roof blocks the ray from above every time.
local function reportSighting(ped)
    local theirs = GetVehiclePedIsIn(ped, false)
    local to     = theirs ~= 0 and theirs or ped

    if #(GetEntityCoords(to) - GetEntityCoords(air.vehicle)) > Config.sight.airRange then return end
    if not HasEntityClearLosToEntity(air.vehicle, to, 17) then return end

    TriggerServerEvent('chase:airEyes', GetEntityCoords(ped))
end

CreateThread(function()
    local scrambleAt = nil

    while true do
        Wait(500)

        local role, status = ChaseState()
        local mine = Config.ai.enabled
            and Config.ai.heli.enabled
            and role == 'fugitive'
            and status.phase == 'active'

        -- Not the suspect any more? Then this client has no business flying a
        -- police helicopter, and anything left over from a previous round goes
        -- now rather than circling whoever is stood here.
        if not mine then
            scrambleAt = nil
            if air.vehicle then despawn() end
        else
            local now = GetGameTimer()
            local ped = PlayerPedId()

            scrambleAt = scrambleAt or (now + Config.ai.heli.arriveAfter * 1000)

            if not alive() then
                if air.vehicle then despawn() end

                if now >= scrambleAt then
                    spawn(GetEntityCoords(ped))

                    if alive() then
                        keepOnThem(ped)
                        TriggerServerEvent('chase:airborne')
                    end
                end
            else
                -- A chase task can quietly expire, same as the cars.
                if (now - air.taskedAt) > 8000 then keepOnThem(ped) end

                if now >= air.nextReport then
                    air.nextReport = now + Config.ai.heli.reportEvery
                    reportSighting(ped)
                end
            end
        end
    end
end)
