-- core: in-game voting. The crew (and, once it's wired, live chat) decides
-- things on the spot — keep a new feature or bin it, who has to do the run,
-- what mode we play next. Results can fire an action, so a vote genuinely
-- changes the game.
--
-- Other resources start a vote with:
--   exports.core:startVote(question, options, seconds, tag)
-- and listen for the outcome:
--   AddEventHandler('core:voteResult', function(tag, winnerIndex, label, counts) ... end)

local cur = nil -- { question, options, votes = {src->idx}, tag }

local function tally()
    local counts = {}
    for i = 1, #cur.options do counts[i] = 0 end
    for _, idx in pairs(cur.votes) do
        if counts[idx] then counts[idx] = counts[idx] + 1 end
    end
    return counts
end

local function startVote(question, options, seconds, tag)
    if cur then return false end            -- one at a time
    if not options or #options < 2 then return false end

    cur = { question = question, options = options, votes = {}, tag = tag }
    seconds = seconds or 20

    TriggerClientEvent('core:voteStart', -1, question, options, seconds)
    TriggerClientEvent('core:announce', -1, 'VOTE', question, 2500)

    CreateThread(function()
        for _ = 1, seconds do
            Wait(1000)
            if not cur then return end
            TriggerClientEvent('core:voteTally', -1, tally())
        end
        if not cur then return end

        local counts = tally()
        local wi, wc = 1, -1
        for i, c in ipairs(counts) do if c > wc then wi, wc = i, c end end
        local label, tg = cur.options[wi], cur.tag
        cur = nil

        TriggerClientEvent('core:voteEnd', -1)
        TriggerClientEvent('core:announce', -1, 'RESULT: ' .. label,
            (wc == 1 and '1 vote' or ('%d votes'):format(wc)), 4500)
        TriggerEvent('core:voteResult', tg, wi, label, counts)
    end)
    return true
end
exports('startVote', startVote)

RegisterNetEvent('core:castVote', function(idx)
    local src = source
    idx = tonumber(idx)
    if cur and idx and cur.options[idx] then cur.votes[src] = idx end
end)

-- ===== ready-made votes =====

-- /vote Question? / Option A / Option B / ...   (options split on " / ")
RegisterCommand('vote', function(source, args)
    local text  = table.concat(args, ' ')
    local parts = {}
    for seg in string.gmatch(text, '([^/]+)') do
        seg = seg:gsub('^%s+', ''):gsub('%s+$', '')
        if seg ~= '' then parts[#parts + 1] = seg end
    end

    local question, options
    if #parts >= 2 and parts[1]:sub(-1) == '?' then
        question = parts[1]
        options = {}
        for i = 2, #parts do options[#options + 1] = parts[i] end
    else
        question, options = 'Vote:', parts
    end

    if not startVote(question, options, 20, 'custom') then
        TriggerClientEvent('chat:addMessage', source, { color = { 200, 80, 80 },
            args = { 'vote', 'usage: /vote Question? / Option A / Option B   (or a vote is already running)' } })
    end
end, false)

-- /votewho who does the run?   -> options are the connected players
RegisterCommand('votewho', function(source, args)
    local q = table.concat(args, ' ')
    if q == '' then q = 'Who?' end
    local opts = {}
    for _, pid in ipairs(GetPlayers()) do opts[#opts + 1] = GetPlayerName(tonumber(pid)) or ('#' .. pid) end
    if not startVote(q, opts, 20, 'who') then
        TriggerClientEvent('chat:addMessage', source, { color = { 200, 80, 80 },
            args = { 'vote', 'need at least 2 players (or a vote is running)' } })
    end
end, false)

-- /votenext  -> the crew picks the next mode, and it actually starts
RegisterCommand('votenext', function()
    startVote('What next?', { 'Zombie horde', 'Cops & robbers', 'The campaign', 'Chaos mode' }, 25, 'next')
end, false)

-- /votekeep  -> keep the current modifier/feature, or bin it
RegisterCommand('votekeep', function()
    startVote('Keep this build?', { 'Keep it', 'Bin it' }, 15, 'keepmod')
end, false)

-- Act on the ones that trigger something.
AddEventHandler('core:voteResult', function(tag, wi)
    if tag == 'next' then
        local map = { 'horde start', 'chase start', 'pint start lastorders', 'chaos' }
        if map[wi] then ExecuteCommand(map[wi]) end
    elseif tag == 'keepmod' then
        if wi == 2 then ExecuteCommand('mod off') end -- "Bin it"
    end
end)
