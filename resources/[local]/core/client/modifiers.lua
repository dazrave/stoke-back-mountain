-- core: the modifier of the night. One global rule warping the world, applied
-- each frame while it's on. Enter/exit is handled cleanly so switching off
-- puts everything back.
local active = 'off'
local DRUNK_SET = 'move_m@drunk@verydrunk'

local function cleanup(mod)
    local ped = PlayerPedId()
    if mod == 'moon' then
        SetGravityLevel(0) -- back to 9.8
    elseif mod == 'drunk' then
        ResetPedMovementClipset(ped, 0.0)
        ClearTimecycleModifier()
        SetPedIsDrunk(ped, false)
    end
end

RegisterNetEvent('core:modifier', function(name)
    if active ~= 'off' then cleanup(active) end
    active = name or 'off'

    if active == 'drunk' then
        RequestAnimSet(DRUNK_SET)
    end
end)

CreateThread(function()
    while true do
        if active == 'off' then
            Wait(300)
        else
            Wait(0)
            local ped = PlayerPedId()

            if active == 'moon' then
                SetGravityLevel(2) -- low, floaty

            elseif active == 'superjump' then
                SetSuperJumpThisFrame(PlayerId())

            elseif active == 'drunk' then
                if HasAnimSetLoaded(DRUNK_SET) then
                    SetPedMovementClipset(ped, DRUNK_SET, 1.0)
                end
                SetPedIsDrunk(ped, true)
                SetTimecycleModifier('spectator5') -- woozy blur
                ShakeGameplayCam('DRUNK_SHAKE', 0.35)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and active ~= 'off' then cleanup(active) end
end)
