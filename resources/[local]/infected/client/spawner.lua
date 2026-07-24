-- Spawning, budget checks and culling.
--
-- Peds are created NETWORKED so the whole group fights the same horde, but each
-- client only ever spawns its own share of a wave. Whoever creates a ped owns
-- it and runs its AI, so distributing the spawn distributes the CPU cost - one
-- machine spawning 80 zombies would tank that one player's frames.
Spawner = {}

-- Marks the one-in-twenty that carries ammo. A decor survives ownership
-- changes; checking the ped's model at death did not, and produced phantom
-- "that was a copper" messages.
DecorRegister('SBM_COP', 2) -- 2 = bool

-- Marks a ped as infected in a way OTHER clients can read. Relationship
-- groups are set locally by whoever spawned the ped and do not sync, so any
-- check based on them is blind to most of the horde in a multiplayer game -
-- which is exactly why the drag-out never fired.
DecorRegister('SBM_INF', 2)

local infectedHash

local function ensureRelationships()
    if infectedHash then return infectedHash end

    AddRelationshipGroup(Config.relationshipGroup)
    infectedHash = GetHashKey(Config.relationshipGroup)

    local HATE, COMPANION = 5, 0

    for _, target in ipairs({ 'PLAYER', 'SQUADMATE' }) do
        SetRelationshipBetweenGroups(HATE, infectedHash, GetHashKey(target))
        SetRelationshipBetweenGroups(HATE, GetHashKey(target), infectedHash)
    end

    -- Without this the horde will happily start fighting itself.
    SetRelationshipBetweenGroups(COMPANION, infectedHash, infectedHash)

    return infectedHash
end

function Spawner.hasHeadroom(count)
    local needed = count + Config.budget.headroomRequired
    return CanRegisterMissionEntities(needed, 0, 0, 0)
end

local function loadModel(modelName)
    local hash = GetHashKey(modelName)
    if not IsModelInCdimage(hash) or not IsModelAPed(hash) then
        return nil, ('"%s" is not a valid ped model'):format(modelName)
    end

    RequestModel(hash)
    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then
            return nil, ('timed out loading "%s"'):format(modelName)
        end
        Wait(25)
    end

    return hash
end

-- Finds ground near the player, biased to behind them so they do not watch the
-- horde pop into existence.
local function findSpawnPoint(playerPed, range)
    local origin  = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)

    -- Ahead of the player but never DEAD ahead, never nearer than range.min,
    -- and off the carriageway wherever the probes can manage it. The old
    -- version snapped fast-driving spawns to road nodes, which put whole
    -- waves in the middle of the road. (In this cos/sin basis, 90 = ahead.)
    local vehicle    = GetVehiclePedIsIn(playerPed, false)
    local movingFast = vehicle ~= 0 and GetEntitySpeed(vehicle) > 12.0

    local arc      = Config.spawn.forwardArc or 120.0
    local deadzone = Config.spawn.deadAheadGap or 18.0
    local fallback = nil

    for _ = 1, Config.spawn.groundProbes do
        -- A wedge either side of straight-ahead: in front, but not IN FRONT.
        local side   = math.random() < 0.5 and -1.0 or 1.0
        local offset = deadzone + math.random() * math.max(arc * 0.5 - deadzone, 5.0)
        local spread = Config.spawn.preferBehind
            and (math.random() * 180.0 + 90.0)
            or (90.0 + side * offset)

        local angle    = math.rad(heading + spread)
        local distance = range.min + math.random() * (range.max - range.min)

        if movingFast then
            distance = distance + 40.0 -- they need a head start against a car
        end

        local x = origin.x + math.cos(angle) * distance
        local y = origin.y + math.sin(angle) * distance

        local found, z = GetGroundZFor_3dCoord(x, y, origin.z + 50.0, false)
        if found then
            local point = vector3(x, y, z + 1.0)

            -- Pavements, verges and car parks - not the carriageway.
            if not IsPointOnRoad(x, y, z, 0) then
                return point
            end

            fallback = point
        end
    end

    return fallback
end

-- Guarantees a point even when every ground probe fails (common when collision
-- at the target column has not streamed in): drops the anchor behind the player
-- at the player's own height and lets the peds settle onto the ground.
local function fallbackSpawnPoint(playerPed, range)
    local origin  = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    local angle   = math.rad(heading + 180.0)

    return vector3(
        origin.x + math.cos(angle) * range.min,
        origin.y + math.sin(angle) * range.min,
        origin.z
    )
end

-- Teleports a straggler to a fresh point near its target, just out of sight.
-- Used both when a zombie is outrun and when it is hopelessly stuck: either
-- way it reads as "it found another way round".
function Spawner.relocateNear(ped, targetPed)
    if not DoesEntityExist(ped) or not DoesEntityExist(targetPed) then return false end

    local range = { min = 35.0, max = 60.0 }
    local point = findSpawnPoint(targetPed, range) or fallbackSpawnPoint(targetPed, range)

    SetEntityCoords(ped, point.x, point.y, point.z, false, false, false, false)
    ClearPedTasks(ped)

    return true
