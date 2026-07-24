-- Per-zombie tick.
--
-- Split into two rates on purpose:
--   * The stalker trigger is checked for EVERY ped on EVERY pass. It is only a
--     distance comparison, and it has to be responsive - a sprinting stalker
--     covers the 25m trigger radius in about three seconds, so checking it on a
--     slow rotating slice meant the sprint fired after it had already reached
--     you, i.e. never.
--   * Re-tasking (TaskCombatPed) is the expensive part, so that stays on a
--     rotating slice.
Behaviour = {}

Behaviour.TICK_MS = 500
local RETASK_EVERY_MS   = 1500
local MELEE_RANGE       = 3.0   -- switch from shuffle-walk to a melee lunge inside this
local FLANK_RANGE       = 20.0  -- beyond this, close in on a personal bearing, not the target
local FLANK_RADIUS      = 10.0  -- how wide the surround ring is
local STUCK_AFTER_MS    = 4000  -- no movement for this long counts as stuck
local RELOCATE_STUCK_MS = 8000  -- stuck this long with the player away: go around
local FOLLOW_MS         = 5000  -- how long a stuck zombie shadows a packmate

local SQUADMATE_GROUP = GetHashKey('SQUADMATE')

-- Pathfinding budget, reset every tick. Nearby infected get proper navmesh
-- routes; everyone else gets a straight-line walk, which costs no pool slot.
-- This is what stops the CPointRoute pool crash.
local navUsed = 0

local function takeNav(distance)
    if distance > 60.0 then return false end
    if navUsed >= Config.budget.navBudget then return false end
    navUsed = navUsed + 1
    return true
end

