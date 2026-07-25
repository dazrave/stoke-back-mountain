-- core: season persistence. Stats survive restarts via FiveM's built-in KVP —
-- no database. This is what turns disconnected chaos nights into a series with
-- a leaderboard, records, and running jokes ("47th death this season").
--
-- Modes feed it with:  TriggerEvent('core:stat', playerServerId, key, amount)
-- keys: kills, deaths, wins, arrests, bestwave (bestwave keeps the max, not a sum).

local SEASON_KEY = 'sbm:season'
local season = GetResourceKvpString(SEASON_KEY) or '1'

local function dataKey() return ('sbm:data:%s'):format(season) end

local stats = {}
do
    local raw = GetResourceKvpString(dataKey())
    if raw then stats = json.decode(raw) or {} end
end

local dirty = false
local function persist()
    if not dirty then return end
    dirty = false
    SetResourceKvp(dataKey(), json.encode(stats))
end
CreateThread(function() while true do Wait(10000); persist() end end)
AddEventHandler('onResourceStop', function(r) if r == GetCurrentResourceName() then persist() end end)

local function idOf(src)
    local lic = GetPlayerIdentifierByType(src, 'license')
    return lic or ('name:' .. (GetPlayerName(src) or tostring(src)))
end

local function entry(src)
    local id = idOf(src)
    if not stats[id] then
        stats[id] = { name = GetPlayerName(src) or '?', kills = 0, deaths = 0, wins = 0, arrests = 0, bestwave = 0 }
    end
    stats[id].name = GetPlayerName(src) or stats[id].name
    return stats[id]
end

local function award(src, key, amount)
    src = tonumber(src)
    if not src or not key then return end
    local e = entry(src)
    amount = tonumber(amount) or 1
    if key == 'bestwave' then
        if amount > (e.bestwave or 0) then e.bestwave = amount end
    else
        e[key] = (e[key] or 0) + amount
    end
    dirty = true
end

-- Modes fire this.
AddEventHandler('core:stat', function(src, key, amount) award(src, key, amount) end)

-- Every death, anywhere, counted by core's own detector (client/life.lua) — no
-- mode has to report it. The AI director gets a dig in on the way past.
local BARBS = {
    "That's %d this season.", "%d deaths and counting.", "Number %d. A vintage year.",
    "Death #%d. Framed it.", "%d. Genuinely impressive.",
}
RegisterNetEvent('core:died', function()
    local src = source
    local e = entry(src)
    e.deaths = (e.deaths or 0) + 1
    dirty = true
    TriggerClientEvent('core:feed', -1,
        ('~r~%s died.~s~ %s'):format(e.name, (BARBS[math.random(#BARBS)]):format(e.deaths)))
end)

-- ===== readouts =====

local ORDER = { { 'kills', 'kills' }, { 'deaths', 'deaths' }, { 'wins', 'wins' },
                { 'arrests', 'arrests' }, { 'bestwave', 'best wave' } }

local function leaderboard()
    local rows = {}
    for _, e in pairs(stats) do rows[#rows + 1] = e end
    table.sort(rows, function(a, b) return (a.kills or 0) > (b.kills or 0) end)
    return rows
end

-- Reply to a command, whether it came from a player or the server console.
local function reply(source, msg)
    if source and source > 0 then
        TriggerClientEvent('chat:addMessage', source, { color = { 245, 200, 66 }, args = { 'core', msg } })
    else
        print('[core] ' .. msg)
    end
end

RegisterCommand('stats', function(source)
    local rows = leaderboard()
    local send = function(msg) reply(source, msg) end
    if #rows == 0 then return send('No stats yet — go and die a few times.') end
    for i, e in ipairs(rows) do
        if i > 8 then break end
        send(('%d. %s — %d kills · %d deaths · %d wins · %d nicks · wave %d')
            :format(i, e.name, e.kills or 0, e.deaths or 0, e.wins or 0, e.arrests or 0, e.bestwave or 0))
    end
end, false)

RegisterCommand('awards', function()
    local rows = {}
    for _, e in pairs(stats) do rows[#rows + 1] = e end
    if #rows == 0 then return end

    local function top(key) local best; for _, e in ipairs(rows) do if not best or (e[key] or 0) > (best[key] or 0) then best = e end end return best end
    local mvp   = top('kills')
    local muppet= top('deaths')
    local law   = top('arrests')

    TriggerClientEvent('core:announce', -1, 'AWARDS', 'Season ' .. season, 6000)
    Wait(1500)
    if mvp    then TriggerClientEvent('core:feed', -1, ('~g~🏆 MVP:~s~ %s (%d kills)'):format(mvp.name, mvp.kills or 0)) end
    if muppet then TriggerClientEvent('core:feed', -1, ('~r~🤡 Muppet of the season:~s~ %s (%d deaths)'):format(muppet.name, muppet.deaths or 0)) end
    if law and (law.arrests or 0) > 0 then TriggerClientEvent('core:feed', -1, ('~b~👮 Long arm of the law:~s~ %s (%d nicks)'):format(law.name, law.arrests)) end
end, false)

RegisterCommand('season', function(source, args)
    if args[1] == 'new' then
        persist()
        season = tostring((tonumber(season) or 1) + 1)
        SetResourceKvp(SEASON_KEY, season)
        stats = {}
        dirty = false
        TriggerClientEvent('core:announce', -1, 'SEASON ' .. season, 'Clean slate. Good luck.', 5000)
    else
        reply(source, 'Current season: ' .. season .. '  (/season new to start the next)')
    end
end, false)

-- Let other server files award without knowing the internals.
exports('award', award)
