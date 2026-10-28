# Test plugin

`w3s_verify.sp` adds server commands that test War3Source on a server with bots. It is not part of the package.

    spcomp64 test/w3s_verify.sp -iaddons/sourcemod/scripting -iaddons/sourcemod/scripting/W3SIncs -ow3s_verify.smx

Server setup for `w3t_matrix`, `w3t_items` and `w3t_kill` (one T bot, one CT bot, frozen):

    sv_cheats 1; bot_quota 2; bot_join_after_player 0; mp_roundtime 9; mp_freezetime 0
    war3_bots_use_races 0; war3_bots_buy_items 0; war3_bots_scramble_on_round 0; mp_restartgame 1
    bot_stop 1

| Command | What it does |
|---|---|
| `w3t_status` | Race, level, skills, XP, gold, health, speed, gravity and alpha of every player |
| `w3t_races` | Loaded races and their skills |
| `w3t_matrix [first] [last] [hits]` | For each race at max level: the T bot with the race hits the CT bot (damage dealt, heal, effects), then the reverse (damage taken, damage returned), then the ultimate and the ability are used on the CT bot standing in front |
| `w3t_items [first] [last] [hits]` | Same for each shop item, bought through the normal purchase event |
| `w3t_cmds` | Every War3Source chat command typed by a bot, with and without `!`, then every item of the menu it opened |
| `w3t_kill [race] [kills]` | The T bot kills the CT bot: XP, gold and level after each kill |
| `w3t_set <client> <race> <level> <xp> <gold>` | Sets a player's data (to test saving and loading) |

Every test prints the number of new lines in SourceMod's error log.

Hits are 1.05 seconds apart: War3Source scales proc chances by the time since the attacker's last hit. Hits go
through the damage hooks (`SDKHooks_TakeDamage` with `bypassHooks` false) with a different impact point each time,
because War3Source ignores an `OnTakeDamage` call identical to the previous one. The shooter's health is read one
hit later, since some skills act after a delay (thorns: 0.1 s).

## Results (CS:S 2025, SourceMod 1.12.0.7259)

- 22 races, 17 shop items, 34 chat commands: no error.
- 8 minutes with 10 bots, races and levels scrambled every round, items, ultimates: no error.
- XP saved and loaded with SQLite: race, level, XP, gold and skills.
