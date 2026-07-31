-- Spawning and teardown of the player's squadmate.
--
-- IMPORTANT ARCHITECTURAL NOTE: the bot is created CLIENT-SIDE, by the player
-- it escorts. In FiveM the owning client runs a ped's AI, and ownership only
-- migrates when the ped drifts out of your relevancy. A bot glued to its own
-- player never migrates, so this is the one bot pattern immune to FiveM's
-- entity-ownership problems. Do not "improve" this by spawning server-side.
Squad = {}

local RELATIONSHIP_COMPANION = 0
local SQUAD_GROUP = 'SQUADMATE'

local function ensureRelationshipGroup()
    AddRelationshipGroup(SQUAD_GROUP)

    local squadHash  = GetHashKey(SQUAD_GROUP)
    local playerHash = GetHashKey('PLAYER')

    SetRelationshipBetweenGroups(RELATIONSHIP_COMPANION, squadHash, playerHash)
    SetRelationshipBetweenGroups(RELATIONSHIP_COMPANION, playerHash, squadHash)

    return squadHash
end

-- The streaming loop lives in the core toolkit; this wrapper keeps the
-- ped-model check and the (nil, error string) shape Squad.spawn reports with.
local function loadModel(modelName)
    local hash = GetHashKey(modelName)

    if not IsModelInCdimage(hash) or not IsModelAPed(hash) then
        return nil, ('"%s" is not a valid ped model'):format(modelName)
    end

    if not SBM.loadModel(modelName, Config.bot.modelTimeoutMs) then
        return nil, ('timed out loading ped model "%s"'):format(modelName)
    end

    return hash
end

local function configureCombat(ped, squadHash, weaponHash)
    SetPedRelationshipGroupHash(ped, squadHash)

    SetPedAccuracy(ped, Config.bot.accuracy)
    SetPedCombatAbility(ped, Config.bot.combatAbility)
    SetPedCombatRange(ped, Config.bot.combatRange)

    -- 46 = always fight, 5 = will not flee when a weapon is drawn.
    -- Without these a spawned ped simply will not engage first.
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5, true)

    SetPedFleeAttributes(ped, 0, false)
    SetPedDropsWeaponsWhenDead(ped, false)

    SetEntityMaxHealth(ped, Config.bot.maxHealth)
    SetEntityHealth(ped, Config.bot.maxHealth)
    SetPedArmour(ped, Config.bot.armour)

    GiveWeaponToPed(ped, weaponHash, Config.bot.ammo, false, true)

    -- Actually shoot well: notice threats at range, fire full-auto bursts and
    -- keep the fire rate up. Without these it fires slowly and misses a lot.
    SetPedShootRate(ped, 250)
    SetPedSeeingRange(ped, 120.0)
    SetPedHearingRange(ped, 150.0)
    SetPedFiringPattern(ped, GetHashKey('FIRING_PATTERN_FULL_AUTO'))
end

-- Returns a new squad table, or nil plus an error string.
function Squad.spawn()
    local playerPed = PlayerPedId()

    if not DoesEntityExist(playerPed) or IsEntityDead(playerPed) then
        return nil, 'player is not alive'
    end

    local squadHash = ensureRelationshipGroup()

    local modelHash, modelError = loadModel(Config.bot.model)
    if not modelHash then
        return nil, modelError
    end

    local origin  = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    local spawnAt = GetOffsetFromEntityInWorldCoords(playerPed, Config.bot.spawnDistance, 0.0, 0.0)

    local ped = CreatePed(4, modelHash, spawnAt.x, spawnAt.y, origin.z, heading, true, true)
    SetModelAsNoLongerNeeded(modelHash)

    if not DoesEntityExist(ped) then
        return nil, 'CreatePed returned an entity that does not exist'
    end

    -- Same guns as you: he copies whatever you are holding at spawn, falling
    -- back to the config sidearm if you are unarmed.
    local weaponHash = GetSelectedPedWeapon(playerPed)
    if weaponHash == GetHashKey('WEAPON_UNARMED') then
        weaponHash = GetHashKey(Config.bot.weapon)
    end

    configureCombat(ped, squadHash, weaponHash)

    local groupId = CreateGroup(0)
    SetPedAsGroupLeader(playerPed, groupId)
    SetPedAsGroupMember(ped, groupId)
    SetPedNeverLeavesGroup(ped, true)
    SetGroupFormation(groupId, Config.group.formation)

    return {
        ped     = ped,
        groupId = groupId,
        blip    = UI.attachBlip(ped),
        order   = 'follow',
    }
end

function Squad.despawn(squad)
    if not squad then return end

    if squad.blip and DoesBlipExist(squad.blip) then
        RemoveBlip(squad.blip)
    end

    if squad.ped and DoesEntityExist(squad.ped) then
        RemovePedFromGroup(squad.ped)
        DeletePed(squad.ped)
    end

    if squad.groupId then
        RemoveGroup(squad.groupId)
    end
end

function Squad.isAlive(squad)
    return squad ~= nil
        and squad.ped ~= nil
        and DoesEntityExist(squad.ped)
        and not IsEntityDead(squad.ped)
end
