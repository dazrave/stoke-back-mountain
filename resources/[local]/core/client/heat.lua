-- core: police "heat". FiveM disables GTA's native dispatch under OneSync, so
-- crimes in free roam normally get no response at all. This rebuilds it as our
-- own system: commit crimes -> heat rises -> NPC police actually spawn and hunt
-- you, escalating with heat, and clearing when you cool off or die.
--
-- Cops are spawned by the offending player's OWN client (like chase's AI units)
-- so their driving/combat AI runs locally where it matters. Heat is per-player
-- and entirely client-side; the server only gets told about big spikes so the
-- cut-list can flag the chase.

local HEAT = {
    max        = 5.0,
    decayPerSec = 0.15,  -- how fast it cools once you stop
    graceMs    = 4000,   -- no cooling for a moment after a crime
    fireGain   = 0.10,   -- per tick while firing a gun in public
    killGain   = 1.5,    -- killing a civilian
    jackGain   = 0.8,    -- dragging someone out of their car
    copKillGain = 2.0,   -- killing a copper - they take it personally
}

local COP = {
    models      = { 'police', 'police2', 'police3' },
    driver      = 's_m_y_cop_01',
    weapon      = 'WEAPON_PISTOL',
    accuracy    = 25,           -- a threat, not a firing squad
    spawnDist   = { 90, 170 },
    despawnDist = 240,
    spawnEvery  = 6000,
}

local heat        = 0.0
local lastCrimeAt = 0
local lastTick    = 0
local units       = {}
local nextSpawn   = 0
local suppressed  = false
local announced   = 0 -- highest whole-star level we've told the server about

RegisterNetEvent('core:heatSuppress', function(on) suppressed = on and true or false end)

-- Heat rides on the city being populated: NPC police only make sense on
-- streets that have people in them, and an emptied city means a mode has taken
-- the world over. Reading core's own population policy rather than listening
-- for a game mode's flag means this stays right when core is hot-reloaded
-- mid-round — a restart re-syncs the policy from the server.
local function active()
    local ped = PlayerPedId()
    return World.policy ~= 'empty' and not suppressed
        and not IsEntityDead(ped) and NetworkIsSessionStarted()
end

local function bump(amount)
    if not active() then return end
    heat = math.min(HEAT.max, heat + amount)
    lastCrimeAt = GetGameTimer()
end

-- ===== crime detection =====

-- Firing a weapon and carjacking are polled; they're states, not one-off events.
CreateThread(function()
    while true do
        Wait(200)
        if active() then
            local ped = PlayerPedId()
            if IsPedShooting(ped) then bump(HEAT.fireGain) end
            if IsPedJacking(ped) then bump(HEAT.jackGain) end
        end
    end
end)

-- Kills are one-off: catch them as they happen. Attacker can be the player or
-- the vehicle they're driving (a hit-and-run still counts).
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if not active() then return end

    local victim, attacker, fatal = args[1], args[2], args[4]
    local me = PlayerPedId()
    if not (fatal and fatal ~= 0) then return end
    if not victim or victim == me or not DoesEntityExist(victim) or not IsEntityAPed(victim) then return end

    local byMe = attacker == me
        or (attacker and DoesEntityExist(attacker) and IsEntityAVehicle(attacker)
            and GetPedInVehicleSeat(attacker, -1) == me)
    if not byMe then return end

    bump(GetPedType(victim) == 6 and HEAT.copKillGain or HEAT.killGain)
end)

-- ===== cop units (adapted from chase/client/ai.lua) =====

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
    for _, ent in ipairs({ unit.ped, unit.vehicle }) do
        if ent and DoesEntityExist(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
        end
    end
end

local function clearAll()
    for _, unit in ipairs(units) do despawn(unit) end
    units = {}
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearAll() end
end)

local function approachPoint(from)
    for _ = 1, 8 do
        local angle = math.random() * 6.2832
        local dist  = COP.spawnDist[1] + math.random() * (COP.spawnDist[2] - COP.spawnDist[1])
        local x, y  = from.x + math.cos(angle) * dist, from.y + math.sin(angle) * dist
        local ok, node, heading = GetClosestVehicleNodeWithHeading(x, y, from.z, 1, 3.0, 0)
        if ok then return node, heading end
    end
    return nil
end

