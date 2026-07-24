fx_version 'cerulean'
game 'gta5'

name 'pint'
description 'A Nice Cold Pint - get to the Yellow Jack, have a pint, wait for all this to blow over.'
author 'Stoke Back Mountain'
version '0.1.0'

dependency 'infected'

shared_script 'config.lua'

client_scripts {
    'client/hud.lua',
    'client/vehicles.lua',
    'client/moments.lua',
    'client/loot.lua',
    'client/main.lua',
}

server_script 'server/mission.lua'
