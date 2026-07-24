-- The jerry-can mule. Press the fetch key: he runs to the nearest jerry can,
-- picks it up, carries it back at your heel, and tips it into the next
-- unlocked vehicle he ends up beside (or the one he gets into with you).
--
-- Deliberately no dependency on the pint resource: he finds ANY jerrycan prop
-- in the world by model, and writes the same synced fuel decor pint reads.
local CAN_MODEL  = 'prop_jerrycan_01a'
local FUEL_DECOR = 'SBM_FUEL'

DecorRegister(FUEL_DECOR, 1) -- 1 = float; idempotent across resources

local fetch = { target = nil, carrying = nil, taskedAt = 0 }

-- Read by main.lua's follow and vehicle threads so they leave him alone
-- mid-errand.
function FetchBusy()
    return fetch.target ~= nil
end

local function setFetch(next)
    fetch = {
        target   = next.target,
        carrying = next.carrying,
        taskedAt = next.taskedAt or 0,
    }
end

local function dropCarried()
    if fetch.carrying and DoesEntityExist(fetch.carrying) then
        DeleteEntity(fetch.carrying)
    end
    setFetch({ target = fetch.target, carrying = nil })
end

local function loadCanModel()
    local hash = GetHashKey(CAN_MODEL)
    RequestModel(hash)

    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(25)
    end

    return hash
end

local function startFetch()
    local squad = ActiveSquad()

    if not Squad.isAlive(squad) then
        UI.notify('~r~Your squadmate is down. Press F10 to get a new one.')
        return
    end

    if fetch.carrying then
        UI.notify('~y~He\'s already lugging one. Lead him to a motor.')
        return
    end

    local at  = GetEntityCoords(squad.ped)
    local can = GetClosestObjectOfType(at.x, at.y, at.z,
        Config.fetch.searchRadius, GetHashKey(CAN_MODEL), false, false, false)

    if can == 0 or not DoesEntityExist(can) then
        UI.notify('~r~No jerry cans anywhere near. Typical.')
        return
    end

    local canAt = GetEntityCoords(can)
    ClearPedTasks(squad.ped)
    TaskGoToCoordAnyMeans(squad.ped, canAt.x, canAt.y, canAt.z, 2.0, 0, false, 786603, 0.0)

    setFetch({ target = can, carrying = nil, taskedAt = GetGameTimer() })
    UI.notify('~b~Squadmate:~w~ on it.')
end

RegisterCommand(Config.fetchCommand.command, startFetch, false)
RegisterKeyMapping(
    Config.fetchCommand.command,
    Config.fetchCommand.label,
    'keyboard',
    Config.fetchCommand.key
)

local function pickUp(squadPed)
    NetworkRequestControlOfEntity(fetch.target)
    local deadline = GetGameTimer() + 1000
    while not NetworkHasControlOfEntity(fetch.target) and GetGameTimer() < deadline do
        Wait(50)
    end

    SetEntityAsMissionEntity(fetch.target, true, true)
    DeleteEntity(fetch.target)

    local hash = loadCanModel()
    if not hash then
        setFetch({ target = nil, carrying = nil })
        return
    end

    local held = CreateObject(hash, 0.0, 0.0, 0.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    AttachEntityToEntity(held, squadPed, GetPedBoneIndex(squadPed, 57005),
        0.12, 0.02, -0.05, 100.0, 0.0, 10.0, true, true, false, true, 1, true)

    setFetch({ target = nil, carrying = held })
    UI.notify('~g~Squadmate:~w~ got it. Lead him to a motor.')
end

local function pourInto(vehicle)
    local fuel = DecorExistOn(vehicle, FUEL_DECOR) and DecorGetFloat(vehicle, FUEL_DECOR) or 0.0
    DecorSetFloat(vehicle, FUEL_DECOR, math.min(100.0, fuel + Config.fetch.canRefuel))

    dropCarried()
    UI.notify(('~g~Squadmate:~w~ fuelled her up. +%d%%.'):format(math.floor(Config.fetch.canRefuel)))
end

-- If he dies mid-errand, the can he was holding lands next to him as a real
-- world prop again, so the errand cost you a squadmate, not the fuel.
local function dropAtCorpse(squadPed)
    local at = GetEntityCoords(squadPed)
    dropCarried()

    local hash = loadCanModel()
    if hash then
        local dropped = CreateObject(hash, at.x, at.y, at.z + 0.2, true, true, false)
        SetModelAsNoLongerNeeded(hash)
        if DoesEntityExist(dropped) then
            PlaceObjectOnGroundProperly(dropped)
        end
    end

    UI.notify('~r~He dropped the can where he fell.')
end

CreateThread(function()
    while true do
        Wait(400)

        local squad = ActiveSquad()
        local alive = Squad.isAlive(squad)

        -- Errand phase: he is on his way to a can.
        if fetch.target then
            if not alive then
                setFetch({ target = nil, carrying = fetch.carrying })
            elseif not DoesEntityExist(fetch.target) then
                -- Someone else took it first.
                setFetch({ target = nil, carrying = nil })
                ClearPedTasks(squad.ped)
                UI.notify('~y~Squadmate:~w~ someone\'s had that can away.')
            elseif GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 then
                -- You got in a car mid-errand: errand cancelled, he comes back.
                setFetch({ target = nil, carrying = nil })
                ClearPedTasks(squad.ped)
                UI.notify('~y~Squadmate:~w~ fine, leaving the can then.')
            else
                local dist = #(GetEntityCoords(squad.ped) - GetEntityCoords(fetch.target))

                if dist < 2.2 then
                    pickUp(squad.ped)
                elseif (GetGameTimer() - fetch.taskedAt) > 6000 then
                    -- Re-task: combat or a wall interrupted him.
                    local canAt = GetEntityCoords(fetch.target)
                    TaskGoToCoordAnyMeans(squad.ped, canAt.x, canAt.y, canAt.z, 2.0, 0, false, 786603, 0.0)
                    setFetch({ target = fetch.target, carrying = nil, taskedAt = GetGameTimer() })
                end
            end

        -- Carry phase: pour into the first sensible vehicle he ends up beside.
        elseif fetch.carrying then
            if not alive then
                if squad and squad.ped and DoesEntityExist(squad.ped) then
                    dropAtCorpse(squad.ped)
                else
                    dropCarried()
                end
            else
                local hisVeh = GetVehiclePedIsIn(squad.ped, false)

                if hisVeh ~= 0 then
                    -- He got in a car holding it. Tips it straight in. Legend.
                    pourInto(hisVeh)
                else
                    local at      = GetEntityCoords(squad.ped)
                    local vehicle = GetClosestVehicle(at.x, at.y, at.z, 3.5, 0, 71)

                    if vehicle ~= 0 and DoesEntityExist(vehicle)
                        and GetVehicleDoorLockStatus(vehicle) ~= 2 then
                        pourInto(vehicle)
                    end
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    dropCarried()
end)
