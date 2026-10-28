# Installing War3Source #

## Supported Games ##

* Counter-Strike: Source (tested with the 2025 version of the game, SourceMod 1.12)
* Team Fortress 2, Counter-Strike: Global Offensive, Left 4 Dead 1 and 2: the code is kept and compiles, but was
  not tested with current versions of these games.

If you plan to run War3Source with a Left4Dead game you will have to get custom tailored races and shopitems as the stock ones are not suited for Left4Dead gameplay

## Requirements ##

* Metamod:Source 1.12 or later (https://www.metamodsource.net/downloads.php?branch=stable)
* SourceMod 1.12 or later (https://www.sourcemod.net/downloads.php?branch=stable)
* Optional: the SteamWorks extension (https://github.com/KyleSanderson/SteamWorks/releases), only for the Clan
  Bonus XP addon with `war3_bonusclan_id`

## Installation guide ##

1. Download `War3Source-CSS-SM1.12.zip` from the latest release, or build the package yourself:

       SPCOMP=/path/to/sourcemod-1.12/addons/sourcemod/scripting/spcomp64 tools/build.sh

   Build with the SourceMod **1.12** compiler: its plugins load on SourceMod 1.12 and later, while plugins built
   with the 1.13 compiler do not load on SourceMod 1.12 ("unsupported version").

2. Copy the content of the zip or of `build/package` (`addons`, `cfg`, `sound`) into the server's `cstrike` folder, where
   Metamod and SourceMod already created an `addons` folder.
3. Put the `sound/war3source` folder on your fastdl server as well, if you use one.
4. Restart the server.

`addons/sourcemod/plugins/disabled` contains the plugins for other games (TF2, Left 4 Dead): leave them there on
Counter-Strike: Source.

## Database ##

War3Source saves XP in the database set by `"database"` in `addons/sourcemod/configs/war3source.ini` (an entry of
SourceMod's `configs/databases.cfg`). With `"default"`, it uses SourceMod's `default` entry; if that database cannot
be reached (out of the box it is MySQL on localhost), War3Source uses SourceMod's local SQLite database
(`storage-local`, file `addons/sourcemod/data/sqlite/sourcemod-local.sq3`) and says so in the server console.

If you use MySQL, put the name of its `databases.cfg` entry in `war3source.ini` (for example `"database"
"war3source"`) instead of `"default"`: a database named there never falls back to SQLite, so a MySQL server that is
briefly down at map start cannot split your players' XP between two databases. New tables are created in
`utf8mb4` on MySQL.

## Settings ##

`cfg/war3source.cfg` is executed at every map start and lists every setting with its default value, commented
out. Race skill settings (cooldowns...) are listed by `cvarlist war3_`.

The `optional` folder contains various things that are not necessary for a base installation.
