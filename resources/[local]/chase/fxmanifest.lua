fx_version 'cerulean'
game 'gta5'

name 'chase'
description 'Scrap Run - one fugitive, everyone else is police. Line-of-sight manhunt.'
author 'Stokeback Mountain'
version '0.1.0'

shared_script 'config.lua'

client_scripts {
    'client/main.lua',
    'client/cop.lua',
    'client/fugitive.lua',
    'client/ai.lua',
}

server_script 'server/round.lua'
