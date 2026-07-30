-- Bangers, wrecks, set pieces, jerry cans, petrol and breakdowns. Fuel lives
-- in a synced entity decor so every client sees the same needle no matter who
-- drives.
local FUEL_DECOR = 'SBM_FUEL'
local CAN_MODEL  = 'prop_jerrycan_01a'

DecorRegister(FUEL_DECOR, 1) -- 1 = float

-- Marks anything the campaign spawned. Decors sync between clients, which a
-- local Lua table does not - that is the whole point. A car spawned on Rory's
-- machine is invisible to Darren's sweep list, and every list is wiped when
-- the resource reloads, so leftovers piled up campaign after campaign.
local MINE_DECOR = 'SBM_PINT'
DecorRegister(MINE_DECOR, 3) -- 3 = bool

local state = {
    active        = false,
    missionName   = nil,
    stageIndex    = 0,
    carrying      = nil,
    claimed       = {},
    claimedWrecks = {},
    claimedCans   = {},
    claimedPieces = {},
}

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

local function M()
    return state.missionName and Config.missions[state.missionName] or nil
end

-- Fuel is a fact of the apocalypse, not just of missions: the gauge and the
-- drain apply whenever the horde is engaged as well as during a mission.
local engaged = false

RegisterNetEvent('infected:engaged', function(on)
    engaged = on and true or false
end)

local function gatherStage()
    local mission = M()
    local stage   = mission and mission.stages[state.stageIndex]
    return (stage and stage.type == 'gather') and stage or nil
end

local function dropCarried()
    if state.carrying and DoesEntityExist(state.carrying) then
        DeleteEntity(state.carrying)
    end
    setState({ carrying = nil })
end

-- Everything this client has spawned for the current mission, so a fresh
-- mission start sweeps its own leftovers first - no more new Gaz vans landing
-- on top of old Gaz vans after a wipe or a restart.
local spawnedEntities = {}

local function trackEntity(entity)
    spawnedEntities[#spawnedEntities + 1] = entity

    if DoesEntityExist(entity) then
        DecorSetBool(entity, MINE_DECOR, true)
    end
end

local function bin(entity)
    if not DoesEntityExist(entity) then return end
    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)
end

local function sweepEntities()
    for _, entity in ipairs(spawnedEntities) do
        bin(entity)
    end
    spawnedEntities = {}

    -- Then everything left over from previous campaigns, whoever spawned it
    -- and however long ago. Anything with somebody sat in it is left alone:
    -- deleting a car out from under a player is worse than a bit of litter.
    for _, pool in ipairs({ 'CVehicle', 'CObject' }) do
        for _, entity in ipairs(GetGamePool(pool)) do
            if DoesEntityExist(entity)
                and DecorExistOn(entity, MINE_DECOR)
                and not (pool == 'CVehicle' and not IsVehicleSeatFree(entity, -1)) then
                bin(entity)
            end
        end
    end
end

RegisterNetEvent('pint:begin', function(missionName)
    dropCarried()
    sweepEntities()
    setState({
        active = true, missionName = missionName, stageIndex = 0,
        claimed = {}, claimedWrecks = {}, claimedCans = {}, claimedPieces = {},
    })
end)

RegisterNetEvent('pint:stage', function(missionName, index)
    setState({ missionName = missionName, stageIndex = index })
end)

RegisterNetEvent('pint:ended', function()
    dropCarried()
    setState({ active = false })
end)

RegisterNetEvent('pint:win', function()
    dropCarried()
    setState({ active = false })
end)

-- ========== spawning helpers ==========

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

-- Clears whatever is already parked on a spot - including vans orphaned by an
-- earlier session, which is how two Gaz vans ended up in the same parking
-- space. Only ever deletes EMPTY vehicles, so nobody gets deleted out from
-- under themselves.
local function clearSpot(pos, radius)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle)
            and #(GetEntityCoords(vehicle) - pos) < radius
            and IsVehicleSeatFree(vehicle, -1)
            and GetVehicleNumberOfPassengers(vehicle) == 0 then
            NetworkRequestControlOfEntity(vehicle)
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteEntity(vehicle)
        end
    end
