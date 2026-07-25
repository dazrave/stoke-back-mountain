-- core: the vote panel. Shows the live vote on screen with a countdown and
-- running tally, and lets you cast with the number keys (great on camera — the
-- audience watches the bars move). Number keys are suppressed from swapping
-- weapons while a vote is up.
local vote = { active = false, question = '', options = {}, counts = {}, endsAt = 0, mine = nil }

RegisterNetEvent('core:voteStart', function(question, options, seconds)
    vote = {
        active = true, question = question, options = options, counts = {},
        endsAt = GetGameTimer() + (seconds * 1000), mine = nil,
    }
    for i = 1, #options do vote.counts[i] = 0 end
end)

RegisterNetEvent('core:voteTally', function(counts)
    if vote.active then vote.counts = counts end
end)

RegisterNetEvent('core:voteEnd', function()
    vote.active = false
end)

local function line(text, x, y, scale, r, g, b)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, 230)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

CreateThread(function()
    while true do
        if vote.active then
            Wait(0)

            local x    = 0.76
            local y    = 0.32
            local secs = math.max(0, math.ceil((vote.endsAt - GetGameTimer()) / 1000))

            line(('~y~VOTE  ·  %ds'):format(secs), x, y, 0.4, 245, 200, 66)
            y = y + 0.035
            line(vote.question, x, y, 0.34, 255, 255, 255)
            y = y + 0.04

            for i = 1, math.min(#vote.options, 9) do
                local c   = vote.counts[i] or 0
                local mine = (vote.mine == i)
                local r, g, b = 255, 255, 255
                if mine then r, g, b = 120, 240, 130 end
                line(('[%d] %s  ~w~%d'):format(i, vote.options[i], c), x, y, 0.32, r, g, b)
                y = y + 0.032
            end

            -- Cast with number keys; block them from swapping weapons.
            for i = 1, math.min(#vote.options, 9) do
                DisableControlAction(0, 156 + i, true)
                if IsDisabledControlJustPressed(0, 156 + i) then
                    vote.mine = i
                    TriggerServerEvent('core:castVote', i)
                end
            end
        else
            Wait(200)
        end
    end
end)