-- The horde attacks players AND their squadmates. Gather candidate targets once
-- per tick (not per zombie) so the ped-pool scan stays cheap.
local function gatherTargets()
    local targets = {}

    for _, playerId in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(playerId)
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            targets[#targets + 1] = ped
        end
    end

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsEntityDead(ped)
            and GetPedRelationshipGroupHash(ped) == SQUADMATE_GROUP then
            targets[#targets + 1] = ped
        end
    end

    return targets
end

local function nearestTarget(targets, fromCoords)
    local closestPed, closestDist = nil, math.huge

    for _, ped in ipairs(targets) do
        local dist = #(GetEntityCoords(ped) - fromCoords)
        if dist < closestDist then
            closestPed, closestDist = ped, dist
        end
    end

    return closestPed, closestDist
end

-- The nearest packmate that is both moving and closer to the target than we
-- are: the one that has "worked it out".
local function nearestMovingMate(pack, selfPed, fromCoords, targetCoords, myDistance)
    local best, bestDist = nil, math.huge

    for _, mate in ipairs(pack) do
        if mate.ped ~= selfPed and #(mate.coords - targetCoords) < (myDistance - 5.0) then
            local dist = #(mate.coords - fromCoords)
            if dist < bestDist then
                best, bestDist = mate.ped, dist
            end
        end
    end

    return best
end

-- Returns a new entry table rather than mutating the one passed in.
local function tickOne(entry, allowRetask, now, targets, pack)
    if not entry.ped or not DoesEntityExist(entry.ped) then
        return entry
    end

    -- Dead peds are handed to the culler, which clears them after a linger
    -- period so you still see the body drop.
    if IsEntityDead(entry.ped) then
        if entry.diedAt then return entry end

        -- Was this one a copper? Explicit flag, set at spawn.
        if DecorExistOn(entry.ped, 'SBM_COP') and DecorGetBool(entry.ped, 'SBM_COP') then
            TriggerEvent('infected:ammoDrop', GetEntityCoords(entry.ped))
        end

        -- Credit the kill. NetworkGetEntityOwner covers every case neatly: a
        -- player ped is owned by that player, a squadmate is owned by the
        -- player it escorts (that is the spawn design, so your bot's kills are
        -- yours), and a vehicle is owned by its driver (roadkill counts).
        local killer = 0
        local cause  = GetPedSourceOfDeath(entry.ped)

        if cause ~= 0 and cause ~= entry.ped and DoesEntityExist(cause)
            and (IsEntityAPed(cause) or IsEntityAVehicle(cause)) then
            local owner = NetworkGetEntityOwner(cause)
            if owner ~= -1 then
                killer = GetPlayerServerId(owner)
            end
        end

        return {
            ped = entry.ped, archetype = entry.archetype,
            sprinting = entry.sprinting, lastTask = entry.lastTask,
            diedAt = now, killer = killer,
        }
    end

    local coords = GetEntityCoords(entry.ped)
    local target, distance = nearestTarget(targets, coords)

    if not target then
        return entry
    end

    local archetype = Archetypes.definitions[entry.archetype]
    local sprinting = entry.sprinting
    local lastTask  = entry.lastTask or 0
    local jackVeh   = entry.jackVeh

    -- Movement bookkeeping for stuck detection.
    local lastPos    = entry.lastPos or coords
    local lastMoveAt = entry.lastMoveAt or now
    if #(coords - lastPos) > 0.5 then
        lastPos    = coords
        lastMoveAt = now
    end
    local stuckFor = now - lastMoveAt

    -- You cannot get away. Outrun one (or leave it hopelessly stuck behind a
    -- fence) and it is respawned just out of sight nearby - which reads as
    -- "it found another way round".
    if distance > Config.budget.relocateDistance
        or (stuckFor > RELOCATE_STUCK_MS and distance > 30.0) then
        if Spawner.relocateNear(entry.ped, target) then
            return {
                ped = entry.ped, archetype = entry.archetype,
                sprinting = sprinting, flank = entry.flank, lastTask = 0,
                lastPos = GetEntityCoords(entry.ped), lastMoveAt = now,
            }
        end
    end

    -- The surprise. One-way flip so it cannot dither on the boundary.
    if archetype.sprintAt and not sprinting and distance <= archetype.sprintAt then
        SetPedMoveRateOverride(entry.ped, archetype.sprintRate)
        ResetPedMovementClipset(entry.ped, 0.0)
        ClearPedTasks(entry.ped)

        -- The reveal. A scream if this ped model's voice has one (silently does
        -- nothing if not), plus a small camera flinch so the moment reads even
        -- when the scream doesn't fire.
        PlayAmbientSpeech1(entry.ped, 'SCREAM_TERROR', 'SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL')
        if distance < 40.0 then
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.08)
        end

        sprinting = true
        lastTask  = 0 -- force an immediate re-task so it charges rather than idles
    end

    -- Pack smarts: a zombie making no progress latches onto the nearest
    -- packmate that IS moving and is nearer the target. If one of them works
    -- out the route - a doorway, a gap in the fence - the rest funnel through
    -- after it instead of face-planting the same wall.
    local followingUntil = entry.followingUntil
    if followingUntil and now > followingUntil then
        followingUntil = nil
        lastTask = 0 -- follow spell over: force a fresh task immediately
    end

    if not followingUntil and stuckFor > STUCK_AFTER_MS and distance > MELEE_RANGE then
        local mate = nearestMovingMate(pack, entry.ped, coords, GetEntityCoords(target), distance)
        if mate and takeNav(distance) then
            TaskGoToEntity(entry.ped, mate, -1, 2.0, 2.0, 1073741824.0, 0)
            followingUntil = now + FOLLOW_MS
        end
    end

    if allowRetask and not followingUntil and (now - lastTask) >= RETASK_EVERY_MS then
        -- "Shuffle" types (shamblers, and stalkers before they trigger) WALK at
        -- their target so the drunk movement clipset and the slow move-rate
        -- actually show - TaskCombatPed swaps in combat locomotion and hides
        -- both. They only lunge into a melee combat task once they are on top of
        -- you. Chargers (runners, triggered stalkers, brutes) go straight to
        -- combat once inside the flank ring.
        local shuffle = archetype.clipset ~= nil and not sprinting
        jackVeh = nil

        if IsPedInAnyVehicle(target, false) then
            -- Owned entirely by Behaviour.pursueVehicles, which runs EVERY
            -- tick instead of on the slow rotating slice. Slice-gated
            -- coordinate tasks were the bug: a van covers ~30m in the 1.5s
            -- between re-tasks, so the zombie ran to where the van used to be,
            -- completed its task, and stood there.
            lastTask = now
        elseif IsPedInAnyVehicle(entry.ped, false) then
            -- It dragged someone out and then got in. It does not know how to
            -- drive. Out.
            TaskLeaveVehicle(entry.ped, GetVehiclePedIsUsing(entry.ped), 256)
        elseif distance > FLANK_RANGE then
            -- Fan out: every zombie owns a fixed bearing and closes in on that
            -- point around its target rather than the target itself, so the
            -- horde arrives from all sides at once instead of queueing up
            -- along the straight line.
            local flank  = entry.flank or 0.0
            local around = GetEntityCoords(target)

            if shuffle then SetPedMoveRateOverride(entry.ped, archetype.moveRate) end

            local fx    = around.x + math.cos(flank) * FLANK_RADIUS
            local fy    = around.y + math.sin(flank) * FLANK_RADIUS
            local speed = shuffle and 1.0 or 2.0

            if takeNav(distance) then
                TaskGoToCoordAnyMeans(entry.ped, fx, fy, around.z, speed, 0, false, 786603, 0.0)
            else
                TaskGoStraightToCoord(entry.ped, fx, fy, around.z, speed, 8000, 0.0, 0.0)
            end
        elseif shuffle and distance > MELEE_RANGE then
            SetPedMoveRateOverride(entry.ped, archetype.moveRate)

            if takeNav(distance) then
                TaskGoToEntity(entry.ped, target, -1, 1.0, 1.0, 1073741824.0, 0)
            else
                local to = GetEntityCoords(target)
                TaskGoStraightToCoord(entry.ped, to.x, to.y, to.z, 1.0, 6000, 0.0, 0.0)
            end
        elseif not IsPedInCombat(entry.ped, target) then
            TaskCombatPed(entry.ped, target, 0, 16)
        end

        if shuffle and not IsPedInAnyVehicle(target, false) then
            Spawner.applyClipset(entry.ped, Archetypes.effectiveClipset(entry.archetype))
        end

        lastTask = now
    end

    return {
        ped            = entry.ped,
        archetype      = entry.archetype,
        sprinting      = sprinting,
        flank          = entry.flank,
        lastTask       = lastTask,
        lastPos        = lastPos,
        lastMoveAt     = lastMoveAt,
        followingUntil = followingUntil,
        jackVeh        = jackVeh,
        diedAt         = nil,
    }