end

-- Scatters a ped a few metres around the batch anchor, so a wave spawns as one
-- tight cluster that arrives together instead of trickling in from all over.
-- Hand-placed mission coordinates (hospital front, the boardwalk, the
-- observatory car park) sit on roads more often than not. A garrison anchored
-- exactly on one drops the whole pack into the carriageway, so nudge it onto
-- the nearest pavement, verge or forecourt first.
local function offRoadNear(point, spread)
    for _ = 1, 10 do
        local angle  = math.random() * 6.2832
        local radius = 4.0 + math.random() * (spread or 20.0)

        local x = point.x + math.cos(angle) * radius
        local y = point.y + math.sin(angle) * radius

        local found, z = GetGroundZFor_3dCoord(x, y, point.z + 25.0, false)

        if found and not IsPointOnRoad(x, y, z, 0) then
            return vector3(x, y, z + 1.0)
        end
    end

    return point
end

local function clusterPoint(anchor)
    -- Scattered around the anchor on a random bearing, with a couple of tries
    -- at landing off the carriageway before settling for what we got.
    for attempt = 1, 5 do
        local angle  = math.random() * 6.2832
        local radius = 8.0 + math.random() * 22.0

        local x = anchor.x + math.cos(angle) * radius
        local y = anchor.y + math.sin(angle) * radius

        local found, z = GetGroundZFor_3dCoord(x, y, anchor.z + 10.0, false)
        local ground   = (found and z + 1.0) or anchor.z

        if attempt == 5 or not IsPointOnRoad(x, y, ground, 0) then
            return vector3(x, y, ground)
        end
    end
end

local function configureInfected(ped, archetype)
    SetPedRelationshipGroupHash(ped, ensureRelationships())

    RemoveAllPedWeapons(ped, true) -- melee only

    -- Zombies do not chat. The ALIENS voice bank has no speech lines, so
    -- combat barks become growls (or silence) instead of GTA one-liners.
    SetAmbientVoiceName(ped, 'ALIENS')

    SetEntityMaxHealth(ped, archetype.health)
    SetEntityHealth(ped, archetype.health)
    SetPedSuffersCriticalHits(ped, archetype.crits ~= false) -- headshots drop them (not brutes)

    -- 46 always fight, 5 do not flee from drawn weapons, 0 do not bother
    -- with cover. Without these they behave like startled civilians.
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5, true)
    SetPedCombatAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 10, true) -- commandeer: will drag drivers out
    SetPedFleeAttributes(ped, 0, false)

    -- No self-preservation of any kind. They will not detour to find a ladder,
    -- they will not pick their way down, and they will walk straight off a
    -- roof to reach you. They also barge through anything in the way.
    SetPedPathCanUseLadders(ped, false)
    SetPedPathCanDropFromHeight(ped, true)
    SetPedPathCanUseClimbovers(ped, true)
    SetPedPathPreferToAvoidWater(ped, false)
    SetPedSteersAroundObjects(ped, false)
    SetPedSteersAroundPeds(ped, false)
    SetPedSteersAroundVehicles(ped, false)

    SetPedCombatMovement(ped, 3)  -- suicidal offensive: charge, flank, no self-preservation
    SetPedCombatAbility(ped, 2)
    SetPedAlertness(ped, 3)
    SetPedSeeingRange(ped, 200.0)
    SetPedHearingRange(ped, 250.0)

    SetPedMoveRateOverride(ped, archetype.moveRate)

    SetPedCanPlayAmbientAnims(ped, false) -- no civilian fidgeting between lunges

    Spawner.applyClipset(ped, archetype.clipset)
end

-- Applies a movement clipset, loading the anim set if needed. Also sets the
-- strafe clipset, because a ped in melee combat strafes rather than walks and
-- would otherwise drop straight back to a normal gait mid-fight.
-- There is no getter for the current clipset, so callers re-apply blindly.
function Spawner.applyClipset(ped, clipset)
    if not DoesEntityExist(ped) then return false end

    if not clipset then
        ResetPedMovementClipset(ped, 0.0)
        ResetPedStrafeClipset(ped)
        return true
    end

    if not HasAnimSetLoaded(clipset) then
        RequestAnimSet(clipset)

        local deadline = GetGameTimer() + 2000
        while not HasAnimSetLoaded(clipset) do
            if GetGameTimer() > deadline then
                print(('[infected] anim set "%s" failed to load'):format(clipset))
                return false
            end
            Wait(25)
        end
    end

    SetPedMovementClipset(ped, clipset, 1.0)
    SetPedStrafeClipset(ped, clipset)

    return true
