-- Floating label over every infected: type, distance, and whether a stalker has
-- triggered. This is the fastest way to tell whether the stalker mechanic is
-- actually firing or just looking like a teleport.
Overlay = {}

local enabled = false
local MAX_LABEL_DISTANCE = 120.0

local function drawText3D(coords, text, colour)
    local onScreen, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    SetTextFont(4)
    SetTextScale(0.32, 0.32)
    SetTextColour(colour[1], colour[2], colour[3], 220)
    SetTextOutline()
    SetTextCentre(true)

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(screenX, screenY)
end

function Overlay.toggle()
    enabled = not enabled
    return enabled
end

CreateThread(function()
    while true do
        if enabled then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local tracked      = exports.infected:getTracked() or {}

            for _, entry in ipairs(tracked) do
                if entry.ped and DoesEntityExist(entry.ped) and not IsEntityDead(entry.ped) then
                    local coords   = GetEntityCoords(entry.ped)
                    local distance = #(coords - playerCoords)

                    if distance < MAX_LABEL_DISTANCE then
                        local colour = entry.sprinting and { 255, 80, 80 } or { 180, 220, 255 }
                        local label  = ('%s  %.0fm%s'):format(
                            entry.archetype,
                            distance,
                            entry.sprinting and '  >> SPRINTING' or ''
                        )

                        drawText3D(coords + vector3(0.0, 0.0, 1.1), label, colour)
                    end
                end
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)
