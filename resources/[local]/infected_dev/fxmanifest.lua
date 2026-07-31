fx_version 'cerulean'
game 'gta5'

name 'infected_dev'
description 'Testing tools for the infected mode. Stop this resource for game night.'
author 'Stokeback Mountain'
version '0.1.0'

dependency 'infected'
dependency 'core'

client_scripts {
    '@core/client/lib.lua',
    'client/overlay.lua',
    'client/noclip.lua',
    'client/perf.lua',
    'client/tools.lua',
    'client/main.lua',
}

server_scripts {
    'server/commands.lua',
}
