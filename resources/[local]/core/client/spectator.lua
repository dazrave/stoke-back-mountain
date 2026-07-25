-- core: a standard spectator anyone can use. Any mode with "no respawn" just
-- fires  TriggerClientEvent('core:spectate', deadPlayer, true)  and core drops
-- them cleanly into watching the living (resurrected invisible so there's no
-- stuck death-cam). /spectate toggles it by hand; /specnext cycles.
local spec = { on = false, target = nil }

local function living()
    local out = {}
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local ped = GetPlayerPed(pid)
            if DoesEntityExist(ped) and not IsEntityDead(ped) then out[#out + 1] = pid end
        end
    end
    table.sort(out)
    return out
end

local function watch(pid)
    local ped = pid and GetPlayerPed(pid)
    if not (ped and DoesEntityExist(ped)) then return false end
    NetworkSetInSpectatorMode(true, ped)
    spec.target = pid
    return true
end

local function tell(msg)
    TriggerEvent('chat:addMessage', { color = { 200, 200, 200 }, args = { 'spectate', msg } })
end

local function enter()
    local ped = PlayerPedId()

    -- Resurrect on the spot but invisible, so there's no wasted-screen and the
    -- body isn't lying in shot.
    if IsEntityDead(ped) then
        local at = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(at.x, at.y, at.z + 1.0, GetEntityHeading(ped), false, false)
        ped = PlayerPedId()
    end
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)

    spec.on = true
    local list = living()
    if list[1] then
        watch(list[1])
        tell('watching ' .. GetPlayerName(list[1]) .. '  (/specnext to switch)')
    else
        tell('nobody alive to watch yet — will pick up when someone is')
    end
end

local function leave()
    NetworkSetInSpectatorMode(false, PlayerPedId())
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    spec.on = false
    spec.target = nil
end

RegisterCommand('spectate', function() if spec.on then leave() else enter() end end, false)

RegisterCommand('specnext', function()
    if not spec.on then return end
    local list = living()
    if #list == 0 then return end
    local idx = 1
    for i, pid in ipairs(list) do if pid == spec.target then idx = i break end end
    idx = (idx % #list) + 1
    if watch(list[idx]) then tell('watching ' .. GetPlayerName(list[idx])) end
end, false)

-- Modes drive it: on = drop into spectate, off = come back.
RegisterNetEvent('core:spectate', function(on)
    if on then if not spec.on then enter() end
    else if spec.on then leave() end end
end)

-- Keep the camera on someone alive.
CreateThread(function()
    while true do
        Wait(1000)
        if spec.on then
            local ped = spec.target and GetPlayerPed(spec.target)
            if not (ped and DoesEntityExist(ped) and not IsEntityDead(ped)) then
                local list = living()
                if list[1] then watch(list[1]) end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and spec.on then leave() end
end)
