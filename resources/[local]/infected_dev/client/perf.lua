-- Live budget readout. This is how you answer "how many can we actually handle"
-- with measurements instead of guesses: crank /stress until FPS falls over, and
-- watch whether the ped pool or the network budget runs out first.
Perf = {}

local enabled = false
local samples = {}
local SAMPLE_WINDOW = 60

local function averageFps()
    if #samples == 0 then return 0 end

    local total = 0
    for _, value in ipairs(samples) do total = total + value end

    return total / #samples
end

local function recordFrame()
    local frameTime = GetFrameTime()
    if frameTime <= 0 then return end

    local next = { 1.0 / frameTime }
    for index = 1, math.min(#samples, SAMPLE_WINDOW - 1) do
        next[index + 1] = samples[index]
    end

    samples = next
end

-- Probes how many more mission entities the game will accept, so you can see
-- the ~110 networked ped ceiling approaching rather than hitting it blind.
local function networkHeadroom()
    for _, size in ipairs({ 60, 40, 25, 15, 10, 5, 1 }) do
        if CanRegisterMissionEntities(size, 0, 0, 0) then
            return size
        end
    end

    return 0
end

function Perf.toggle()
    enabled = not enabled
    return enabled
end

CreateThread(function()
    while true do
        if enabled then
            recordFrame()

            local pedPool = GetGamePool('CPed')
            local tracked = exports.infected:getTracked() or {}
            local fps     = averageFps()

            local lines = {
                ('FPS  ~%s~%.0f'):format(fps < 30 and 'r' or (fps < 50 and 'y' or 'g'), fps),
                ('MY INFECTED  ~y~%d'):format(#tracked),
                ('PEDS IN WORLD  ~y~%d'):format(#pedPool),
                ('NET HEADROOM  ~%s~%d+'):format(networkHeadroom() < 10 and 'r' or 'g', networkHeadroom()),
            }

            for index, line in ipairs(lines) do
                SetTextFont(4)
                SetTextScale(0.34, 0.34)
                SetTextColour(255, 255, 255, 210)
                SetTextOutline()

                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(line)
                EndTextCommandDisplayText(0.015, 0.30 + (index - 1) * 0.028)
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)
