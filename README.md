# nande-rpc
A lua-native (and honestly vibe-coded) mpv player &lt;-> Discord RPC client. No binaries!

<img width="459" height="161" alt="image" src="https://github.com/user-attachments/assets/a0f4471c-77f8-42cf-b540-de3f815a1f58" />
<img width="441" height="143" alt="image" src="https://github.com/user-attachments/assets/cb84af8b-fe26-477a-94fc-a3158e5b3e39" />


Works on Plex Desktop too

Current failure modes:
- When paused, timer is stuck at 0:00
- When launching Plex initially, it won't be detected until it populates the `user-data/plex/playing-media` property
- Progress bar might be laggy, updates are pushed every second
- Timer might tick away when paused, Discord things I guess
- Linux/macOS are not tested at all
- Might get a bit confused as to Watching/Listening state if a cover art is embedded in a song - probs could be fixed tho

If Plex somehow gets misidentified as a regular mpv client, it might publish the direct file name from Plex, like `file.mkv?X-Plex-Session-ID=12345678....&X-Plex-Token=secret`. This is a concern since it could expose secrets. I added a matcher to strip any URL params out period, but beware of this. The string is usually long enough to not actually include the token, but it's worth noting. I tested for it, and it never leaked anything even if I forcefully misidentified the client.

## Installation

Drop it in your config dir's scripts directory - might need to make it.  
Some paths to try (Plex Desktop, will probably work on HTPC too though):

- For Windows: `%localappdata%/Plex/scripts`
- For Flatpak: `~/.var/app/tv.plex.PlexDesktop/data/plex/`
- For Snap: `~/snap/plex-desktop/common/`
- For AUR (Arch btw): `/opt/plex-desktop/resources/`
- For macOS: `~/Library/Application Support/Plex/scripts/`

## Alternatives

If my "pure Lua, zero dependencies" approach doesn't work for you or if you are looking for nicer features like dynamic web-fetched cover art and such, check out these other fantastic projects by people who care much more than me:

### For mpv
* **[tnychn/mpv-discord](https://github.com/tnychn/mpv-discord)** 
* **[goodtrailer/mpv-rich-presence](https://github.com/goodtrailer/mpv-rich-presence)** 
* **[cniw/mpv-discordRPC](https://github.com/cniw/mpv-discordRPC)**

### For Plex
* **[phin05/discord-rich-presence-plex](https://github.com/phin05/discord-rich-presence-plex)** 
