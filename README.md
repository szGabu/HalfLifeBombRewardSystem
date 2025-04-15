# HLDM Bomb Reward System

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![AMX Mod X](https://img.shields.io/badge/AMXX%201.9-Required-orange)

A Half-Life plugin that manages the nuke/bomb system on maps like `crossfire`, awarding kills from nuclear explosions to players who take shelter in the bunker.

## Description

When a player activates the nuclear bomb, the plugin:

1. Notifies all players that the bomb has been activated and who triggered it
2. Shows a countdown timer until detonation
3. Displays which players are inside the bunker
4. Awards kills to players in the bunker in a round-robin fashion
5. Awards bonus points to players who survive the blast outside the explosion radius
6. Awards a bonus point to the player who activated the bomb (if they didn't make it to the bunker)

## Features

- Works out of the box with default maps with a nuke/bunker system (`doublecross` and `crossfire`)
- Multilingual support
- Configuration system to add support to custom maps

## Compatible Games

- Half-Life

In theory, this plugin can also work in other games like Opposing Force, Adrenaline Gamer and even Counter-Strike, but no games aside from Half-Life were tested.

## Installation

1. Download the plugin and related files
2. Copy the files to the following directories:
   - `bomb_award.amxx` → `addons/amxmodx/plugins/`
   - `bomb_award.txt` → `addons/amxmodx/data/lang/`
   - Create directory `addons/amxmodx/configs/bomb_award/`
   - Copy map configs (e.g., `crossfire.ini`) → `addons/amxmodx/configs/bomb_award/`
3. Add the plugin to your `plugins.ini` file:
```
bomb_award.amxx
```

## Configuration

### Map Configuration Files

Each map that uses the bomb system needs its own configuration file. Create a file named `mapname.ini` in the `configs/bomb_award/` directory. 

Example for the map `crossfire` (`crossfire.ini`):
```ini
; Configuration file for bomb awards
; Z threshold - height to be considered "safe" outside the bomb blast
; To disable, put an absurd high value like 9999.9 but NOT ZERO 
z_threshold = -1090.0

; Bomb time - seconds until bomb falls after activation
bomb_time = 52

; Entity target - "target" field of the entity that activates the bomb
entity_target = fire_button_texture

; Damage targetname - "targetname" of the trigger_hurt that kills players
damage_targetname = strike_pain
```

There are many tools you can use to find the required values, but I recommend Nem's BSP Viewer or UnrealKaraulov's newbspguy.

The following maps have support by default:
- `crossfire`
- `doublecross`
- `dm_crossedwire`

### ConVars

```c
// Cvars for plugin "Half-Life Bomb Reward System" by "szGabu" (hldm_bomb_reward.amxx, v1.0.0)

// Enables the plugin.
// -
// Default: "1"
// Minimum: "0.000000"
// Maximum: "1.000000"
amx_bomb_reward_enabled "1"

// Uses a newer detection of the blast zone rather than looping & checking bounds which is slow, unreliable and doesn't even work on newer maps with complex blast zones. Leave it on 1 unless you know what are you doing.
// -
// Default: "1"
// Minimum: "0.000000"
// Maximum: "1.000000"
amx_bomb_reward_new_detection "1"
```

## Languages

The plugin supports multiple languages through the `bomb_award.txt` language file. A native translation is provided for English (en) and Spanish (es). Translations for other languages were generated with AI, so their accuracy cannot be guaranteed. You're welcome to provide your own translations using the template below.

```ini
[en]
BOMB_ACTIVATED = %s has activated the nuke^nPlayers inside the bunker will be awarded the kills
BOMB_ACTIVATED_UNKNOWN = Someone has activated the nuke^nPlayers inside the bunker will be awarded the kills
BOMB_INSIDE_NO_ONE = No one is inside the bunker
BOMB_INSIDE = Players Inside the Bunker:^n%s
BOMB_KILLS = * Nuke kills are awarded to the following players inside the bunker in a round-robin fashion:
BOMB_KILLS_PITY = * %s was also awarded an extra frag for activating the nuke.
BOMB_SURVIVED = * The following players survived the nuclear blast, they are awarded 1 frag each:
```