end

-- Vehicle pursuit. Runs every tick for every zombie whose nearest target is
-- sat in a vehicle, bypassing the rotating slice completely.
--
-- The choice of native is the whole fix:
--   * Far  - TaskGoToEntity aimed at the VEHICLE. An entity task follows a
--            moving target natively; a coordinate task completes at a stale
--            point and leaves the ped standing in an empty road.
--   * Close - TaskEnterVehicle with the jack flag (8). The ped wrenches the
--            door open and drags the occupant out. Ordinary combat simply
--            cannot reach somebody sealed inside a car, which is why a parked
--            van was being politely ignored.
--
-- Neither is re-issued while it is still working: re-tasking restarts the
-- approach animation, which reads as standing still all by itself. A pursuer
-- is only re-tasked when the vehicle changes, the mode changes, it stalls, or
-- five seconds pass.
local chase = {}

ZombieDebug = false

function Behaviour.pursueVehicles(tracked, targets, now)
    for _, entry in ipairs(tracked) do
        local ped = entry.ped

        if ped and DoesEntityExist(ped) and not IsEntityDead(ped) then
            local coords  = GetEntityCoords(ped)
            local target  = nearestTarget(targets, coords)
            local vehicle = (target and IsPedInAnyVehicle(target, false))
                and GetVehiclePedIsIn(target, false) or 0

            if vehicle ~= 0 then
                local dist = #(GetEntityCoords(vehicle) - coords)
                local rec0 = chase[ped]

                -- (The "give up and appear at the driver's door" trick lived
                -- here. It worked, but it meant zombies materialising on top of
                -- you constantly, which is worse than them losing the footrace.
                -- If a car outruns them, the car outruns them.)
                local mode  = dist < 15.0 and 'jack' or 'run'
                local rec   = chase[ped]
                local stale = (not rec)
                    or rec.veh ~= vehicle
                    or rec.mode ~= mode
                    or (now - rec.at) > 5000
                    or (GetEntitySpeed(ped) < 0.4 and (now - rec.at) > 1500)

                if stale then
                    -- The drunk clipset physically caps the gait at a shuffle.
                    ResetPedMovementClipset(ped, 0.25)
                    ResetPedStrafeClipset(ped)
                    SetPedMoveRateOverride(ped, 1.6)
                    ClearPedTasks(ped)

                    if mode == 'jack' then
                        local seat = -1
                        for candidate = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
                            if GetPedInVehicleSeat(vehicle, candidate) == target then
                                seat = candidate
                                break
                            end
                        end
                        TaskEnterVehicle(ped, vehicle, -1, seat, 2.0, 8, 0)
                    elseif takeNav(dist) then
                        TaskGoToEntity(ped, vehicle, -1, 3.0, 4.0, 1073741824.0, 0)
                    else
                        local to = GetEntityCoords(vehicle)
                        TaskGoStraightToCoord(ped, to.x, to.y, to.z, 4.0, 6000, 0.0, 0.0)
                    end

                    chase[ped] = { veh = vehicle, mode = mode, at = now,
                                   since = (rec and rec.since) or now }

                    if ZombieDebug then
                        print(('[infected] pursue ped=%d mode=%s dist=%.1f'):format(ped, mode, dist))
                    end
                end
            elseif chase[ped] then
                chase[ped] = nil
            end
        end
    end
