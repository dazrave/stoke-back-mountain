-- Ammo stashes: guarded boxes out in the world. Walk up, press E, take the
-- rounds. Guarded, because free ammo is not a story.
local STASH_MODEL = 'prop_box_ammo03a'

local loot = { active = false, missionName = nil, claimed = {}, props = {} }

local function M()
    return loot.missionName and Config.missions[loot.missionName] or nil
end

local function sweepProps()
    for _, prop in pairs(loot.props) do
        if DoesEntityExist(prop) then
            SetEntityAsMissionEntity(prop, true, true)
            DeleteEntity(prop)
        end
    end
    loot.props = {}
end

RegisterNetEvent('pint:begin', function(missionName)
    sweepProps()
    loot = { active = true, missionName = missionName, claimed = {}, props = {} }
end)

RegisterNetEvent('pint:stage', function(missionName)
    loot.missionName = missionName
end)

RegisterNetEvent('pint:ended', function() loot.active = false end)
RegisterNetEvent('pint:win', function() loot.active = false end)

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

RegisterNetEvent('pint:spawnStash', function(index)
    local mission = M()
    local stash   = mission and mission.ammoStashes and mission.ammoStashes[index]
    if not stash then return end

    local hash = loadModel(STASH_MODEL)
    if not hash then return end

    local prop = CreateObject(hash, stash.pos.x, stash.pos.y, stash.pos.z, true, true, false)
    SetModelAsNoLongerNeeded(hash)

    if DoesEntityExist(prop) then
        PlaceObjectOnGroundProperly(prop)
        loot.props[index] = prop
    end

    if (stash.guards or 0) > 0 then
        TriggerEvent('infected:garrison', stash.pos, stash.guards)
    end
end)

-- Somebody emptied it: everyone's copy of the box goes away.
RegisterNetEvent('pint:stashGone', function(index)
    local prop = loot.props[index]

    if prop and DoesEntityExist(prop) then
        NetworkRequestControlOfEntity(prop)
        SetEntityAsMissionEntity(prop, true, true)
        DeleteEntity(prop)
    end

    loot.props[index] = nil
end)

RegisterNetEvent('pint:ammoLoot', function(rounds)
    AddAmmoToPed(PlayerPedId(), GetHashKey(Config.player.weapon), rounds)
    PintHUD.notify(('~g~+%d rounds.~w~ Pockets full.'):format(rounds))
end)

-- Claim stashes as you approach, same one-shot server arbitration as the cans.
CreateThread(function()
    while true do
        Wait(2000)

        local mission = M()

        if loot.active and mission and mission.ammoStashes then
            local me = GetEntityCoords(PlayerPedId())

            for index, stash in ipairs(mission.ammoStashes) do
                if not loot.claimed[index]
                    and #(vector2(me.x, me.y) - vector2(stash.pos.x, stash.pos.y)) < Config.jerryCanTrigger then
                    loot.claimed[index] = true
                    TriggerServerEvent('pint:claimStash', index)
                end
            end
        end
    end
end)

-- The prompt and the taking.
CreateThread(function()
    while true do
        Wait(loot.active and 0 or 500)

        local mission = M()

        if loot.active and mission and mission.ammoStashes then
            local me = GetEntityCoords(PlayerPedId())

            for index, stash in ipairs(mission.ammoStashes) do
                local prop = loot.props[index]

                if prop and DoesEntityExist(prop) then
                    local at = GetEntityCoords(prop)

                    if #(me - at) < 2.0 then
                        local onScreen, sx, sy = World3dToScreen2d(at.x, at.y, at.z + 0.5)

                        if onScreen then
                            SetTextFont(4)
                            SetTextScale(0.32, 0.32)
                            SetTextColour(255, 255, 255, 215)
                            SetTextOutline()
                            SetTextCentre(true)
                            BeginTextCommandDisplayText('STRING')
                            AddTextComponentSubstringPlayerName(
                                ('~y~E~w~ take ammo (%d)'):format(stash.rounds or 18))
                            EndTextCommandDisplayText(sx, sy)
                        end

                        if IsControlJustReleased(0, 38) then
                            TriggerServerEvent('pint:takeStash', index)
                        end

                        break
                    end
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    sweepProps()
end)
