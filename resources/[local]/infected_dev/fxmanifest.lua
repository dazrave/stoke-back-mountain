fx_version 'cerulean'
game 'gta5'

name 'infected_dev'
description 'Testing tools for the infected mode. Stop this resource for game night.'
author 'Stoke Back Mountain'
version '0.1.0'

dependency 'infected'

client_scripts {
    'client/overlay.lua',
    'client/noclip.lua',
    'client/perf.lua',
    'client/tools.lua',
    'client/main.lua',
}

server_scripts {
    'server/commands.lua',
}
