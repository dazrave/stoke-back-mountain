-- Blip on your squadmate plus a one-line status readout of its current order.
UI = {}

function UI.attachBlip(ped)
    local blip = AddBlipForEntity(ped)

    SetBlipSprite(blip, Config.blip.sprite)
    SetBlipColour(blip, Config.blip.colour)
    SetBlipScale(blip, Config.blip.scale)
    SetBlipAsShortRange(blip, true)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.blip.name)
    EndTextCommandSetBlipName(blip)

    return blip
end

function UI.drawStatus(text)
    SetTextFont(4)
    SetTextScale(Config.ui.scale, Config.ui.scale)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextCentre(true)

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(Config.ui.statusX, Config.ui.statusY)
end

-- The mechanics live in the core toolkit; UI keeps the name so callers read
-- the same as ever.
UI.notify = SBM.notify
