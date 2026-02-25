# PatreonTV

![Build](https://github.com/kochj23/PatreonTV/actions/workflows/build.yml/badge.svg)

Watch your favorite Patreon creators on Apple TV.

## Overview

PatreonTV is a native Apple TV app that lets you browse and watch content from Patreon creators you support. It uses a companion Mac app (PatreonTV Relay) that handles authentication and acts as a media proxy server — resolving Patreon media URLs, extracting YouTube/Vimeo streams via yt-dlp, and proxying video/audio to the Apple TV over your local network.

**Current Versions**: PatreonTV v3.0.0 (tvOS) | PatreonTV Relay v2.0.0 (macOS)

## Components

### PatreonTV (tvOS App)
- Native Apple TV app built with SwiftUI
- Browse your home feed with infinite scroll and creator filter chips
- Watch video and listen to audio — all media streams through the relay
- View images and read text posts with HTML rendering
- Navigate by creator or unified feed
- Continue Watching — resumes playback where you left off
- Top Shelf extension shows recent posts on the Apple TV home screen
- Deep linking via `patreontv://` URL scheme (Top Shelf → post detail)
- Glassmorphic UI design system

### PatreonTV Relay (macOS App)
- Local HTTP server running on your Mac (port 8080)
- Handles QR code authentication flow with native WebView login
- **Media proxy server** — streams video/audio to Apple TV
- Resolves Patreon CDN redirects with session authentication
- Extracts YouTube/Vimeo stream URLs via yt-dlp (with anti-detection)
- Caches resolved URLs (5-minute TTL) to minimize latency on seek
- Dashboard shows active streams, bytes proxied, yt-dlp status, and cache stats
- No data leaves your local network

### PatreonTV Top Shelf (tvOS Extension)
- Displays recent posts on the Apple TV home screen
- Shows post thumbnails and titles from your feed
- Tap to deep link directly into the post detail view
- Data shared via App Group container (`group.com.jordankoch.patreontv`)

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

### Relay Discovery

The Apple TV finds the Mac relay server automatically:

1. **Bonjour** — publishes `_patreontv._tcp` service, Apple TV browses and resolves
2. **Subnet fallback** — if Bonjour doesn't respond within 3 seconds, scans `192.168.1.1-254` on port 8080

No manual IP configuration required.

## Security

- **App Transport Security Enforced**: NSAllowsArbitraryLoads disabled on both tvOS and macOS targets; only local networking permitted via NSAllowsLocalNetworking
- **Local Network Only**: The Relay server only runs on your local network
- **No Cloud Services**: All authentication and media streaming happens between your devices
- **Secure Storage**: Session tokens are stored in the Apple TV's Keychain
- **Session Expiry**: Patreon sessions expire naturally; re-authenticate when needed
- **yt-dlp Anti-Detection**: Rotated user agents (7 browser strings), web player client, and browser-like Referer headers to avoid YouTube throttling
- **No Sandbox on Relay**: The macOS relay requires full network server/client access and yt-dlp subprocess execution
- **Hardened Runtime**: Enabled on the macOS relay app

## Features

- QR code authentication via native Mac login window
- Bonjour auto-discovery with subnet scanning fallback
- Home feed browsing with infinite scroll (cursor-based pagination)
- Creator filter chips — filter feed by specific creator
- Creator list view
- Video playback (Patreon-hosted, YouTube, and Vimeo via relay proxy)
- Audio playback (Patreon-hosted podcasts/audio via relay proxy)
- Image viewing
- Text post reading with HTML rendering
- Continue Watching — saves and resumes playback position
- Top Shelf extension with recent posts and deep linking
- Media proxy with URL caching (5-minute TTL) and HTTP Range/seek support
- Relay dashboard with live stream stats (active streams, bytes proxied, cache hits)
- Glassmorphic UI design system
- Debug logging (file-based, accessible from the app)
- No external Swift package dependencies — all native Apple frameworks

## Project Structure

```
PatreonTV/
├── Shared/                          # Shared code across all targets
│   ├── Design/                      # Glassmorphic UI (colors, glass cards, background)
│   ├── Models/PatreonModels.swift   # Data models (posts, campaigns, users, pairing)
│   └── Services/PatreonAPI.swift    # Patreon API client
├── PatreonTV/                       # tvOS app target
│   ├── App/PatreonTVApp.swift       # App entry, auth manager, Bonjour discovery
│   ├── Views/                       # HomeView, PostDetailView, CreatorViews, PairingView
│   └── Services/                    # PlaybackProgressManager, KeychainService
├── PatreonTV Relay/                 # macOS relay server target
│   ├── App/PatreonTVRelayApp.swift  # App entry
│   ├── Views/                       # RelayServerView (dashboard), PatreonLoginView
│   └── Services/                    # RelayServerManager, MediaProxyService
├── PatreonTV Top Shelf/             # tvOS Top Shelf extension
│   └── ContentProvider.swift        # Recent posts for Apple TV home screen
├── project.yml                      # XcodeGen project spec
└── PatreonTV.xcodeproj/             # Generated Xcode project
```

**3 targets** | **19 Swift files** | **~3,600 lines of code** | **Zero external dependencies**

## Building from Source

### Requirements
- Xcode 16.0+
- yt-dlp (`brew install yt-dlp`)
- XcodeGen (optional, only needed to regenerate the project: `brew install xcodegen`)

### Build Steps

```bash
cd PatreonTV
open PatreonTV.xcodeproj
```

Then build:
- **PatreonTV**: Select scheme, choose your Apple TV destination
- **PatreonTV Relay**: Select scheme, build for Mac

To regenerate the Xcode project from `project.yml`:

```bash
xcodegen generate
```

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

---

> **Disclaimer:** This is a personal project created on my own time. It is not affiliated with, endorsed by, or representative of my employer.
