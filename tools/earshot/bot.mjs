// Earshot: sits in the Discord voice channel and writes down what everyone says.
//
// Discord hands out a SEPARATE audio stream per speaker, which is the whole
// reason for using a bot rather than recording the desktop: every utterance
// arrives already attributed to a person, and none of the game audio comes
// with it.
//
// One file per utterance, not fixed-length chunks. Whisper is far more
// accurate on a single sentence with clean silence either side, and it means
// the transcript is naturally ordered by who said what, when.
import 'dotenv/config';

import { Client, GatewayIntentBits } from 'discord.js';
import {
    joinVoiceChannel,
    EndBehaviorType,
    entersState,
    VoiceConnectionStatus,
} from '@discordjs/voice';
import prism from 'prism-media';

import { mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE      = dirname(fileURLToPath(import.meta.url));
const QUEUE_DIR = process.env.QUEUE_DIR || join(HERE, 'queue');

// Discord gives us 48kHz stereo signed 16-bit.
const SAMPLE_RATE = 48000;
const CHANNELS    = 2;

// Anything shorter than this is a cough, a door, or someone knocking their
// desk. Transcribing it wastes time and produces hallucinated words.
const MIN_MS = Number(process.env.MIN_UTTERANCE_MS || 700);

// How long a gap counts as "they've stopped talking".
const SILENCE_MS = Number(process.env.SILENCE_MS || 900);

mkdirSync(QUEUE_DIR, { recursive: true });

function wavHeader(dataLength) {
    const header    = Buffer.alloc(44);
    const byteRate  = SAMPLE_RATE * CHANNELS * 2;
    const blockAlign = CHANNELS * 2;

    header.write('RIFF', 0);
    header.writeUInt32LE(36 + dataLength, 4);
    header.write('WAVE', 8);
    header.write('fmt ', 12);
    header.writeUInt32LE(16, 16);          // PCM chunk size
    header.writeUInt16LE(1, 20);           // format: PCM
    header.writeUInt16LE(CHANNELS, 22);
    header.writeUInt32LE(SAMPLE_RATE, 24);
    header.writeUInt32LE(byteRate, 28);
    header.writeUInt16LE(blockAlign, 32);
    header.writeUInt16LE(16, 34);          // bits per sample
    header.write('data', 36);
    header.writeUInt32LE(dataLength, 40);

    return header;
}

// Filenames can't be trusted to hold a Discord display name unedited.
function safeName(name) {
    return String(name).replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 32) || 'unknown';
}

const client = new Client({
    intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildVoiceStates],
});

const names     = new Map(); // userId -> display name, cached
const listening = new Set(); // userIds we already have a live subscription for

async function displayName(userId) {
    if (names.has(userId)) return names.get(userId);

    let name = userId;
    try {
        const user = await client.users.fetch(userId);
        name = user.globalName || user.username || userId;
    } catch {
        // Falls back to the raw id, which is still a usable label.
    }

    names.set(userId, name);
    return name;
}

function capture(receiver, userId) {
    if (listening.has(userId)) return;
    listening.add(userId);

    const opus = receiver.subscribe(userId, {
        end: { behavior: EndBehaviorType.AfterSilence, duration: SILENCE_MS },
    });

    const decoder = new prism.opus.Decoder({
        rate: SAMPLE_RATE,
        channels: CHANNELS,
        frameSize: 960,
    });

    const chunks = [];
    const pcm    = opus.pipe(decoder);

    pcm.on('data', (chunk) => chunks.push(chunk));

    pcm.on('end', async () => {
        listening.delete(userId);

        const audio = Buffer.concat(chunks);
        const ms    = (audio.length / (SAMPLE_RATE * CHANNELS * 2)) * 1000;

        if (ms < MIN_MS) return;

        const who  = safeName(await displayName(userId));
        const file = join(QUEUE_DIR, `${Date.now()}__${who}.wav`);

        writeFileSync(file, Buffer.concat([wavHeader(audio.length), audio]));
        console.log(`[earshot] ${who}: ${Math.round(ms)}ms -> ${file}`);
    });

    pcm.on('error', (error) => {
        listening.delete(userId);
        console.error('[earshot] stream error:', error.message);
    });
}

client.once('clientReady', async () => {
    console.log(`[earshot] logged in as ${client.user.tag}`);

    const guild   = await client.guilds.fetch(process.env.GUILD_ID);
    const channel = await guild.channels.fetch(process.env.VOICE_CHANNEL_ID);

    const connection = joinVoiceChannel({
        channelId: channel.id,
        guildId: guild.id,
        adapterCreator: guild.voiceAdapterCreator,
        selfDeaf: false,  // deafened bots receive nothing at all
        selfMute: true,   // it only listens; it has nothing to say
    });

    await entersState(connection, VoiceConnectionStatus.Ready, 20_000);
    console.log(`[earshot] listening in #${channel.name}`);

    const receiver = connection.receiver;
    receiver.speaking.on('start', (userId) => capture(receiver, userId));

    connection.on(VoiceConnectionStatus.Disconnected, async () => {
        // A move between channels looks identical to a drop at first; give it
        // a moment to resolve itself before tearing anything down.
        try {
            await Promise.race([
                entersState(connection, VoiceConnectionStatus.Signalling, 5_000),
                entersState(connection, VoiceConnectionStatus.Connecting, 5_000),
            ]);
        } catch {
            console.log('[earshot] disconnected');
            connection.destroy();
        }
    });
});

client.login(process.env.DISCORD_TOKEN);
