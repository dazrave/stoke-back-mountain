-- Director cam: a clean spectator angle for capturing footage from a spare rig.
--
-- Reuses the spectator native the pint mode already relies on
-- (NetworkSetInSpectatorMode). The operator's own character is frozen,
-- invisible and invincible so it never wanders into shot or dies; the camera
-- rides whichever player is in the thick of it. No on-screen overlay while
-- filming — the whole point is a clean feed — so status only ever prints to
-- chat, which OBS isn't capturing.
--
-- Commands (type them on the director rig only):
--   /director   toggle the camera on/off
--   /dauto      toggle auto-follow-the-action vs manual
--   /dnext      manual: next player
--   /dprev      manual: previous player

local state = {
    on       = false,
    auto     = DirectorConfig.startInAuto,
    target   = nil, -- server id of the player being watched
    lastAt   = 0,
}

-- Latest positions, straight off the telemetry relay (server broadcasts every
-- few seconds). Keyed by server id.
local mates = {}
RegisterNetEvent('telemetry:mates', function(list)
    local next = {}
    for _, m in ipairs(list or {}) do next[m.id] = m end
    mates = next
end)

local function me()
    return GetPlayerServerId(PlayerId())
end

-- server id -> ped, only if that player is in scope on this machine.
local function pedOf(serverId)
    local lp = GetPlayerFromServerId(serverId)
    if lp == -1 then return nil end
    local ped = GetPlayerPed(lp)
    return DoesEntityExist(ped) and ped or nil
end

-- Everyone but us who we can actually spectate right now.
local function watchable()
    local out = {}
    for _, id in ipairs(GetActivePlayers()) do
        local sid = GetPlayerServerId(id)
        if sid ~= me() then
            local ped = GetPlayerPed(id)
            if DoesEntityExist(ped) then out[#out + 1] = sid end
        end
    end
    table.sort(out)
    return out
end

-- The action = whoever has the most other players packed around them. Falls
-- back to the first watchable player if nobody's clustered yet.
local function pickAction()
    local best, bestScore
    for sid, m in pairs(mates) do
        if sid ~= me() and pedOf(sid) then
            local score = 0
            for other, n in pairs(mates) do
                if other ~= sid then
                    local dx, dy = m.x - n.x, m.y - n.y
                    if (dx * dx + dy * dy) ^ 0.5 < DirectorConfig.clusterRadius then
                        score = score + 1
                    end
                end
            end
            if not bestScore or score > bestScore then
                best, bestScore = sid, score
            end
        end
    end
    if best then return best end
    local list = watchable()
    return list[1]
end

local function spectate(serverId)
    local ped = serverId and pedOf(serverId)
    if not ped then return false end
    NetworkSetInSpectatorMode(true, ped)
    state.target = serverId
    state.lastAt = GetGameTimer()
    return true
end

local function nameOf(serverId)
    return (mates[serverId] and mates[serverId].name)
        or GetPlayerName(GetPlayerFromServerId(serverId))
        or ('#' .. tostring(serverId))
end

local function tell(msg)
    TriggerEvent('chat:addMessage', { color = { 245, 200, 66 }, args = { 'director', msg } })
end

local function enable()
    local ped = PlayerPedId()
    -- Park our own body out of the way: unseen, unkillable, unmoving.
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)

    state.on = true
    if not spectate(pickAction()) then
        tell('nobody to spectate yet — will pick up when players are in.')
    else
        tell(('ON — %s, %s'):format(state.auto and 'auto-follow' or 'manual', nameOf(state.target)))
    end
end

local function disable()
    NetworkSetInSpectatorMode(false, PlayerPedId())
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    state.on = false
    state.target = nil
    tell('OFF')
end

RegisterCommand('director', function()
    if state.on then disable() else enable() end
end, false)

RegisterCommand('dauto', function()
    state.auto = not state.auto
    tell(state.auto and 'auto-follow ON' or 'manual')
end, false)

local function step(dir)
    if not state.on then return end
    state.auto = false
    local list = watchable()
    if #list == 0 then return end

    local idx = 1
    for i, sid in ipairs(list) do
        if sid == state.target then idx = i break end
    end
    idx = ((idx - 1 + dir) % #list) + 1

    if spectate(list[idx]) then
        tell('watching ' .. nameOf(list[idx]))
    end
end

RegisterCommand('dnext', function() step(1) end, false)
RegisterCommand('dprev', function() step(-1) end, false)

-- Keep the feed clean and the camera live.
CreateThread(function()
    while true do
        if state.on then
            Wait(0)
            HideHudAndRadarThisFrame()

            -- Target left / went out of scope: re-pick immediately.
            if not (state.target and pedOf(state.target)) then
                spectate(pickAction())
            elseif state.auto and (GetGameTimer() - state.lastAt) > DirectorConfig.switchIntervalMs then
                local want = pickAction()
                if want and want ~= state.target then
                    spectate(want)
                end
            end
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and state.on then disable() end
end)
