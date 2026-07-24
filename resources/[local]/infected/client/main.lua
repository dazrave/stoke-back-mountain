-- Client wiring: take our share of each wave, run the horde, report deaths up.
local state = { tracked = {}, cursor = 0, wave = 0 }

local BEHAVIOUR_SLICE = 10

local function setState(next)
    state = {
        tracked = next.tracked or state.tracked,
        cursor  = next.cursor  or state.cursor,
        wave    = next.wave    or state.wave,
    }
end

RegisterNetEvent('infected:spawnShare', function(quota, wave)
    local allowed = math.min(quota, Config.budget.maxPerClient)

    HUD.set({ wave = wave })
    HUD.notify(('~r~WAVE %d~w~ - %d incoming'):format(wave, quota))

    local spawned, err = Spawner.spawnBatch(allowed, wave)

    if not spawned then
        print('[infected] spawn share failed: ' .. tostring(err))
        TriggerServerEvent('infected:reportSpawned', 0, wave)
        return
    end

    local combined = {}
    for _, entry in ipairs(state.tracked) do combined[#combined + 1] = entry end
    for _, entry in ipairs(spawned)       do combined[#combined + 1] = entry end

    setState({ tracked = combined, wave = wave })
    TriggerServerEvent('infected:reportSpawned', #spawned, wave)
end)

RegisterNetEvent('infected:waveState', function(wave, kills, alive, scores)
    local me   = GetPlayerServerId(PlayerId())
    local mine = scores and (scores[me] or scores[tostring(me)]) or nil

    HUD.set({ wave = wave, kills = kills, alive = alive, myKills = mine })
end)

RegisterNetEvent('infected:reset', function()
    Spawner.clearAll(state.tracked)
    setState({ tracked = {}, cursor = 0 })
    TriggerEvent('infected:clearBodies')
end)

-- Corpses outlive the resource that spawned them: tracked peds get deleted on
-- reset, but anything culled, orphaned, or spawned by another client just lies
-- there decorating the mission start point forever. This bins the lot.
AddEventHandler('infected:clearBodies', function()
    local infectedHash = GetHashKey(Config.relationshipGroup)
    local cleared      = 0

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped)
            and (IsEntityDead(ped) or GetPedRelationshipGroupHash(ped) == infectedHash) then
            NetworkRequestControlOfEntity(ped)
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
            cleared = cleared + 1
        end
    end

    if cleared > 0 then
        print(('[infected] cleared %d bodies'):format(cleared))
    end
end)

RegisterNetEvent('infected:waveCleared', function(wave)
    AddAmmoToPed(PlayerPedId(), GetHashKey(Config.player.weapon), Config.player.resupplyPerWave)
    HUD.notify(('~g~WAVE %d CLEARED~w~  +%d rounds'):format(wave, Config.player.resupplyPerWave))
end)

-- Pre-placed infestations. `at` is a world coord: the pack spawns clustered
-- there instead of around the player. Fired locally by the pint mission for
-- chokepoints the route forces players through. An event, not an export,
-- because spawning yields.
AddEventHandler('infected:garrison', function(at, count)
    local spawned = Spawner.spawnBatch(count or 8, state.wave > 0 and state.wave or 1, {
        at = vector3(at.x, at.y, at.z),
    })
    if not spawned then return end

    local combined = {}
    for _, entry in ipairs(state.tracked) do combined[#combined + 1] = entry end
    for _, entry in ipairs(spawned)       do combined[#combined + 1] = entry end
    setState({ tracked = combined })

    TriggerServerEvent('infected:reportSpawned', #spawned, state.wave)
end)

-- Horde brain. Deaths are counted explicitly by the tick rather than inferred
-- from alive-count deltas, which drifted.
CreateThread(function()
    while true do
        -- Guarded: one bad zombie must never kill the whole horde brain.
        local ok, updated, cursor, killed, killers =
            pcall(Behaviour.tick, state.tracked, state.cursor, BEHAVIOUR_SLICE)

        if ok then
            local kept, despawned = Spawner.cull(updated)

            setState({ tracked = kept, cursor = cursor })

            if killed > 0 or despawned > 0 then
                TriggerServerEvent('infected:reportDead', killed, despawned, killers)
            end
        else
            print('[infected] behaviour tick failed: ' .. tostring(updated))
        end

        Wait(Behaviour.TICK_MS)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Spawner.clearAll(state.tracked)
    Survival.restoreWorld()
end)

-- Hooks for the optional infected_dev resource. Safe to leave in: nothing calls
-- them unless the dev tools are running.
exports('getTracked', function()
    return state.tracked
end)

-- An EVENT, not an export. Spawning yields (model loading waits), and exports
-- are synchronous - yielding inside one throws "attempt to yield across a
-- C-call boundary". Event handlers run in the scheduler and may yield.
-- Result comes back on infected:dev:spawnResult since we cannot return a value.
AddEventHandler('infected:dev:spawnHere', function(archetypeName, count, distance)
    local at = distance or 8.0

    local spawned, err = Spawner.spawnBatch(count or 1, state.wave > 0 and state.wave or 1, {
        archetype   = archetypeName,
        minDistance = at,
        maxDistance = at + 6.0,
    })

    if not spawned then
        TriggerEvent('infected:dev:spawnResult', 0, tostring(err))
        return
    end

    local combined = {}
    for _, entry in ipairs(state.tracked) do combined[#combined + 1] = entry end
    for _, entry in ipairs(spawned)       do combined[#combined + 1] = entry end
    setState({ tracked = combined })

    TriggerEvent('infected:dev:spawnResult', #spawned, nil)
end)

-- Auditioning a walk across the whole horde. An event, not an export, because
-- applying a clipset may need to load an anim set and therefore yields.
AddEventHandler('infected:dev:setClipset', function(key)
    if key == 'default' then
        Archetypes.override = nil
    elseif key == 'normal' then
        Archetypes.override = { clipset = false }
    elseif Config.clipsets[key] then
        Archetypes.override = { clipset = Config.clipsets[key] }
    else
        TriggerEvent('infected:dev:clipsetResult', nil, ('unknown clipset "%s"'):format(tostring(key)))
        return
    end

    local applied = 0
    for _, entry in ipairs(state.tracked) do
        if entry.ped and DoesEntityExist(entry.ped) and not IsEntityDead(entry.ped) then
            if Spawner.applyClipset(entry.ped, Archetypes.effectiveClipset(entry.archetype)) then
                applied = applied + 1
            end
        end
    end

    TriggerEvent('infected:dev:clipsetResult', applied, nil)
end)

-- Safe as an export: no yielding.
exports('getClipsetKeys', function()
    local keys = { 'default', 'normal' }
    for key in pairs(Config.clipsets) do
        keys[#keys + 1] = key
    end
    return keys
end)

exports('clearLocal', function()
    local removed = #state.tracked
    Spawner.clearAll(state.tracked)
    setState({ tracked = {}, cursor = 0 })
    return removed
end)

local function armPlayer()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end

    local hash = GetHashKey(Config.player.weapon)
    GiveWeaponToPed(ped, hash, Config.player.ammo, false, true)
    SetCurrentPedWeapon(ped, hash, true)
end

-- One-hit-kill means frequent respawns; re-arm the survivor each time.
AddEventHandler('playerSpawned', function()
    armPlayer()
end)

CreateThread(function()
    Survival.suppressWorld()
    Survival.atmosphere()
    Survival.watchHealth(function()
        HUD.notify(('~r~You were infected.~w~ You made it to wave %d.'):format(state.wave))
    end)
    HUD.start()

    armPlayer()

    Wait(2000)
    TriggerServerEvent('infected:playerReady')
end)

-- (Straggler blips removed: they only ever rendered for one client.)

-- Sidearm law: whatever you loot, you keep the pistol. Enforced whenever the
-- apocalypse is engaged, so it covers missions and sandbox horde alike.
CreateThread(function()
    local pistol  = GetHashKey(Config.player.weapon)
    local unarmed = GetHashKey('WEAPON_UNARMED')

    while true do
        Wait(3000)

        if Survival.engaged then
            local ped      = PlayerPedId()
            local selected = GetSelectedPedWeapon(ped)

            if selected ~= pistol and selected ~= unarmed then
                local ammo = GetAmmoInPedWeapon(ped, pistol)
                RemoveAllPedWeapons(ped, true)
                GiveWeaponToPed(ped, pistol, ammo, false, true)
                HUD.notify('~y~Pistols only.~w~ House rules.')
            end
        end
    end
end)

-- ===== ammo drops =====
-- A downed copper leaves a box of pistol rounds.
AddEventHandler('infected:ammoDrop', function(at)
    -- Try each prop in turn: a model that isn't in this build silently refuses
    -- to load, and then the box you were promised never existed.
    local hash

    for _, name in ipairs(Config.carrier.props) do
        local candidate = GetHashKey(name)

        if IsModelInCdimage(candidate) then
            RequestModel(candidate)

            local deadline = GetGameTimer() + 4000
            while not HasModelLoaded(candidate) do
                if GetGameTimer() > deadline then break end
                Wait(25)
            end

            if HasModelLoaded(candidate) then
                hash = candidate
                break
            end
        end
    end

    if not hash then
        -- Nothing would load: hand the ammo straight over rather than send
        -- someone hunting a box that does not exist.
        AddAmmoToPed(PlayerPedId(), GetHashKey(Config.player.weapon), Config.carrier.ammo)
        HUD.notify(('~b~Looted a copper.~w~ +%d rounds.'):format(Config.carrier.ammo))
        return
    end

    local prop = CreateObject(hash, at.x, at.y, at.z + 0.2, true, true, false)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(prop) then return end

    PlaceObjectOnGroundProperly(prop)
    HUD.notify('~b~That one was a copper.~w~ He dropped his mags.')

    CreateThread(function()
        Wait(Config.carrier.lifeMs)
        if DoesEntityExist(prop) then
            SetEntityAsMissionEntity(prop, true, true)
            DeleteEntity(prop)
        end
    end)
end)

-- Walk over a dropped box to take it.
--
-- Scans the object pool directly. GetClosestObjectOfType will not return an
-- entity flagged as a mission object unless asked exactly right, which is why
-- boxes were visibly on the floor and completely un-collectable.
CreateThread(function()
    local hashes = {}
    for _, name in ipairs(Config.carrier.props) do
        hashes[GetHashKey(name)] = true
    end

    while true do
        Wait(0)

        local idle = true

        if Survival.engaged then
            local me = GetEntityCoords(PlayerPedId())

            for _, object in ipairs(GetGamePool('CObject')) do
                if DoesEntityExist(object) and hashes[GetEntityModel(object)] then
                    local at   = GetEntityCoords(object)
                    local dist = #(me - at)

                    if dist < 12.0 then
                        idle = false

                        DrawMarker(21, at.x, at.y, at.z + 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            0.45, 0.45, 0.45, 90, 180, 255, 170, true, false, 2, nil, nil, false)

                        if dist < 2.5 then
                            NetworkRequestControlOfEntity(object)
                            SetEntityAsMissionEntity(object, true, true)
                            DeleteEntity(object)

                            AddAmmoToPed(PlayerPedId(), GetHashKey(Config.player.weapon),
                                Config.carrier.ammo)
                            HUD.notify(('~g~+%d rounds.'):format(Config.carrier.ammo))
                        end
                    end
                end
            end
        end

        if idle then Wait(400) end
    end
end)

-- No shooting your mates. Survivors are on the same side by definition, and
-- friendly fire enabled by another game mode must never follow players in
-- here.
CreateThread(function()
    while true do
        Wait(2000)

        if Survival.engaged then
            NetworkSetFriendlyFireOption(false)
            SetCanAttackFriendly(PlayerPedId(), false, false)
        end
    end
end)
