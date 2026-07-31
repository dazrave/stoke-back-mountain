fx_version 'cerulean'
game 'gta5'

name 'squadmate'
description 'Week 1 prototype: every player gets one AI squadmate they can give orders to.'
author 'Stokeback Mountain'
version '0.1.0'

shared_script 'config.lua'

client_scripts {
    '@core/client/lib.lua',
    'client/orders.lua',
    'client/squad.lua',
    'client/ui.lua',
    'client/main.lua',
    'client/fetch.lua',
}

dependency 'core'
