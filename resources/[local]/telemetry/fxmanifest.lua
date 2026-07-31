fx_version 'cerulean'
game 'gta5'

name 'telemetry'
description 'Route telemetry: samples player positions so the game modes can be tuned to how people actually play.'
author 'Stokeback Mountain'
version '0.1.0'

client_scripts {
    '@core/client/lib.lua',
    'client/main.lua',
}

server_script 'server/main.lua'

dependency 'core'
