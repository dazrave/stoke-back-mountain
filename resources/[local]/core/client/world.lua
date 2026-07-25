-- core — the shared foundation every mode sits on. Right now it owns ONE thing:
-- the world's population, so Los Santos feels alive by default.
--
-- The rule is simple: unless a mode has explicitly emptied the streets (the
-- horde and the campaign do this — they broadcast infected:engaged when they
-- take over with fog and one-hit-kills), core keeps the city full of
-- pedestrians and traffic. So free roam and the police chase get a living,
-- breathing city; the apocalypse gets its ghost town. No mode has to ask for
-- either — core reads the flag they already set.
local apocalypse = false

RegisterNetEvent('infected:engaged', function(on)
    apocalypse = on and true or false
end)

-- Raise the ambient population ceiling (the game caps these at 3). Re-asserted
-- periodically because the engine will quietly wind them back down.
local function openTheFloodgates()
    SetPedPopulationBudget(3)
    SetVehiclePopulationBudget(3)
end

CreateThread(function()
    while true do
        Wait(3000)
        if not apocalypse then openTheFloodgates() end
    end
end)

-- The per-frame density push. Multipliers are "this frame" natives, so they
-- have to be set every tick to hold.
CreateThread(function()
    while true do
        if apocalypse then
            -- A mode owns the streets (empty apocalypse). Stay out of its way.
            Wait(500)
        else
            Wait(0)
            SetPedDensityMultiplierThisFrame(1.0)
            SetScenarioPedDensityMultiplierThisFrame(1.0, 1.0)
            SetVehicleDensityMultiplierThisFrame(1.0)
            SetRandomVehicleDensityMultiplierThisFrame(1.0)
            SetParkedVehicleDensityMultiplierThisFrame(1.0)
        end
    end
end)