end

-- Ask the GAME how many seats a van has rather than trusting my memory of
-- GTA's vehicle list - that is what stranded people on the pavement twice.
-- Returns hash, name, seats for the first candidate that genuinely fits the
-- crew.
local function loadCrewVan()
    for _, name in ipairs(Config.crewVans or {}) do -- legacy: crew now get a car each
        local hash = loadModel(name)

        if hash then
            local seats = GetVehicleModelNumberOfSeats(hash)
            print(('[pint] crew van "%s": %d seats'):format(name, seats))

            if seats >= Config.minCrewSeats then
                return hash, name, seats
            end

            SetModelAsNoLongerNeeded(hash)
        end
    end

    return nil
end

-- ========== drivable bangers ==========

RegisterNetEvent('pint:spawnSpot', function(index)
    local mission = M()
    local spot    = mission and mission.beaterSpots and mission.beaterSpots[index]
    if not spot then return end

    local hash, modelName

    if spot.crewVan then
        hash, modelName = loadCrewVan()
    end

    if not hash then
        modelName = spot.model or Config.beaterModels[math.random(#Config.beaterModels)]
        hash      = loadModel(modelName)
    end

    if not hash then
        print(('[pint] could not load beater model "%s"'):format(tostring(modelName)))
        return
    end

    clearSpot(vector3(spot.pos.x, spot.pos.y, spot.pos.z), 6.0)

    local vehicle = CreateVehicle(hash, spot.pos.x, spot.pos.y, spot.pos.z, spot.pos.w, true, true)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(vehicle) then return end

    SetVehicleOnGroundProperly(vehicle)
    trackEntity(vehicle)

    local fuelRange = spot.fuel or Config.beaterFuelDefault
    DecorSetFloat(vehicle, FUEL_DECOR, math.random(fuelRange[1], fuelRange[2]) + 0.0)

    SetVehicleEngineHealth(vehicle,
        math.random(Config.beaterEngineHealth[1], Config.beaterEngineHealth[2]) + 0.0)
    SetVehicleBodyHealth(vehicle, 550.0)
    SetVehicleDirtLevel(vehicle, 14.0)
    SetVehicleNumberPlateText(vehicle, spot.plate or 'BANGER')
end)

-- One motor per player, parked in a fan around the start line so three people
-- can set off at once instead of queueing for the van's back seats.
AddEventHandler('pint:spawnMyCar', function(at, index)
    local slot  = ((index or 1) - 1)
    local name  = Config.crewCars[(slot % #Config.crewCars) + 1]
    local hash  = loadModel(name)
    if not hash then return end

    -- Spread wider than the huddle everyone respawns in, and drop each motor
    -- onto the road rather than at the start line's height: spawning at at.z
    -- above uneven ground is how a car ends up landing on a player.
    local radius = Config.crewCarRadius or 16.0
    local angle  = slot * 1.1
    local px     = at.x + math.cos(angle) * radius
    local py     = at.y + math.sin(angle) * radius
    local pz     = at.z

    local ok, node = GetClosestVehicleNodeWithHeading(px, py, at.z, 1, 3.0, 0)
    if ok then
        px, py, pz = node.x, node.y, node.z
    end

    clearSpot(vector3(px, py, pz), 4.0)

    local vehicle = CreateVehicle(hash, px, py, pz, math.deg(angle) + 90.0, true, true)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(vehicle) then return end

    SetVehicleOnGroundProperly(vehicle)
    trackEntity(vehicle)

    DecorSetFloat(vehicle, FUEL_DECOR, Config.crewCarFuel)
    SetVehicleDirtLevel(vehicle, 9.0)
    SetVehicleNumberPlateText(vehicle, ('CREW %d'):format((index or 1)))
end)

-- ========== set-dressing wrecks: locked, dead, sometimes on fire ==========

RegisterNetEvent('pint:spawnWreck', function(index)
    local mission = M()
    local spot    = mission and mission.wreckSpots and mission.wreckSpots[index]
    if not spot then return end

    local modelName = spot.model or Config.wreckModels[math.random(#Config.wreckModels)]
    local hash = loadModel(modelName)
    if not hash then return end

    local wreck = CreateVehicle(hash, spot.pos.x, spot.pos.y, spot.pos.z, spot.pos.w, true, true)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(wreck) then return end

    SetVehicleOnGroundProperly(wreck)
    trackEntity(wreck)

    SetVehicleDoorsLocked(wreck, 2)
    SetVehicleDoorsLockedForAllPlayers(wreck, true)
    SetVehicleEngineHealth(wreck, -4000.0)
    SetVehicleDirtLevel(wreck, 15.0)
    DecorSetFloat(wreck, FUEL_DECOR, 0.0)

    for tyre = 0, 5 do
        SetVehicleTyreBurst(wreck, tyre, true, 1000.0)
    end

    if spot.style == 'scorched' then
        SetEntityRenderScorched(wreck, true)
        SmashVehicleWindow(wreck, 0)
        SmashVehicleWindow(wreck, 1)
    elseif spot.style == 'burning' then
        StartEntityFire(wreck)
    end
end)

-- ========== set pieces: the plane. Locked, frozen, going nowhere (yet) ======

RegisterNetEvent('pint:spawnPiece', function(index)
    local mission = M()
    local piece   = mission and mission.setPieces and mission.setPieces[index]
    if not piece then return end

    local hash = loadModel(piece.model)
    if not hash then return end

    local vehicle = CreateVehicle(hash, piece.pos.x, piece.pos.y, piece.pos.z, piece.pos.w, true, true)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(vehicle) then return end

    SetVehicleOnGroundProperly(vehicle)
    trackEntity(vehicle)
    FreezeEntityPosition(vehicle, true)
    SetVehicleDoorsLocked(vehicle, 2)
    SetVehicleDoorsLockedForAllPlayers(vehicle, true)
    DecorSetFloat(vehicle, FUEL_DECOR, 100.0)
end)

-- ========== jerry cans: guarded fuel you carry by hand ==========

RegisterNetEvent('pint:spawnCan', function(index)
    local mission = M()
    local can     = mission and mission.jerryCans and mission.jerryCans[index]
    if not can then return end

    local hash = loadModel(CAN_MODEL)
    if not hash then return end

    local prop = CreateObject(hash, can.pos.x, can.pos.y, can.pos.z, true, true, false)
    SetModelAsNoLongerNeeded(hash)

    if DoesEntityExist(prop) then
        PlaceObjectOnGroundProperly(prop)
        trackEntity(prop)
    end

    TriggerEvent('infected:garrison', can.pos, can.guards)
end)

-- ========== one-shot spot claiming ==========

local function claimNear(me, list, claimedField, triggerFor, claimEvent)
    if not list then return end

    for index, spot in ipairs(list) do
        if not state[claimedField][index] then
            local at = spot.pos or spot.at
            if #(vector2(me.x, me.y) - vector2(at.x, at.y)) < triggerFor(spot) then
                local claimed = {}
                for key, value in pairs(state[claimedField]) do claimed[key] = value end
                claimed[index] = true
                setState({ [claimedField] = claimed })

                TriggerServerEvent(claimEvent, index)
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(2000)

        local mission = M()

        if state.active and mission then
            local me = GetEntityCoords(PlayerPedId())

            claimNear(me, mission.beaterSpots, 'claimed',
                function() return Config.claimDistance end, 'pint:claimSpot')
            claimNear(me, mission.wreckSpots, 'claimedWrecks',
                function() return Config.claimDistance end, 'pint:claimWreck')
            claimNear(me, mission.jerryCans, 'claimedCans',
                function() return Config.jerryCanTrigger end, 'pint:claimCan')
            claimNear(me, mission.setPieces, 'claimedPieces',
                function() return 250.0 end, 'pint:claimPiece')
        end
    end
end)

-- ========== pick up / carry / pour / deliver ==========

local function drawPrompt(at, text)
    local onScreen, sx, sy = World3dToScreen2d(at.x, at.y, at.z + 0.4)
    if not onScreen then return end

    SetTextFont(4)
    SetTextScale(0.32, 0.32)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextCentre(true)

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end

local function pickUpCan(worldCan)
    NetworkRequestControlOfEntity(worldCan)
    local deadline = GetGameTimer() + 1000
    while not NetworkHasControlOfEntity(worldCan) and GetGameTimer() < deadline do
        Wait(50)
    end

    SetEntityAsMissionEntity(worldCan, true, true)
    DeleteEntity(worldCan)

    local ped  = PlayerPedId()
    local hash = loadModel(CAN_MODEL)
    if not hash then return end

    local held = CreateObject(hash, 0.0, 0.0, 0.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    AttachEntityToEntity(held, ped, GetPedBoneIndex(ped, 57005),
        0.12, 0.02, -0.05, 100.0, 0.0, 10.0, true, true, false, true, 1, true)

    setState({ carrying = held })
    PintHUD.notify('~y~Jerry can.~w~ E beside a motor to pour - or bring it where it\'s needed.')
end

local function pourInto(vehicle)
    local fuel = DecorExistOn(vehicle, FUEL_DECOR) and DecorGetFloat(vehicle, FUEL_DECOR) or 0.0
    DecorSetFloat(vehicle, FUEL_DECOR, math.min(100.0, fuel + Config.jerryCanRefuel))

    dropCarried()
    PintHUD.notify(('~g~Glug glug.~w~ +%d%%.'):format(math.floor(Config.jerryCanRefuel)))
end

CreateThread(function()
    local canHash = GetHashKey(CAN_MODEL)

    while true do
        Wait(state.active and 0 or 500)

        if state.active then
            local ped = PlayerPedId()
            local me  = GetEntityCoords(ped)

            if not state.carrying then
                local worldCan = GetClosestObjectOfType(me.x, me.y, me.z, 2.0, canHash, false, false, false)

                if worldCan ~= 0 and DoesEntityExist(worldCan) then
                    drawPrompt(GetEntityCoords(worldCan), '~y~E~w~ take jerry can')

                    if IsControlJustReleased(0, 38) then -- E
                        pickUpCan(worldCan)
                    end
                end
            elseif GetVehiclePedIsIn(ped, false) == 0 then
                -- Mission delivery beats a cheeky top-up: the plane first.
                local stage = gatherStage()

                if stage and #(vector2(me.x, me.y) - vector2(stage.deliverAt.x, stage.deliverAt.y)) < stage.radius then
                    drawPrompt(me, '~y~E~w~ load it in')

                    if IsControlJustReleased(0, 38) then
                        dropCarried()
                        TriggerServerEvent('pint:delivered')
                    end
                else
                    local vehicle = GetClosestVehicle(me.x, me.y, me.z, 3.5, 0, 71)

                    if vehicle ~= 0 and DoesEntityExist(vehicle) then
                        drawPrompt(GetEntityCoords(vehicle), '~y~E~w~ pour fuel in')

                        if IsControlJustReleased(0, 38) then
                            pourInto(vehicle)
                        end
                    end
                end
            end
        end
    end
end)

-- ========== fuel drain / sputter / stations ==========

-- Every petrol station in the game, without hand-typing coordinates: look for
-- an actual pump prop nearby. The old list missed most stations, which is why
-- refuelling only worked at the scripted one.
local PUMP_MODELS = {
    'prop_gas_pump_1a', 'prop_gas_pump_1b', 'prop_gas_pump_1c', 'prop_gas_pump_1d',
    'prop_gas_pump_old2', 'prop_gas_pump_old3', 'prop_vintage_pump',
}

local function nearStation(coords)
    for _, model in ipairs(PUMP_MODELS) do
        local pump = GetClosestObjectOfType(coords.x, coords.y, coords.z,
            Config.fuel.stationRadius, GetHashKey(model), false, false, false)

        if pump ~= 0 and DoesEntityExist(pump) then
            return true
        end
    end

    -- Fallback for the handful of scripted forecourts with no pump props.
    for _, station in ipairs(Config.stations) do
        if #(vector2(coords.x, coords.y) - vector2(station.x, station.y)) < Config.fuel.stationRadius then
            return true
        end
    end

    return false
end

CreateThread(function()
    local nextSputter   = 0
    local naggedEmpty   = false
    local pumpTroubleAt = 0

    while true do
        Wait(250)

        local shown = false

        if state.active or engaged then
            local ped     = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 then
                -- Every vehicle in the apocalypse has a tank, including the
                -- ones you hotwire. Passengers see the gauge too; only the
                -- driver actually burns it.
                if not DecorExistOn(vehicle, FUEL_DECOR) then
                    DecorSetFloat(vehicle, FUEL_DECOR,
                        math.random(Config.fuel.ambientFuel[1], Config.fuel.ambientFuel[2]) + 0.0)
                end

                local fuel       = DecorGetFloat(vehicle, FUEL_DECOR)
                local isDriver   = GetPedInVehicleSeat(vehicle, -1) == ped
                local refuelling = false

                if isDriver then
                    local coords = GetEntityCoords(vehicle)
                    local parked = GetEntitySpeed(vehicle) < 1.0

                    if parked and nearStation(coords) and fuel < 100.0 then
                        fuel       = math.min(100.0, fuel + Config.fuel.refuelPerSec * 0.25)
                        refuelling = true
                    elseif GetIsVehicleEngineRunning(vehicle) then
                        local rpm    = GetVehicleCurrentRpm(vehicle)
                        local perMin = Config.fuel.drainIdlePerMin
                            + (Config.fuel.drainDrivePerMin - Config.fuel.drainIdlePerMin) * rpm

                        fuel = math.max(0.0, fuel - perMin * 0.25 / 60.0)
                    end

                    DecorSetFloat(vehicle, FUEL_DECOR, fuel)

                    -- Tell the horde we're at the pumps, so it doesn't drag us
                    -- out of a stage that requires standing still.
                    TriggerEvent('pint:refuelling', refuelling)

                    -- Refuelling is loud and stationary. Linger at the pumps
                    -- and company keeps arriving out of the dark.
                    if refuelling then
                        if pumpTroubleAt == 0 then
                            pumpTroubleAt = GetGameTimer() + 12000
                        elseif GetGameTimer() > pumpTroubleAt then
                            pumpTroubleAt = GetGameTimer() + 15000
                            PintHUD.notify('~r~The pumps hum. Something heard.')

                            local angle = math.random() * 6.2832
                            TriggerEvent('infected:garrison', vector3(
                                coords.x + math.cos(angle) * 45.0,
                                coords.y + math.sin(angle) * 45.0,
                                coords.z), 5)
                        end
                    else
                        pumpTroubleAt = 0
                    end

                    if fuel <= 0.0 then
                        SetVehicleEngineOn(vehicle, false, true, true)

                        if not naggedEmpty then
                            naggedEmpty = true
                            PintHUD.notify('~r~Out of petrol.~w~ Brilliant.')
                        end
                    else
                        naggedEmpty = false

                        -- Under a quarter tank she starts coughing.
                        if fuel < Config.fuel.sputterBelow and GetIsVehicleEngineRunning(vehicle) then
                            local now = GetGameTimer()

                            if now >= nextSputter then
                                nextSputter = now + Config.fuel.sputterEveryMs

                                if math.random() < Config.fuel.sputterChance then
                                    SetVehicleEngineOn(vehicle, false, true, true)
                                    PintHUD.notify('~o~She\'s coughing again...')
                                    Wait(1300)
                                    SetVehicleEngineOn(vehicle, true, false, false)
                                end
                            end
                        end
                    end
                end

                PintHUD.set({ fuel = math.floor(fuel + 0.5), refuelling = refuelling })
                shown = true
            else
                pumpTroubleAt = 0
            end
        end

        if not shown then
            PintHUD.set({ fuel = '__clear', refuelling = false })
        end
    end
end)