end

-- /zdbg - print what the pursuers are actually doing, to the F8 console.
RegisterCommand('zdbg', function()
    ZombieDebug = not ZombieDebug
    print('[infected] zombie debug ' .. (ZombieDebug and 'ON' or 'OFF'))
end, false)

-- `cursor` rotates which slice gets the expensive re-task this pass.
function Behaviour.tick(tracked, cursor, sliceSize)
    local updated = {}
    local total   = #tracked
    local now     = GetGameTimer()

    local newlyDead = 0
    local killers   = {}
    local targets   = gatherTargets()

    -- Fresh pathfinding budget each tick.
    navUsed = 0

    -- Vehicle chases are handled every tick, never slice-gated.
    Behaviour.pursueVehicles(tracked, targets, now)

    -- Packmates that moved recently: candidates for the stuck to follow.
    local pack = {}
    for _, entry in ipairs(tracked) do
        if entry.ped and DoesEntityExist(entry.ped) and not IsEntityDead(entry.ped)
            and entry.lastMoveAt and (now - entry.lastMoveAt) < 1500 then
            pack[#pack + 1] = { ped = entry.ped, coords = GetEntityCoords(entry.ped) }
        end
    end

    for index, entry in ipairs(tracked) do
        local allowRetask = total <= sliceSize
            or (index > cursor and index <= cursor + sliceSize)

        local result = tickOne(entry, allowRetask, now, targets, pack)

        if result.diedAt == now and not entry.diedAt then
            newlyDead = newlyDead + 1

            if result.killer and result.killer ~= 0 then
                killers[result.killer] = (killers[result.killer] or 0) + 1
            end
        end

        updated[index] = result
    end

    local nextCursor = (total > 0 and (cursor + sliceSize) < total) and (cursor + sliceSize) or 0

    return updated, nextCursor, newlyDead, killers
end

function Behaviour.countAlive(tracked)
    local alive = 0

    for _, entry in ipairs(tracked) do
        if entry.ped and DoesEntityExist(entry.ped) and not IsEntityDead(entry.ped) then
            alive = alive + 1
        end
    end

    return alive
end
