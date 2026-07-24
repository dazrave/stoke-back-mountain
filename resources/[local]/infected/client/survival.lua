-- One-hit-kill rule and world suppression.
Survival = {}

-- Whether the apocalypse is "on", driven by the server: wave director running
-- or a mission holding it engaged. Off = the city populates normally, the
-- weather clears, wanted levels return - free-roam is just GTA.
Survival.engaged = false

RegisterNetEvent('infected:engaged', function(on)
    local was = Survival.engaged
    Survival.engaged = on and true or false

    if was and not Survival.engaged then
        ClearWeatherTypePersist()
        SetMaxWantedLevel(5)
    end
end)

-- Infection is a TOUCH, not a stat. The one-hit rule fires only when the
-- damage came from an infected ped: falling off a roof or crashing the van
-- hurts you the normal GTA way. Dying to gravity is not "being infected".
function Survival.watchHealth(onDeath)
    local infectedHash = GetHashKey(Config.relationshipGroup)

    AddEventHandler('gameEventTriggered', function(name, args)
        if name ~= 'CEventNetworkEntityDamage' then return end
        if not Config.survival.oneHitKill then return end

        local victim, attacker = args[1], args[2]
        local playerPed = PlayerPedId()

        if victim ~= playerPed or IsEntityDead(playerPed) then return end

        if attacker and attacker ~= 0 and DoesEntityExist(attacker)
            and IsEntityAPed(attacker)
            and GetPedRelationshipGroupHash(attacker) == infectedHash then
            SetEntityHealth(playerPed, 0)
            if onDeath then onDeath() end
        end
    end)
end

-- Locks the world into a late-night fog while the mode runs; sells the
-- apocalypse far harder than a sunny afternoon. Only while engaged.
function Survival.atmosphere()
    if not Config.survival.atmosphere then return end

    CreateThread(function()
        while true do
            if Survival.engaged then
                NetworkOverrideClockTime(Config.survival.clockHour, 0, 0)
                SetWeatherTypeNowPersist(Config.survival.weather)
            end
            Wait(5000)
        end
    end)
end

function Survival.restoreWorld()
    ClearWeatherTypePersist()
end

-- Clearing ambient population does double duty: it frees slots in GTA's
-- 256-ped pool for the horde, and an empty city is the whole point of the
-- mode. Density calls are per-frame, so simply not calling them brings the
-- city back on its own when disengaged.
function Survival.suppressWorld()
    if not Config.survival.suppressAmbient then return end

    CreateThread(function()
        while true do
            if Survival.engaged then
                SetMaxWantedLevel(Config.survival.maxWantedLevel)
                SetPedDensityMultiplierThisFrame(0.0)
                SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
                SetVehicleDensityMultiplierThisFrame(0.0)
                SetRandomVehicleDensityMultiplierThisFrame(0.0)
                SetParkedVehicleDensityMultiplierThisFrame(0.0)
                SetCreateRandomCops(false)
                SetGarbageTrucks(false)
                SetRandomBoats(false)
                DistantCopCarSirens(false)

                Wait(0)
            else
                Wait(500)
            end
        end
    end)
end
