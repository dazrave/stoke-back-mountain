-- Round lifecycle, roles, spawns, freeze, weather and the shared HUD. The
-- cop-only and fugitive-only brains live in their own files and read state
-- through ChaseState().
local state = { role = nil, status = {}, frozen = false }

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

-- Read by cop.lua / fugitive.lua.
function ChaseState()
    return state.role, state.status
end

ChaseHUD = {}

function ChaseHUD.notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, true)
end

function ChaseHUD.draw(text, x, y, scale)
    SetTextFont(4)
    SetTextScale(scale or Config.hud.scale, scale or Config.hud.scale)
    SetTextColour(255, 255, 255, 225)
    SetTextOutline()
    SetTextCentre(true)

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

function ChaseHUD.shard(title, subtitle)
    CreateThread(function()
        local movie = RequestScaleformMovie('MP_BIG_MESSAGE_FREEMODE')

        local deadline = GetGameTimer() + 5000
        while not HasScaleformMovieLoaded(movie) do
            if GetGameTimer() > deadline then return end
            Wait(0)
        end

        BeginScaleformMovieMethod(movie, 'SHOW_SHARD_WASTED_MP_MESSAGE')
        ScaleformMovieMethodAddParamPlayerNameString(title)
        ScaleformMovieMethodAddParamPlayerNameString(subtitle or '')
        EndScaleformMovieMethod()

        local showUntil = GetGameTimer() + 6000
        while GetGameTimer() < showUntil do
            DrawScaleformMovieFullscreen(movie, 255, 255, 255, 255, 0)
            Wait(0)
        end

        SetScaleformMovieAsNoLongerNeeded(movie)
    end)
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

-- Puts a vehicle down flat on the road. Creating one at a guessed height
-- drops it in, and GTA's physics happily lands it on its roof - which is how
-- the fugitive kept starting the round upside down.
local function placeVehicle(hash, pos)
    RequestCollisionAtCoord(pos.x, pos.y, pos.z)

    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 25.0, false)
    local z = found and (groundZ + 1.0) or pos.z

    local vehicle = CreateVehicle(hash, pos.x, pos.y, z, pos.w, true, true)
    if not DoesEntityExist(vehicle) then return nil end

    -- Zero the pitch and roll explicitly, then let the game seat it.
    SetEntityRotation(vehicle, 0.0, 0.0, pos.w, 2, true)
    SetVehicleOnGroundProperly(vehicle)

    -- Shootable. Tyres that won't burst make the whole "aim for the tyres"
    -- brief a lie.
    SetVehicleTyresCanBurst(vehicle, true)
    SetVehicleWheelsCanBreak(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, true)
    SetVehicleStrong(vehicle, false)
    SetDisableVehiclePetrolTankDamage(vehicle, false)

    -- Destructible, not merely dentable: parts come off, the engine dies, and
    -- enough rounds into the tank ends the vehicle entirely.
    SetVehicleCanBreak(vehicle, true)
    SetVehicleEngineCanDegrade(vehicle, true)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehiclePetrolTankHealth(vehicle, 1000.0)
    Wait(50)
    SetVehicleOnGroundProperly(vehicle)

    return vehicle
end

-- Drops the player onto solid ground, waiting for the map to stream in first.
-- A single probe right after a teleport asks about terrain that hasn't loaded
-- yet, fails, and leaves you standing in the sky - which is exactly what was
-- happening at the police station.
-- `expectedZ` is the height of the road we meant to land on. The probe starts
-- 40m up and takes the FIRST surface going down, which next to a building is
-- its roof - so without a sanity check people spawn on top of the nick and
-- spend the head start looking for the stairs.
local function settleToGround(expectedZ)
    local ped = PlayerPedId()

    FreezeEntityPosition(ped, true)

    for _ = 1, 25 do
        local pos = GetEntityCoords(ped)
        RequestCollisionAtCoord(pos.x, pos.y, pos.z)

        Wait(100)

        if HasCollisionLoadedAroundEntity(ped) then
            local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 40.0, false)

            -- More than a storey above the road we aimed at is a roof, not the
            -- ground. Take the road height instead and let physics settle it.
            if found and expectedZ and groundZ > (expectedZ + 6.0) then
                found, groundZ = true, expectedZ
            end

            if found then
                SetEntityCoords(ped, pos.x, pos.y, groundZ + 1.0, false, false, false, false)
                break
            end
        end
    end

    FreezeEntityPosition(ped, false)
