-- core: the shared HUD. Crew name tags (so the camera and the viewers always
-- know who's who), a big-text announcer for the dramatic beats, and a death
-- feed the AI director snarks over.

-- ===== name tags =====
local PALETTE = {
    { 245, 200, 66 }, { 90, 169, 255 }, { 88, 199, 119 },
    { 200, 120, 255 }, { 255, 120, 120 }, { 120, 220, 220 },
}

local function colourFor(serverId)
    return table.unpack(PALETTE[(serverId % #PALETTE) + 1])
end

CreateThread(function()
    while true do
        Wait(0)
        local me   = PlayerPedId()
        local from = GetEntityCoords(me)

        for _, pid in ipairs(GetActivePlayers()) do
            if pid ~= PlayerId() then
                local ped = GetPlayerPed(pid)
                if DoesEntityExist(ped) and not IsEntityDead(ped) then
                    local at = GetEntityCoords(ped)
                    if #(at - from) < 55.0 then
                        local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.32)
                        local on, sx, sy = World3dToScreen2d(head.x, head.y, head.z)
                        if on then
                            local r, g, b = colourFor(GetPlayerServerId(pid))
                            SetTextFont(4)
                            SetTextScale(0.32, 0.32)
                            SetTextColour(r, g, b, 220)
                            SetTextOutline()
                            SetTextCentre(true)
                            BeginTextCommandDisplayText('STRING')
                            AddTextComponentSubstringPlayerName(GetPlayerName(pid))
                            EndTextCommandDisplayText(sx, sy)
                        end
                    end
                end
            end
        end
    end
end)

-- ===== announcer (big centred text) =====
local ann = { text = nil, sub = nil, until_ = 0 }

RegisterNetEvent('core:announce', function(text, sub, ms)
    ann = { text = text, sub = (sub ~= '' and sub or nil), until_ = GetGameTimer() + (ms or 4000) }
end)

CreateThread(function()
    while true do
        if ann.text and ann.text ~= '' and GetGameTimer() < ann.until_ then
            Wait(0)
            SetTextFont(1)
            SetTextScale(1.4, 1.4)
            SetTextColour(245, 200, 66, 235)
            SetTextOutline()
            SetTextCentre(true)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(ann.text)
            EndTextCommandDisplayText(0.5, 0.28)

            if ann.sub then
                SetTextFont(4)
                SetTextScale(0.5, 0.5)
                SetTextColour(255, 255, 255, 220)
                SetTextOutline()
                SetTextCentre(true)
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(ann.sub)
                EndTextCommandDisplayText(0.5, 0.42)
            end
        else
            Wait(150)
        end
    end
end)

-- ===== feed (killfeed-style ticker) =====
RegisterNetEvent('core:feed', function(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end)
