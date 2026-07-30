-- core — the shared foundation every mode sits on. This file owns exactly one
-- thing: how busy Los Santos is.
--
-- The city is ALIVE by default and stays that way unless a mode has claimed
-- otherwise on the server (see server/world.lua). Free roam and the police
-- chase get a full city for nothing; the horde and the campaign claim 'empty'
-- and get their ghost town. No mode touches the density natives itself — if
-- two resources push the streets in opposite directions every frame, whoever
-- ran last wins and the city flickers.
World = { policy = 'alive' }

local LEVELS = {
    alive  = { ped = 1.0,  vehicle = 1.0, parked = 1.0, budget = 3, extras = true  },
    sparse = { ped = 0.35, vehicle = 0.4, parked = 0.6, budget = 2, extras = true  },
    empty  = { ped = 0.0,  vehicle = 0.0, parked = 0.0, budget = 0, extras = false },
}

local synced = false

-- The city's odds and ends. These are STICKY natives, not per-frame ones, so
-- they get set once when the policy changes — and, crucially, set back. Not
-- switching them on again is why the streets used to stay half-dead after a
-- horde ended: traffic returned, but the patrol cars, bin lorries, boats and
-- distant sirens never did, for the rest of the session.
local function applyExtras(on)
    SetCreateRandomCops(on)
    SetGarbageTrucks(on)
    SetRandomBoats(on)

    -- Distant sirens stay OFF even in a living city. The native loops an
    -- ambient siren bed more or less permanently rather than playing it now
    -- and again, which stops reading as atmosphere and starts reading as a
    -- fault — and it sits right on top of the voices you actually need to
    -- hear. Real sirens still play: heat.lua spawns cars with real ones.
    DistantCopCarSirens(false)
end

local function applyPolicy(policy)
    local level = LEVELS[policy]

    World.policy = policy
    applyExtras(level.extras)
    SetPedPopulationBudget(level.budget)
    SetVehiclePopulationBudget(level.budget)
end

RegisterNetEvent('core:population', function(policy)
    if not LEVELS[policy] then return end
    -- First word from the server always lands, even if it matches what we
    -- assumed: a client starting up after a horde needs the sticky natives
    -- actually applied, not skipped as a no-op.
    if synced and policy == World.policy then return end

    synced = true
    applyPolicy(policy)
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    TriggerServerEvent('core:worldReady')
end)

-- The population budget is a ceiling the engine quietly winds back down, so it
-- gets re-asserted rather than set once.
CreateThread(function()
    while true do
        Wait(3000)
        local level = LEVELS[World.policy]
        SetPedPopulationBudget(level.budget)
        SetVehiclePopulationBudget(level.budget)
    end
end)

-- The density multipliers are "this frame" natives: they hold for one tick and
-- then lapse. Both directions need pushing every frame — the engine's own idea
-- of a busy street is what comes back the moment we stop asking for an empty
-- one.
CreateThread(function()
    while true do
        Wait(0)
        local level = LEVELS[World.policy]
        SetPedDensityMultiplierThisFrame(level.ped)
        SetScenarioPedDensityMultiplierThisFrame(level.ped, level.ped)
        SetVehicleDensityMultiplierThisFrame(level.vehicle)
        SetRandomVehicleDensityMultiplierThisFrame(level.vehicle)
        SetParkedVehicleDensityMultiplierThisFrame(level.parked)
    end
end)
