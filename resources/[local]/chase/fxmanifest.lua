fx_version 'cerulean'
game 'gta5'

name 'chase'
description 'Scrap Run - one fugitive, everyone else is police. Line-of-sight manhunt.'
author 'Stokeback Mountain'
version '0.1.0'

shared_scripts {
    '@core/shared/loadouts.lua',
    'config.lua',
}

client_scripts {
    '@core/client/lib.lua',
    'client/main.lua',
    'client/cop.lua',
    'client/fugitive.lua',
    'client/ai.lua',
    'client/heli.lua',
}

server_script 'server/round.lua'

dependency 'core'
