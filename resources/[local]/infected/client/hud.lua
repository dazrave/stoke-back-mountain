-- Wave / kills / alive readout, plus the wave-incoming shout.
HUD = {}

local state = { wave = 0, kills = 0, alive = 0, myKills = 0 }

function HUD.set(nextState)
    state = {
        wave    = nextState.wave    or state.wave,
        kills   = nextState.kills   or state.kills,
        alive   = nextState.alive   or state.alive,
        myKills = nextState.myKills or state.myKills,
    }
end

function HUD.notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, true)
end

function HUD.draw()
    local text = ('WAVE ~y~%d~w~   ALIVE ~r~%d~w~   KILLS ~g~%d~w~   YOURS ~b~%d')
        :format(state.wave, state.alive, state.kills, state.myKills)

    SetTextFont(4)
    SetTextScale(Config.hud.scale, Config.hud.scale)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextCentre(true)

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(Config.hud.x, Config.hud.y)
end

function HUD.start()
    CreateThread(function()
        while true do
            -- Only while the apocalypse is actually on: otherwise this sits on
            -- top of whatever other game mode is running.
            if Survival and Survival.engaged then
                HUD.draw()
                Wait(0)
            else
                Wait(400)
            end
        end
    end)
end
