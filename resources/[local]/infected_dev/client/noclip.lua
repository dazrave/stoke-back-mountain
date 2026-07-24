-- Fly camera. The only sane way to watch a 60-strong swarm behave from above
-- without being eaten in the first two seconds.
Noclip = {}

local enabled = false
local speed   = 1.0

local SPEEDS  = { min = 0.2, max = 12.0, step = 0.4 }

local CONTROL = {
    forward = 32, back = 33, left = 34, right = 35,
    up = 44, down = 46,       -- Q / E
    faster = 241, slower = 242, -- mouse wheel
}

function Noclip.toggle()
    enabled = not enabled

    local ped = PlayerPedId()
    SetEntityVisible(ped, not enabled, false)
    SetEntityCollision(ped, not enabled, not enabled)
    SetEntityInvincible(ped, enabled)
    FreezeEntityPosition(ped, enabled)

    if not enabled then
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)
    end

    return enabled
end

function Noclip.isEnabled()
    return enabled
end

CreateThread(function()
    while true do
        if enabled then
            local ped    = PlayerPedId()
            local camRot = GetGameplayCamRot(2)
            local coords = GetEntityCoords(ped)

            if IsControlPressed(0, CONTROL.faster) then
                speed = math.min(SPEEDS.max, speed + SPEEDS.step)
            elseif IsControlPressed(0, CONTROL.slower) then
                speed = math.max(SPEEDS.min, speed - SPEEDS.step)
            end

            local pitch = math.rad(camRot.x)
            local yaw   = math.rad(camRot.z)

            local forward = vector3(
                -math.sin(yaw) * math.cos(pitch),
                 math.cos(yaw) * math.cos(pitch),
                 math.sin(pitch)
            )
            local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)

            local move = vector3(0.0, 0.0, 0.0)
            if IsControlPressed(0, CONTROL.forward) then move = move + forward end
            if IsControlPressed(0, CONTROL.back)    then move = move - forward end
            if IsControlPressed(0, CONTROL.right)   then move = move + right   end
            if IsControlPressed(0, CONTROL.left)    then move = move - right   end
            if IsControlPressed(0, CONTROL.up)      then move = move + vector3(0.0, 0.0, 1.0) end
            if IsControlPressed(0, CONTROL.down)    then move = move - vector3(0.0, 0.0, 1.0) end

            if #move > 0.0 then
                SetEntityCoordsNoOffset(ped, coords + move * speed, true, true, false)
            end

            SetEntityHeading(ped, camRot.z)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)

            Wait(0)
        else
            Wait(300)
        end
    end
end)
