fx_version 'cerulean'
game 'gta5'

name 'pint'
description 'A Nice Cold Pint - get to the Yellow Jack, have a pint, wait for all this to blow over.'
author 'Stokeback Mountain'
version '0.1.0'

dependencies {
    'core',
    'infected',
}

shared_scripts {
    '@core/shared/loadouts.lua',
    'config.lua',
}

client_scripts {
    '@core/client/lib.lua',
    'client/hud.lua',
    'client/vehicles.lua',
    'client/moments.lua',
    'client/loot.lua',
    'client/main.lua',
}

server_script 'server/mission.lua'
