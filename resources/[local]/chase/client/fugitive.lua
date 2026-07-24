-- Fugitive brain: no weapons, position heartbeat, and the breadcrumbs they
-- leave while hidden - stolen-car reports and collision witnesses.
local memo = { lastVehicle = 0, firstVehicle = 0, bodyHealth = nil, nextWitness = 0, diedReported = false }

local function whereAmI()
    local pos    = GetEntityCoords(PlayerPedId())
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(pos.x, pos.y, pos.z))
    return pos, ('near %s'):format(street or 'somewhere')
end

-- No guns. Ever. Checked continuously in case they get creative.
CreateThread(function()
    while true do
        Wait(5000)

        local role, status = ChaseState()
        if role == 'fugitive' and status.phase ~= 'idle' then
            RemoveAllPedWeapons(PlayerPedId(), true)
        end
    end
end)

-- Heartbeat: the server only ever reveals this during the final alert.
CreateThread(function()
    while true do
        Wait(1000)

        local role, status = ChaseState()
        if role == 'fugitive' and status.phase ~= 'idle' then
            -- Sent during the head start too: the police are watching you go.
            TriggerServerEvent('chase:heartbeat', GetEntityCoords(PlayerPedId()))
        end
    end
end)

-- Breadcrumbs.
CreateThread(function()
    while true do
        Wait(1000)

        local role, status = ChaseState()

        if role == 'fugitive' and status.phase == 'active' then
            local ped     = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                -- New set of wheels. The first car of the round is "yours";
                -- every one after that got jacked from somebody.
                if vehicle ~= memo.lastVehicle then
                    if memo.firstVehicle == 0 then
                        memo.firstVehicle = vehicle
                    elseif vehicle ~= memo.firstVehicle and not status.tracking then
                        local pos, street = whereAmI()
                        local name = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
                        TriggerServerEvent('chase:report', 'stolen', pos,
                            ('a %s %s'):format(name ~= 'NULL' and name or 'vehicle', street))
                    end

                    memo.lastVehicle = vehicle
                    memo.bodyHealth  = GetVehicleBodyHealth(vehicle)
                end

                -- Bumps and scrapes while hidden get phoned in by witnesses.
                local body = GetVehicleBodyHealth(vehicle)

                if memo.bodyHealth and (memo.bodyHealth - body) > 3.0
                    and not status.tracking
                    and GetGameTimer() > memo.nextWitness then
                    memo.nextWitness = GetGameTimer() + Config.reports.witnessGapMs

                    local pos, street = whereAmI()
                    TriggerServerEvent('chase:report', 'witness', pos, street)
                end

                memo.bodyHealth = body
            end
        end
    end
end)

-- Death: who did this? A cop bullet shames the force; scenery closes the case.
CreateThread(function()
    while true do
        Wait(1000)

        local role, status = ChaseState()

        if role == 'fugitive' and status.phase ~= 'idle' then
            local ped = PlayerPedId()

            local vehicle = GetVehiclePedIsIn(ped, false)

            -- Wrapped it round a lamppost. A bike doesn't always kill you when
            -- it goes up, so the wreck itself counts: no vehicle, no escape.
            if vehicle ~= 0 and IsEntityDead(vehicle) and not memo.diedReported then
                memo.diedReported = true
                ChaseHUD.notify('~r~You wrote it off.')
                TriggerServerEvent('chase:died', false)

            elseif (IsEntityDead(ped) or IsPedFatallyInjured(ped)) and not memo.diedReported then
                memo.diedReported = true

                local cause = GetPedSourceOfDeath(ped)
                local byCop = false

                if cause ~= 0 and cause ~= ped and DoesEntityExist(cause) then
                    local owner = NetworkGetEntityOwner(cause)
                    byCop = owner ~= -1 and owner ~= PlayerId()
                end

                TriggerServerEvent('chase:died', byCop)
            end
        else
            memo.diedReported = false
        end
    end
end)

-- Getting hauled out of the car by the law. Runs on the FUGITIVE'S client
-- because your own machine owns your own ped - the same reason the zombie
-- version works. Slow down with a copper on foot beside you and you're out.
CreateThread(function()
    local clingMs = 0
    local warned  = false

    while true do
        Wait(200)

        local grabbed = false
        local role, status = ChaseState()

        if role == 'fugitive' and status.phase == 'active' then
            local ped     = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 and not IsEntityDead(ped)
                and GetEntitySpeed(vehicle) < Config.cop.dragOut.maxSpeed then
                local at = GetEntityCoords(vehicle)

                for _, playerId in ipairs(GetActivePlayers()) do
                    if playerId ~= PlayerId() then
                        local cop = GetPlayerPed(playerId)

                        if DoesEntityExist(cop) and not IsEntityDead(cop)
                            and GetVehiclePedIsIn(cop, false) == 0
                            and #(GetEntityCoords(cop) - at) < Config.cop.dragOut.radius then
                            grabbed = true
                            break
                        end
                    end
                end

                if grabbed then
                    clingMs = clingMs + 200

                    if not warned then
                        warned = true
                        ChaseHUD.notify('~r~THEY\'RE AT THE WINDOW!~w~ Move!')
                    end

                    if clingMs >= Config.cop.dragOut.grabMs then
                        clingMs = 0
                        warned  = false

                        TaskLeaveVehicle(ped, vehicle, 4160)
                        SetPedToRagdoll(ped, 1500, 1500, 0, true, true, false)
                        ChaseHUD.notify('~r~PULLED OUT OF THE CAR.')
                    end
                end
            end
        end

        if not grabbed then
            clingMs = 0
            warned  = false
        end
    end
end)

-- Non-lethal enforcement. Runs on the fugitive's own client, which owns the
-- ped, so no shot can ever drop them below the floor. They still take the
-- hit - the health bar falls, they limp, they bleed - but the round can only
-- ever end in an arrest, a crash, or a clean getaway.
CreateThread(function()
    local wasHit = false

    while true do
        Wait(0)

        local role, status = ChaseState()

        if role == 'fugitive' and status.phase ~= 'idle' and Config.nonLethal.enabled then
            local ped    = PlayerPedId()
            local health = GetEntityHealth(ped)

            if not IsEntityDead(ped) and health < Config.nonLethal.floorHealth then
                SetEntityHealth(ped, Config.nonLethal.floorHealth)

                if not wasHit then
                    wasHit = true
                    ChaseHUD.notify('~r~You\'re hit.~w~ Still standing. Keep going.')
                    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.4)
                end
            elseif health > Config.nonLethal.limpBelow then
                wasHit = false
            end

            -- Winded and slowed while shot up, but never finished off.
            if health <= Config.nonLethal.limpBelow then
                SetPedMoveRateOverride(ped, 0.85)
            else
                SetPedMoveRateOverride(ped, 1.0)
            end
        else
            Wait(500)
        end
    end
end)