end

-- Returns a new list of tracked infected, or nil plus an error.
-- `overrides` is optional and used by the dev tools: { minDistance, maxDistance,
-- archetype } to spawn a specific type right in front of you.
function Spawner.spawnBatch(count, wave, overrides)
    local playerPed = PlayerPedId()
    local opts      = overrides or {}

    if not DoesEntityExist(playerPed) or IsEntityDead(playerPed) then
        return nil, 'player not alive'
    end

    local range = {
        min = opts.minDistance or Config.spawn.minDistance,
        max = opts.maxDistance or Config.spawn.maxDistance,
    }

    local mix     = Archetypes.mixForWave(wave)
    local spawned = {}

    -- One anchor for the whole batch so they land together as a wave.
    -- opts.at pins the batch to a world coord (garrisons at chokepoints).
    local anchor = (opts.at and offRoadNear(opts.at, 22.0))
        or findSpawnPoint(playerPed, range)
        or fallbackSpawnPoint(playerPed, range)

    local brutes = Archetypes.bruteCountForWave(wave, count)
    if not opts.archetype and brutes > 0 then
        HUD.notify(('~o~Something BIG is with wave %d.'):format(wave))
    end

    for index = 1, count do
        -- Headroom is checked per ped, not for the whole batch. A batch check of
        -- 8+ can fail against the mission-entity budget and spawn nothing, even
        -- when there is room for several. Spawn what fits, then stop.
        if not Spawner.hasHeadroom(1) then
            print(('[infected] out of entity headroom - spawned %d of %d'):format(#spawned, count))
            break
        end

        local name      = opts.archetype or (index <= brutes and 'brute') or Archetypes.pick(mix)
        local archetype = Archetypes.definitions[name]
        local point     = clusterPoint(anchor)

        if point then
            -- One in twenty is a copper carrying ammo - unless the archetype
            -- pins its own model (brutes).
            local carrier   = (not archetype.model) and math.random(Config.carrier.chance) == 1
            local modelName = (carrier and Config.carrier.model)
                or archetype.model
                or Config.models[math.random(#Config.models)]
            local hash, err = loadModel(modelName)

            if hash then
                local ped = CreatePed(4, hash, point.x, point.y, point.z, math.random() * 360.0, true, true)
                SetModelAsNoLongerNeeded(hash)

                if DoesEntityExist(ped) then
                    configureInfected(ped, archetype)

                    DecorSetBool(ped, 'SBM_INF', true)

                    if carrier then
                        DecorSetBool(ped, 'SBM_COP', true)
                    end

                    -- Boss blip; removes itself when the entity is deleted.
                    if archetype.bossBlip then
                        local blip = AddBlipForEntity(ped)
                        SetBlipSprite(blip, 1)
                        SetBlipColour(blip, 1)
                        SetBlipScale(blip, 1.0)
                        BeginTextCommandSetBlipName('STRING')
                        AddTextComponentString('Brute')
                        EndTextCommandSetBlipName(blip)
                    end

                    spawned[#spawned + 1] = {
                        ped       = ped,
                        archetype = name,
                        sprinting = false,
                        -- Personal surround bearing - see the flanking logic
                        -- in behaviour.lua.
                        flank     = math.random() * 6.2832,
                    }
                end
            else
                print('[infected] ' .. tostring(err))
            end
        end

        Wait(0) -- spread the cost across frames rather than hitching
    end

    if #spawned == 0 then
        return nil, 'no entity headroom for any peds'
    end

    return spawned
end

-- Returns the kept list plus a count of *living* peds that were despawned.
-- Corpses are deleted here too once they have lingered, but they are not
-- counted - they were already tallied as kills when they died.
function Spawner.cull(tracked)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local now          = GetGameTimer()
    local kept, despawnedAlive = {}, 0

    for _, entry in ipairs(tracked) do
        if not entry.ped or not DoesEntityExist(entry.ped) then
            -- Vanished without us seeing it die (ownership loss, engine cleanup).
            if not entry.diedAt then despawnedAlive = despawnedAlive + 1 end
        else
            local corpseExpired = entry.diedAt
                and (now - entry.diedAt) >= Config.budget.corpseLingerMs
            local tooFar = #(GetEntityCoords(entry.ped) - playerCoords) > Config.budget.cullDistance

            if corpseExpired or tooFar then
                DeletePed(entry.ped)
                if tooFar and not entry.diedAt then
                    despawnedAlive = despawnedAlive + 1
                end
            else
                kept[#kept + 1] = entry
            end
        end
    end

    return kept, despawnedAlive
end

function Spawner.clearAll(tracked)
    for _, entry in ipairs(tracked) do
        if entry.ped and DoesEntityExist(entry.ped) then
            DeletePed(entry.ped)
        end
    end
end
