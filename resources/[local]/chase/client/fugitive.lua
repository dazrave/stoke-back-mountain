-- Fugitive brain: no weapons, position heartbeat, and the breadcrumbs they
-- leave while hidden - stolen-car reports and collision witnesses.
local nextKnockdown = 0
local memo = { lastVehicle = 0, firstVehicle = 0, bodyHealth = nil, nextWitness = 0, diedReported = false, hits = 0 }

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
                    -- A fresh car is a fresh set of chances.
                    memo.hits        = 0
                    ClearEntityLastWeaponDamage(vehicle)
                    ClearEntityLastDamageEntity(vehicle)
                end

                local body = GetVehicleBodyHealth(vehicle)
                local drop = memo.bodyHealth and (memo.bodyHealth - body) or 0.0

                -- Take enough punishment and the engine gives up.
                if Config.carHits.enabled then
                    local hit = false

                    -- Shot at. BULLET damage specifically (type 2), so kerbs
                    -- and lampposts can't use up the allowance this way.
                    if Config.carHits.bullets
                        and HasEntityBeenDamagedByWeapon(vehicle, 0, 2) then
                        hit = true
                    end

                    -- Rammed. HasEntityBeenDamagedByAnyVehicle is what keeps
                    -- scenery out of it: walls, kerbs and railings are map
                    -- collision rather than entities, and a lamppost or a bin
                    -- is an object, so none of them can ever set the
                    -- damaged-by-a-VEHICLE bit - only another motor can. The
                    -- damage threshold then throws away the traffic scrapes,
                    -- leaving the deliberate shunts the police want rewarding.
                    if Config.carHits.rams
                        and HasEntityBeenDamagedByAnyVehicle(vehicle)
                        and drop >= Config.carHits.minRamDamage then
                        hit = true
                    end

                    -- Cleared every pass, hit or not: these flags latch until
                    -- they're reset, and a stale one would let the next kerb
                    -- you clip land inside the same second as an old ram.
                    ClearEntityLastWeaponDamage(vehicle)
                    ClearEntityLastDamageEntity(vehicle)

                    if hit then
                        memo.hits = memo.hits + 1

                        local left = Config.carHits.hits - memo.hits

                        if left <= 0 then
                            SetVehicleEngineHealth(vehicle, 0.0)
                            SetVehicleUndriveable(vehicle, true)
                            BeginTextCommandThefeedPost('STRING')
                            AddTextComponentSubstringPlayerName('~r~ENGINE\'S GONE.~w~ Find another motor.')
                            EndTextCommandThefeedPostTicker(false, true)
                        elseif left <= 2 then
                            BeginTextCommandThefeedPost('STRING')
                            AddTextComponentSubstringPlayerName(('~y~She won\'t take much more. ~w~%d left.'):format(left))
                            EndTextCommandThefeedPostTicker(false, true)
                        end
                    end
                end

                -- Bumps and scrapes while hidden get phoned in by witnesses.
                if memo.bodyHealth and drop > 3.0
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

                -- On foot and shot: knocked down, not killed. That few seconds
                -- on the floor is the arrest window. Rate-limited so a second
                -- copper can't keep them there indefinitely.
                local knock = Config.nonLethal.knockdown
                if knock and knock.enabled
                    and not IsPedInAnyVehicle(ped, false)
                    and GetGameTimer() >= nextKnockdown then
                    nextKnockdown = GetGameTimer() + knock.everyMs
                    SetPedToRagdoll(ped, knock.downMs, knock.downMs, 0, true, true, false)
                    ChaseHUD.notify('~r~DOWN.~w~ Get up before they reach you.')
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


-- ===== police cars are not getaway cars =====
-- Enforced on the FUGITIVE'S OWN PED, which is the one entity their machine
-- genuinely owns.
--
-- The first go at this (#30) stamped SetVehicleDoorsLockedForPlayer onto every
-- police car within 60m. That reads as a local decision but isn't one: the
-- lock is stored ON THE VEHICLE, so it travels with the vehicle's synced game
-- state, and the player it names is a local index that is a different person
-- on a different machine. During the head start the fugitive stands 8m from
-- the whole fleet, so it branded every car the police were about to get into -
-- which is #32, the law stood outside their own cruisers at the off.
--
-- Refusing the door on our own ped cannot touch anybody else's car, and it
-- still covers the AI cruisers that turn up mid-round.
local POLICE_MODELS = {}
for _, list in ipairs({ Config.cop.vehicles or {}, Config.ai.models or {} }) do
    for _, model in ipairs(list) do
        POLICE_MODELS[GetHashKey(model)] = true
    end
end

CreateThread(function()
    local nextMoan = 0

    local function moan()
        if GetGameTimer() < nextMoan then return end
        nextMoan = GetGameTimer() + 4000
        ChaseHUD.notify('~r~Not that one.~w~ You are not nicking a police car.')
    end

    while true do
        Wait(200)

        local role, status = ChaseState()

        if Config.lockPoliceVehicles and role == 'fugitive' and status.phase ~= 'idle' then
            local ped       = PlayerPedId()
            local inVehicle = GetVehiclePedIsIn(ped, false)
            local wanted    = GetVehiclePedIsTryingToEnter(ped)

            if inVehicle ~= 0 and POLICE_MODELS[GetEntityModel(inVehicle)] then
                TaskLeaveVehicle(ped, inVehicle, 4160)
                moan()
            elseif wanted ~= 0 and POLICE_MODELS[GetEntityModel(wanted)] then
                ClearPedTasks(ped)
                moan()
            end
        end
    end
end)