local function spawnUnit(me)
    local node, heading = approachPoint(me)
    if not node then return end

    local carHash = loadModel(COP.models[math.random(#COP.models)])
    local copHash = loadModel(COP.driver)
    if not carHash or not copHash then return end

    local vehicle = CreateVehicle(carHash, node.x, node.y, node.z + 0.5, heading, true, true)
    SetModelAsNoLongerNeeded(carHash)
    if not DoesEntityExist(vehicle) then return end

    SetEntityRotation(vehicle, 0.0, 0.0, heading, 2, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleSiren(vehicle, true)
    SetVehicleHasMutedSirens(vehicle, false)
    SetVehicleEngineOn(vehicle, true, true, false)

    local driver = CreatePedInsideVehicle(vehicle, 26, copHash, -1, true, true)
    SetModelAsNoLongerNeeded(copHash)
    if not DoesEntityExist(driver) then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteEntity(vehicle)
        return
    end

    RemoveAllPedWeapons(driver, true)
    GiveWeaponToPed(driver, GetHashKey(COP.weapon), 250, false, true)
    SetPedInfiniteAmmo(driver, true, GetHashKey(COP.weapon))
    SetPedAccuracy(driver, COP.accuracy)
    SetPedFleeAttributes(driver, 0, false)
    SetPedCombatAttributes(driver, 46, true) -- always fight
    SetPedCombatAttributes(driver, 3, true)  -- give chase on foot
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 1.0)
    SetPedKeepTask(driver, true)
    TaskVehicleChase(driver, PlayerPedId())

    SetPedAsCop(driver, true)
    units[#units + 1] = { vehicle = vehicle, ped = driver, at = GetGameTimer() }
end

local function targetUnits()
    if heat < 1 then return 0 end
    return math.min(5, math.floor(heat) + 1)
end

-- ===== the tick: cool down, keep the fleet honest, spawn to target =====
CreateThread(function()
    while true do
        Wait(1000)
        local now = GetGameTimer()
        local dt  = lastTick == 0 and 1 or (now - lastTick) / 1000
        lastTick  = now

        -- Death wipes the slate.
        if IsEntityDead(PlayerPedId()) then heat = 0 end

        -- Cool down once the grace window has passed and no fresh crime.
        if heat > 0 and (now - lastCrimeAt) > HEAT.graceMs then
            heat = math.max(0, heat - HEAT.decayPerSec * dt)
        end

        -- Tell the server when we cross into a new whole-star level (for the
        -- cut-list + a bit of snark). Only on the way up.
        local whole = math.floor(heat)
        if whole > announced then
            announced = whole
            TriggerServerEvent('core:heatMark', whole)
        elseif heat < 1 then
            announced = 0
        end

        local want = active() and targetUnits() or 0
        local me   = GetEntityCoords(PlayerPedId())

        -- Cull units that died, crashed out, or lost you.
        local kept = {}
        for _, unit in ipairs(units) do
            local alive = unit.vehicle and DoesEntityExist(unit.vehicle)
                and unit.ped and DoesEntityExist(unit.ped) and not IsEntityDead(unit.ped)
            if alive and #(GetEntityCoords(unit.vehicle) - me) < COP.despawnDist and want > 0 then
                kept[#kept + 1] = unit
            else
                despawn(unit)
            end
        end
        units = kept

        -- Re-task survivors; a chase task quietly expires.
        for _, unit in ipairs(units) do
            if (now - unit.at) > 8000 then
                unit.at = now
                TaskVehicleChase(unit.ped, PlayerPedId())
                SetVehicleSiren(unit.vehicle, true)
            end
        end

        -- Bring more in, up to the current heat's target.
        if want > #units and now >= nextSpawn then
            nextSpawn = now + COP.spawnEvery
            spawnUnit(me)
        end
    end
end)

-- ===== wanted-stars HUD (our own; native stars follow the broken wanted system) =====
CreateThread(function()
    while true do
        if heat > 0.01 then
            Wait(0)
            local filled = math.ceil(heat)
            local x, y, w, h, gap = 0.44, 0.965, 0.011, 0.019, 0.016
            for i = 0, 4 do
                DrawRect(x + i * gap, y, w, h, 0, 0, 0, 160)
                if i < filled then
                    DrawRect(x + i * gap, y, w * 0.8, h * 0.7, 245, 200, 66, 230)
                end
            end
        else
            Wait(300)
        end
    end
end)
