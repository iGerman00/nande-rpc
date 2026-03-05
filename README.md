# nande-rpc
A lua-native (and honestly vibe-coded) mpv player &lt;-> Discord RPC client. No binaries!

Works on Plex Desktop too

Current failure modes:
- When paused, timer is stuck at 0:00
- When launching Plex initially, it won't be detected until it populates the `user-data/plex/playing-media` property
- Progress bar might be laggy, updates are pushed every second
- Timer might tick away when paused, Discord things I guess
- Linux/macOS are not tested at all
- _Might_ leak _some_ data from Plex like a session ID or at worst a token, not tested but it does try to strip that stuff out
