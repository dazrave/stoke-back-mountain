-- core: server side of police heat. Heat itself lives on each client; the
-- server just hears about spikes so the cut-list can flag the chase and the
-- room gets a bit of snark when someone brings the whole city down on their head.

local LINES = {
    [2] = '%s picked a fight with Los Santos PD.',
    [3] = '%s is properly wanted now.',
    [4] = "%s has half the division after them.",
    [5] = '%s vs the entire city. Get the popcorn.',
}

RegisterNetEvent('core:heatMark', function(level)
    local src = source
    if src <= 0 then return end
    level = tonumber(level) or 0

    local name = GetPlayerName(src) or ('#' .. src)
    TriggerEvent('telemetry:mark', ('heat:%d:%s'):format(level, name)) -- cut-list signal

    local line = LINES[level]
    if line then
        TriggerClientEvent('core:feed', -1, line:format(name))
    end
end)
