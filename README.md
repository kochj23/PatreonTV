# PatreonTV

Watch your favorite Patreon creators on Apple TV.

## Overview

PatreonTV is a native Apple TV app that lets you browse and watch content from Patreon creators you support. It uses a companion Mac app (PatreonTV Relay) that handles authentication and acts as a media proxy server — resolving Patreon media URLs, extracting YouTube/Vimeo streams via yt-dlp, and proxying video/audio to the Apple TV over your local network.

## Components

### PatreonTV (tvOS App)
- Native Apple TV app built with SwiftUI
- Browse your feed from supported creators
- Watch video and listen to audio — all media streams through the relay
- View images and text posts
- Navigate by creator or unified feed
- Glassmorphic UI design system

### PatreonTV Relay (macOS App)
- Local HTTP server running on your Mac
- Handles QR code authentication flow
- **Media proxy server** — streams video/audio to Apple TV
- Resolves Patreon CDN redirects with session authentication
- Extracts YouTube/Vimeo stream URLs via yt-dlp (with anti-detection)
- Caches resolved URLs to minimize latency on seek
- Dashboard shows active streams, bytes proxied, yt-dlp status, and cache stats
- No data leaves your local network

## Installation

### Prerequisites
- Apple TV (4th generation or later) running tvOS 17.0+
- Mac running macOS 14.0+ (for the Relay server)
- Patreon account with active subscriptions
- yt-dlp installed on Mac (`brew install yt-dlp`) — required for YouTube/Vimeo playback

### Setup

1. **Install PatreonTV Relay on your Mac**
   - Copy `PatreonTV Relay.app` to your Applications folder
   - Launch the app — it starts the local server automatically on port 8080
   - Verify the dashboard shows "yt-dlp: Available" (green checkmark)
   - Note the server URL displayed (e.g., `http://192.168.1.100:8080`)

2. **Install PatreonTV on Apple TV**
   - Build and deploy from Xcode, or install via TestFlight (if available)

3. **Connect Your Account**
   - Launch PatreonTV on your Apple TV
   - Click "Pair with Your Mac"
   - Scan the QR code with your phone
   - A login window opens on your Mac — log in to Patreon
   - Your Apple TV connects automatically

## Architecture

```
Apple TV                          Mac (Relay Server)
    |                                    |
    |  1. Pair via QR code               |
    |  2. Receive session token          |
    |                                    |
    |  3. Browse feed (Patreon API)      |
    |                                    |
    |  4. Play media:                    |
    |     GET /api/media/stream/<id>     |
    |  --------------------------------> |
    |                                    |
    |                           Resolve media URL:
    |                           - Patreon video/audio:
    |                             follow redirect -> CDN URL
    |                           - YouTube/Vimeo embed:
    |                             yt-dlp -> direct stream URL
    |                           - Cache resolved URL (5 min)
    |                                    |
    |                           Proxy upstream response:
    |                           - Forward headers (Content-Type,
    |                             Content-Length, Range support)
    |                           - Stream body chunks to Apple TV
    |                                    |
    |  <-- HTTP headers + body chunks -- |
    |                                    |
    |  AVPlayer plays stream             |
```

## Security

- **Local Network Only**: The Relay server only runs on your local network
- **No Cloud Services**: All authentication happens between your devices
- **Secure Storage**: Session tokens are stored in the Apple TV's Keychain
- **Session Expiry**: Patreon sessions expire naturally; re-authenticate when needed
- **yt-dlp Anti-Detection**: Rotated user agents, web player client, and browser-like headers to avoid YouTube throttling

## Features

- QR code authentication via native Mac login window
- Bonjour auto-discovery (no manual IP configuration)
- Home feed browsing with infinite scroll
- Creator list view
- Video playback (Patreon-hosted, YouTube, and Vimeo via relay proxy)
- Audio playback (Patreon-hosted podcasts/audio via relay proxy)
- Image viewing
- Text post reading with HTML rendering
- Media proxy with URL caching and Range/seek support
- Relay dashboard with live stream stats
- Glassmorphic UI design system
- Debug logging (file-based, pullable from Apple TV)

## Building from Source

### Requirements
- Xcode 16.0+
- yt-dlp (`brew install yt-dlp`)

### Build Steps

```bash
cd PatreonTV
open PatreonTV.xcodeproj
```

Then build:
- **PatreonTV**: Select scheme, choose your Apple TV destination
- **PatreonTV Relay**: Select scheme, build for Mac

## Troubleshooting

### "Could not connect to relay server"
- Make sure PatreonTV Relay is running on your Mac
- Verify your Mac and Apple TV are on the same network
- Check if any firewall is blocking port 8080

### "Pairing code expired"
- Codes expire after 5 minutes
- Click "Cancel" and start a new pairing session

### Video not playing
- Check that PatreonTV Relay is running on your Mac
- Verify the relay dashboard shows "yt-dlp: Available"
- For YouTube content, make sure yt-dlp is up to date (`brew upgrade yt-dlp`)
- Check the relay server logs for error details

### yt-dlp not working
- Install: `brew install yt-dlp`
- Update: `brew upgrade yt-dlp`
- The relay dashboard shows yt-dlp status at a glance

## License

MIT License - see [LICENSE](LICENSE) file.

## Author

Created by Jordan Koch.

## Disclaimer

This is an unofficial app and is not affiliated with or endorsed by Patreon. Use at your own risk and in accordance with Patreon's Terms of Service.
