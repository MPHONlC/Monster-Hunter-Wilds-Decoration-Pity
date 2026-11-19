# Decoration Pity

A REFramework script for Monster Hunter Wilds that stops the same decoration (gem) from dropping over and over. When a reward gives you a gem you already got many times recently, the script trades the new copies for a different gem of the same slot level and type.

Quest clear opens a watch window, so it works on any quest.

> [!WARNING]
> Back up your save before using it. The script writes straight into the loaded save data. Use at your own risk.

## Key features

- Compares your decoration box before and after a quest, and logs every gem you gain with a timestamp.
- Once you have received a set number of the same gem inside your time window, new copies of it are taken back.
- Adds the same number of a different gem in their place, using the game's own add call.
- Keeps the tier intact. The replacement always has the same slot level and the same type (weapon or armor), so a level 1 gem never turns into a level 4 one.
- Prefers a gem you have not received in the window. If you have received them all, it picks the least-seen one.
- Checks the box after each swap. If the new gem does not land, your original copies are put back.

## Requirements

- Monster Hunter Wilds (PC, Steam)
- [REFramework](https://github.com/praydog/REFramework) for Monster Hunter Wilds

## Installation

1. Install REFramework if you do not have it.
2. Copy `decoration_pity.lua` into `reframework/autorun/` in your game folder.
3. Start the game. Open the REFramework menu (Insert by default) and find **Decoration Pity**.

To uninstall, delete `decoration_pity.lua`. Your history and settings are in `reframework/data/decoration_pity.json`. Delete that file too for a clean start.

## Settings

- **Enable**: turns the script on or off.
- **Swap after this many copies in window** (default 3): how many of one gem you must already have received inside the window before new copies are swapped.
- **Window in hours** (default 24): how far back the script looks. Set it to 0 to use "since midnight" instead.
- **Watch seconds after quest clear** (default 600): how long gains count as quest rewards after a clear.
- **Replacement keeps the slot level** and **keeps the type**: both on by default. Turn them off to allow any tier or type.
- **Pick from all decorations**: by default replacements come from gems you already own. Tick this to allow any valid gem of the matching slot level and type, including ones you have never had.
- **Watch all the time**: counts every gain, not only rewards after a clear.
- **Clear history**: forgets everything received so far.

## Compatibility

- The script reads gains from your decoration box, so anything that adds gems during the watch window counts as a reward. That includes taking a gem out of your gear and gems added by other mods, such as the bonus gems from Bonus Quest Rewards.
- It is meant for single-player use. Do not use it in online or multiplayer sessions.

## Known issues

- The decoration box may not refresh on screen right away. If a swapped gem does not show, change area to refresh it.
- With "Pick from all decorations" on, the pool can include gems that do not normally drop. Leave it off if you want to stay close to what the game gives out.

## Troubleshooting

- **Menu missing**: check that `decoration_pity.lua` sits in `reframework/autorun/` and that REFramework shows no script errors.
- **"Quest clear hook: NOT found"**: tick "Watch all the time" instead.
- **Swap failed, original restored**: the game did not accept the replacement gem. Try again with "Pick from all decorations" off.
- **Nothing gets swapped**: you may not have reached the copy count yet, or no other gem of that slot level and type is available. Lower the count or tick "Pick from all decorations".

## Credits

- [praydog](https://www.nexusmods.com/profile/praydog?gameId=6993), for REFramework.
- [Paradyse19](https://www.nexusmods.com/profile/Paradyse19?gameId=6993), for [Bonus Quest Rewards](https://www.nexusmods.com/monsterhunterwilds/mods/921), whose quest clear hook this script builds on.
- Craft All Decorations, whose decoration box access this script builds on.
