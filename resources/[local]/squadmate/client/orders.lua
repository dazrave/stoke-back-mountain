-- Order definitions. These are pure data plus one apply function; applying an
-- order never mutates the order table or the squad passed in - it returns a new
-- squad table.
Orders = {}

local COMBAT_MOVEMENT = {
    stationary = 0,
    defensive  = 1, -- seeks cover, blind-fires
    offensive  = 2, -- advances but still uses cover
    reckless   = 3, -- suicidal flanking
}

Orders.definitions = {
    follow = {
        label    = 'FOLLOWING',
        movement = COMBAT_MOVEMENT.defensive,
        inGroup  = true,
        spacing  = 'close',
    },
    aggressive = {
        label    = 'AGGRESSIVE',
        movement = COMBAT_MOVEMENT.offensive,
        inGroup  = true,
        spacing  = 'far',
    },
    hold = {
        label    = 'HOLDING POSITION',
        movement = COMBAT_MOVEMENT.defensive,
        inGroup  = false,
        spacing  = nil,
    },
}

-- Returns a new squad table with the order applied, or the original squad plus
-- an error string if it could not be applied.
function Orders.apply(squad, orderName)
    local order = Orders.definitions[orderName]

    if not order then
        return squad, ('unknown order "%s"'):format(tostring(orderName))
    end

    if not squad or not squad.ped or not DoesEntityExist(squad.ped) then
        return squad, 'no living squadmate to give orders to'
    end

    local ped = squad.ped

    SetPedCombatMovement(ped, order.movement)

    if order.inGroup then
        SetPedAsGroupMember(ped, squad.groupId)
        SetPedNeverLeavesGroup(ped, true)
        SetGroupFormationSpacing(squad.groupId, Config.group.spacing[order.spacing], -1.0, -1.0)
        ClearPedTasks(ped)
    else
        RemovePedFromGroup(ped)
        TaskGuardCurrentPosition(ped, Config.guard.defensiveRadius, Config.guard.patrolRange, true)
    end

    return {
        ped     = squad.ped,
        groupId = squad.groupId,
        blip    = squad.blip,
        order   = orderName,
    }
end