end

-- Round vehicles this client spawned; swept before each new round so fleets
-- don't stack up at the station.
local spawnedEntities = {}

local function trackEntity(entity)
    spawnedEntities[#spawnedEntities + 1] = entity
end

local function sweepEntities()
    for _, entity in ipairs(spawnedEntities) do
        if DoesEntityExist(entity) then
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
        end
    end
    spawnedEntities = {}
end

local function applyLook(modelName)
    local hash = loadModel(modelName)
    if not hash then return end

    SetPlayerModel(PlayerId(), hash)
    SetModelAsNoLongerNeeded(hash)

    -- Randomised variations so multiple cops aren't clones.
    local ped = PlayerPedId()
    SetPedRandomComponentVariation(ped, 0)
    SetPedRandomProps(ped)
end

-- Wipe the yard before a round starts. sweepEntities() only knows about cars
-- THIS client spawned in THIS session, so fleets from previous rounds (and
-- everyone else's) survived and the new cars landed on top of them.
RegisterNetEvent('chase:clearArea', function(stationIndex)
    sweepEntities()

    local station = Config.stations[stationIndex or 1] or Config.stations[1]
    local origin  = station.pos
    local cleared = 0

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle)
            and #(GetEntityCoords(vehicle) - origin) < 300.0
            and IsVehicleSeatFree(vehicle, -1)
            and GetVehicleNumberOfPassengers(vehicle) == 0 then
            NetworkRequestControlOfEntity(vehicle)
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteEntity(vehicle)
            cleared = cleared + 1
        end
    end

    print(('[chase] cleared %d vehicles from the muster area'):format(cleared))
end)

RegisterNetEvent('chase:role', function(role)
    DoScreenFadeOut(600)
    Wait(700)

    sweepEntities()

    applyLook(role.isFugitive and Config.models.fugitive or Config.models.cop)
    local ped = PlayerPedId()

    -- Whichever nick got picked this round. Work out which way its road runs
    -- once, then hang the fleet and the suspect off that.
    local station = Config.stations[role.stationIndex or 1] or Config.stations[1]
    local origin  = station.pos

    local ok, node, roadHeading =
        GetClosestVehicleNodeWithHeading(origin.x, origin.y, origin.z, 1, 3.0, 0)

    local base    = ok and node or origin
    local heading = ok and roadHeading or (station.h or 0.0)
    local rad     = math.rad(heading)
    local fx, fy  = -math.sin(rad), math.cos(rad)   -- along the road
    local rx, ry  = math.cos(rad), math.sin(rad)    -- across it

    if role.isFugitive then
        -- Just up the road from everyone else, in plain view. The separation
        -- that matters is the head start, not the distance.
        local sx = base.x + fx * Config.fugitiveLead
        local sy = base.y + fy * Config.fugitiveLead

        SetEntityCoords(ped, sx, sy, base.z, false, false, false, false)
        SetEntityHeading(ped, heading)
        settleToGround(base.z)

        local hash = loadModel(Config.fugitive.cars[math.random(#Config.fugitive.cars)])
        if hash then
            local car = placeVehicle(hash, vector4(sx + rx * 2.5, sy + ry * 2.5, base.z, heading))
            SetModelAsNoLongerNeeded(hash)
            if car then trackEntity(car) end
        end
    else
        -- On the road with everybody else, not stood in the station car park.
        -- Pushed across the kerb so nobody spawns inside the parked fleet.
        SetEntityCoords(ped,
            base.x - rx * 3.0 + math.random(-2, 2),
            base.y - ry * 3.0 + math.random(-2, 2),
            base.z, false, false, false, false)
        SetEntityHeading(ped, heading)
        settleToGround(base.z)

        -- Exactly one cop (the server's pick) spawns the shared fleet, laid
        -- out along the nearest road so nothing ends up inside a wall.
        if role.spawnFleet then
            for index, model in ipairs(Config.cop.vehicles) do
                local hash = loadModel(model)

                if hash then
                    -- Nose to tail down the kerb; the chopper gets shoved well
                    -- clear so its rotors aren't in someone's boot.
                    local along  = (index - 1) * Config.cop.fleetSpacing
                    local across = (model == 'polmav') and 18.0 or 3.0

                    local car = placeVehicle(hash, vector4(
                        base.x + fx * along + rx * across,
                        base.y + fy * along + ry * across,
                        base.z, heading))

                    SetModelAsNoLongerNeeded(hash)
                    if car then trackEntity(car) end
                end
            end
        end

        -- Held at the station until release.
        FreezeEntityPosition(PlayerPedId(), true)
        setState({ frozen = true })
    end

    -- Golden-hour city, and no NPC police gatecrashing the chase.
    NetworkOverrideClockTime(17, 30, 0)
    SetWeatherTypeNowPersist('EXTRASUNNY')

    DoScreenFadeIn(800)

    setState({ role = role.isFugitive and 'fugitive' or 'cop' })

    if role.isFugitive then
        ChaseHUD.shard('SCRAP RUN', 'You\'re the rabbit. No guns. Just wheels and nerve.')
    else
        ChaseHUD.shard('SCRAP RUN', ('Bring in %s. Tyres, not heads.'):format(role.fugitiveName or '?'))
    end
end)

-- Big centre-screen countdown. The corner clock already had the number, but
-- nobody looks at the corner in the three seconds before a chase starts.
local goFlashUntil = 0

local function bigText(text, r, g, b, scale)
    SetTextFont(1)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentSubstringPlayerName(text)
    DrawText(0.5, 0.38)
end

CreateThread(function()
    while true do
        local status = state.status
        local left   = status and status.headstart or 0

        if state.role and status and status.phase == 'headstart' and left > 0 then
            Wait(0)
            bigText(tostring(left), 245, 200, 66, 3.0)
        elseif GetGameTimer() < goFlashUntil then
            Wait(0)
            bigText('GO!', 120, 255, 120, 3.0)
        else
            Wait(200)
        end
    end
end)

RegisterNetEvent('chase:release', function()
    goFlashUntil = GetGameTimer() + 1500
    if state.frozen then
        FreezeEntityPosition(PlayerPedId(), false)
        setState({ frozen = false })
    end

    if state.role == 'cop' then
        ChaseHUD.notify('~b~Units released.~w~ Go.')
    else
        ChaseHUD.notify('~r~They\'re coming.')
    end
end)

RegisterNetEvent('chase:status', function(status)
    setState({ status = status })
end)

RegisterNetEvent('chase:end', function(result, fugitiveName)
    if state.frozen then FreezeEntityPosition(PlayerPedId(), false) end
    setState({ role = nil, status = {}, frozen = false })
    ClearWeatherTypePersist()

    local shards = {
        escaped  = { 'CLEAN GETAWAY', (fugitiveName or '?') .. ' vanished into the city.' },
        arrested = { 'NICKED', 'By the book. Straight to booking.' },
        shot     = { 'SUSPECT DOWN', 'The chief is FURIOUS. It was supposed to be tyres.' },
        crashed  = { 'CASE CLOSED', 'The suspect fought the scenery. Scenery won.' },
        fled     = { 'GONE', 'Left the server. The perfect crime.' },
    }

    local shard = shards[result] or shards.escaped
    ChaseHUD.shard(shard[1], shard[2])
end)

-- Player-versus-player damage, which FiveM disables by default. Without this
-- every shot between players is ignored: bullets pass through each other AND
-- through each other's tyres, which is why nothing seemed to take damage and
-- why the non-lethal rule looked like "nothing happens at all". Drive-bys are
-- explicitly enabled at the same time so drivers can shoot out of the window.
CreateThread(function()
    while true do
        Wait(1000)

        if state.role then
            NetworkSetFriendlyFireOption(true)
            SetCanAttackFriendly(PlayerPedId(), true, true)
            SetPlayerCanDoDriveBy(PlayerId(), true)
        else
            -- Turn it off again the moment the round ends. Left on, it followed
            -- everyone into the zombie modes and let mates shoot each other.
            NetworkSetFriendlyFireOption(false)
            SetCanAttackFriendly(PlayerPedId(), false, false)
        end
    end
end)

-- The vehicle you are sitting in belongs to YOUR machine, and the owner's
-- machine decides whether incoming damage applies. Vehicles spawn damageable,
-- but the game quietly re-protects an occupied one - which is why cars turned
-- bulletproof the moment somebody got in. Re-assert it on whatever you're
-- driving, continuously, so everyone else's shots land.
CreateThread(function()
    while true do
        Wait(1000)

        if state.role then
            local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)

            if vehicle ~= 0 then
                SetEntityInvincible(vehicle, false)
                SetEntityCanBeDamaged(vehicle, true)
                SetEntityProofs(vehicle, false, false, false, false, false, false, false, false)
                SetVehicleTyresCanBurst(vehicle, true)
                SetVehicleWheelsCanBreak(vehicle, true)
                SetVehicleCanBeVisiblyDamaged(vehicle, true)
                SetVehicleStrong(vehicle, false)
                SetDisableVehiclePetrolTankDamage(vehicle, false)
                SetVehicleEngineCanDegrade(vehicle, true)
                SetVehicleCanBreak(vehicle, true)
            end
        end
    end
end)

-- Wanted level stays off for everyone: the only police tonight are humans.
CreateThread(function()
    while true do
        Wait(1000)

        if state.role then
            SetMaxWantedLevel(0)
            SetPlayerWantedLevel(PlayerId(), 0, false)
            SetPlayerWantedLevelNow(PlayerId(), false)
        end
    end
end)

-- Shared HUD: clock plus a role-appropriate status line.
CreateThread(function()
    while true do
        Wait(0)

        local status = state.status

        if state.role and status.phase and status.phase ~= 'idle' then
            local clock

            if status.phase == 'headstart' then
                clock = ('HEAD START  ~y~0:%02d'):format(status.headstart or 0)
            else
                local remaining = status.remaining or 0
                clock = ('%d:%02d'):format(math.floor(remaining / 60), remaining % 60)
            end

            if state.role == 'cop' then
                local line
                if status.finalAlert then
                    line = '~r~CITYWIDE ALERT - THEY\'RE ON YOUR MAP'
                elseif status.tracking then
                    line = '~r~EYES ON - GPS LOCKED'
                elseif status.unseenFor then
                    line = ('~y~SEARCHING - last seen %ds ago'):format(status.unseenFor)
                else
                    line = '~c~NO CONTACT YET'
                end
                ChaseHUD.draw(clock .. '   ' .. line, Config.hud.x, Config.hud.y)
            else
                local line
                if status.finalAlert then
                    line = '~r~CITYWIDE ALERT - NOWHERE TO HIDE'
                elseif status.tracking then
                    line = '~r~SPOTTED'
                elseif status.unseenFor then
                    line = ('~g~HIDDEN - %ds'):format(status.unseenFor)
                else
                    line = '~g~HIDDEN'
                end
                ChaseHUD.draw(clock .. '   ' .. line, Config.hud.x, Config.hud.y)
            end
        else
            Wait(400)
        end
    end
end)
