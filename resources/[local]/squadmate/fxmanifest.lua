fx_version 'cerulean'
game 'gta5'

name 'squadmate'
description 'Week 1 prototype: every player gets one AI squadmate they can give orders to.'
author 'Stoke Back Mountain'
version '0.1.0'

shared_script 'config.lua'

client_scripts {
    'client/orders.lua',
    'client/squad.lua',
    'client/ui.lua',
    'client/main.lua',
    'client/fetch.lua',
}
