# Earshot

Sits in the Discord voice channel, writes down what everyone says, and every
five minutes turns the useful bits into GitHub issues.

The point: nobody should have to stop playing to ask for a change. You say
"these zombies are far too quick" out loud, and it becomes an issue — and
eventually a deployed change — without anyone alt-tabbing.

## How it works

```
Discord voice ──► bot.mjs ──► queue/*.wav ──► transcribe.py ──► transcripts/*.jsonl
                                                                      │
                                                    recent.py 5 ──────┤
                                                                      ▼
                                                          Claude agent (DIGEST.md)
                                                                      │
                                                                      ▼
                                                              GitHub issues
```

Discord hands out **one audio stream per speaker**, so every utterance arrives
already attributed to a person and none of the game audio comes with it. That's
why this is a bot rather than a desktop recorder.

Audio is transcribed and **immediately deleted** — the WAV files are a queue,
not a recording. Only text is kept.

## Setup

**1. Make a Discord bot.** [Developer Portal](https://discord.com/developers/applications)
→ New Application → Bot → Reset Token. No privileged intents needed. Invite it
to your server with the **Connect** permission.

**2. Configure.**

```bash
cp .env.example .env    # add the token, server id and voice channel id
```

Server and channel IDs: turn on Developer Mode in Discord (Settings → Advanced),
then right-click → Copy ID.

**3. Install.**

```bash
npm install
python3 -m venv .venv && ./.venv/bin/pip install faster-whisper
```

**4. Run.**

```bash
./start.sh
```

The bot joins the channel and starts listening. `Ctrl-C` stops both halves.

## Checking what it heard

```bash
./recent.py 5           # last five minutes, and mark them digested
./recent.py 30 --peek   # last half hour, without marking anything
```

## Performance

On a Ryzen 7 3800X, `small.en` on **CPU** transcribes about **20× faster than
real time** — a one-second utterance takes ~50ms. It deliberately stays off the
GPU because that GPU is busy running the game being discussed. Set
`EARSHOT_DEVICE=cuda` if you're running this somewhere else.

## Consent

This records people's voices continuously. Everyone in the channel should know
it's running and be happy about it — particularly if you're streaming.

Transcripts are git-ignored and never leave the machine. Don't commit them.
