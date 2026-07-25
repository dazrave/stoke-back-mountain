fx_version 'cerulean'
game 'gta5'

name 'core'
description 'Stokeback core: the shared foundation every mode sits on. First job — keep the city alive.'
author 'Stokeback Mountain'
version '0.1.0'

client_scripts {
    'client/world.lua',
    'client/hud.lua',
    'client/life.lua',
    'client/modifiers.lua',
    'client/spectator.lua',
    'client/vote.lua',
    'client/heat.lua',
}

server_scripts {
    'server/stats.lua',
    'server/rules.lua',
    'server/director.lua',
    'server/vote.lua',
    'server/heat.lua',
}
