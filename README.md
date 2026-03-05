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
- _Might_ leak _some_ data from Plex like a session ID or at worst a token, not tested but it does try to strip that stuff out
- Might get a bit confused as to Watching/Listening state if a cover art is embedded in a song - probs could be fixed tho
