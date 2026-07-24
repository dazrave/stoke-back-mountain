fx_version 'cerulean'
game 'gta5'

name 'infected'
description '28 Frags Later - wave-based infected horde. One hit and you are gone.'
author 'Stokeback Mountain'
version '0.1.0'

shared_script 'config.lua'

client_scripts {
    'client/archetypes.lua',
    'client/spawner.lua',
    'client/behaviour.lua',
    'client/survival.lua',
    'client/hud.lua',
    'client/hijack.lua',
    'client/main.lua',
}

server_scripts {
    'server/waves.lua',
}
