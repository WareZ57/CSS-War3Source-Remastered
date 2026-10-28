# Online statistics and updater (not installed)

These plugins were part of War3Source until 2016. They are kept for reference only:

- `War3Source_Engine_Statistics.sp`: sent kills, round results, server information, SteamIDs and player IPs to
  `mysql.ownageclan.com`, and fetched race statistics and version checks from it.
- `War3Source_Engine_StatSockets2.sp`: the HTTP client used by Statistics (needs the old socket extension).
- `War3Source_Updater.sp`: downloaded plugin updates from `ownageclan.com`.

The `ownageclan.com` domain no longer belongs to the War3Source project. Do not install these plugins unless you
point them to a server you control. They need `socket.inc` (here) and a socket extension built for your server.
