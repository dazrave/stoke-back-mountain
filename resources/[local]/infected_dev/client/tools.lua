-- Godmode, loadout, timescale and teleport presets.
Tools = {}

local godEnabled = false

local LOADOUT = {
    'WEAPON_CARBINERIFLE', 'WEAPON_PUMPSHOTGUN', 'WEAPON_PISTOL',
    'WEAPON_MICROSMG', 'WEAPON_GRENADE', 'WEAPON_MACHETE',
}

-- Somewhere open, somewhere tight, somewhere vertical. Different spawn and
-- pathing behaviour in each, which is exactly what needs testing.
Tools.locations = {
    sandy    = vector3(1699.0, 3585.0, 35.6),   -- open desert, long sightlines
    vinewood = vector3(297.0, 180.0, 104.4),    -- dense urban, tight streets
    docks    = vector3(  -5.0, -2530.0, 6.0),   -- containers, cover-heavy
    airport  = vector3(-1336.0, -3044.0, 13.9), -- huge flat open space
    mall     = vector3( -706.0, -914.0, 19.2),  -- interiors, stairs, awkward pathing
}

function Tools.toggleGod()
    godEnabled = not godEnabled

    local ped = PlayerPedId()
    SetEntityInvincible(ped, godEnabled)
    SetPlayerInvincible(PlayerId(), godEnabled)

    if godEnabled then
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        SetPedArmour(ped, 100)
    end

    return godEnabled
end

function Tools.isGod()
    return godEnabled
end

function Tools.giveLoadout()
    local ped = PlayerPedId()

    for _, weapon in ipairs(LOADOUT) do
        GiveWeaponToPed(ped, GetHashKey(weapon), 500, false, false)
    end

    SetPedArmour(ped, 100)

    return #LOADOUT
end

function Tools.setTimescale(scale)
    local clamped = math.max(0.05, math.min(1.0, tonumber(scale) or 1.0))
    SetTimeScale(clamped)
    return clamped
end

function Tools.teleport(name)
    local target = Tools.locations[name]

    if not target then
        return nil, 'unknown location'
    end

    local ped = PlayerPedId()
    SetEntityCoords(ped, target.x, target.y, target.z, false, false, false, false)

    return target
end
