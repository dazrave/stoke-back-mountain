-- core: modifier of the night. One global rule that warps the whole world —
-- the sort of thing a genuinely buggy AI build would ship. Toggle it, or roll a
-- random one as a theme layer ("tonight's build has a physics bug").

local MODS = { 'moon', 'superjump', 'drunk' }

local current = 'off'

local BLURBS = {
    moon      = 'gravity is broken',
    superjump = 'someone left the jump height in debug',
    drunk     = 'the walk animation did not compile',
}

local function set(name)
    if name ~= 'off' then
        local ok = false
        for _, m in ipairs(MODS) do if m == name then ok = true end end
        if not ok then return false end
    end
    current = name
    TriggerClientEvent('core:modifier', -1, name)
    if name == 'off' then
        TriggerClientEvent('core:announce', -1, 'HOTFIX DEPLOYED', 'the world works again', 3500)
    else
        TriggerClientEvent('core:announce', -1, 'MODIFIER: ' .. name:upper(), BLURBS[name], 4500)
    end
    return true
end

RegisterCommand('mod', function(source, args)
    local a = args[1]
    if a == 'random' then a = MODS[math.random(#MODS)] end
    if a == 'off' or a == nil and current ~= 'off' then a = a or 'off' end

    if not a then
        TriggerClientEvent('chat:addMessage', source, { color = { 245, 200, 66 },
            args = { 'core', ('modifier: %s  ·  /mod %s|random|off'):format(current, table.concat(MODS, '|')) } })
        return
    end

    if not set(a) then
        TriggerClientEvent('chat:addMessage', source, { color = { 200, 80, 80 },
            args = { 'core', ('no modifier "%s". try: %s, random, off'):format(a, table.concat(MODS, ', ')) } })
    end
end, false)

-- New joiners get the current modifier so they're not left out.
AddEventHandler('playerJoining', function()
    local src = source
    if current ~= 'off' then TriggerClientEvent('core:modifier', src, current) end
end)
