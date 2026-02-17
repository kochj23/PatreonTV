# PatreonTV

Watch your favorite Patreon creators on Apple TV.

## Overview

PatreonTV is a native Apple TV app that lets you browse and watch content from Patreon creators you support. Since tvOS doesn't support web browsers, this app uses a companion Mac app (PatreonTV Relay) to handle authentication via QR code.

## Components

### PatreonTV (tvOS App)
- Native Apple TV app built with SwiftUI
- Browse your feed from supported creators
- Watch video content
- Listen to audio/podcasts
- View images and text posts
- Navigate by creator or unified feed

### PatreonTV Relay (macOS App)
- Local HTTP server running on your Mac
- Handles QR code authentication flow
- Securely passes Patreon session to Apple TV
- No data leaves your local network

## Installation

### Prerequisites
- Apple TV (4th generation or later) running tvOS 17.0+
- Mac running macOS 14.0+ (for the Relay server)
- Patreon account with active subscriptions

### Setup

1. **Install PatreonTV Relay on your Mac**
   - Copy `PatreonTV Relay.app` to your Applications folder
   - Launch the app - it will start the local server automatically
   - Note the server URL displayed (e.g., `http://192.168.1.100:8080`)

2. **Install PatreonTV on Apple TV**
   - Build and deploy from Xcode, or
   - Install via TestFlight (if available)

3. **Connect Your Account**
   - Launch PatreonTV on your Apple TV
   - Click "Pair with Your Mac"
   - Scan the QR code with your phone
   - Log in to Patreon when prompted
   - Copy your `session_id` cookie and paste it in the form
   - Your Apple TV will automatically connect

## How It Works

```
Apple TV                    Mac (Relay Server)              Phone
    │                              │                          │
    │  1. Generate pairing code    │                          │
    │  2. Display QR code ─────────│──────────────────────────│
    │                              │                          │
    │                              │        3. Scan QR        │
    │                              │◄─────────────────────────│
    │                              │                          │
    │                              │   4. Show login page     │
    │                              │─────────────────────────►│
    │                              │                          │
    │                              │   5. User logs into      │
    │                              │      Patreon             │
    │                              │                          │
    │                              │   6. Paste session_id    │
    │                              │◄─────────────────────────│
    │                              │                          │
    │  7. Poll for session         │                          │
    │─────────────────────────────►│                          │
    │                              │                          │
    │  8. Receive session token    │                          │
    │◄─────────────────────────────│                          │
    │                              │                          │
    │  9. Fetch content from       │                          │
    │     Patreon API              │                          │
```

## Security

- **Local Network Only**: The Relay server only runs on your local network
- **No Cloud Services**: All authentication happens between your devices
- **Secure Storage**: Session tokens are stored in the Apple TV's Keychain
- **Session Expiry**: Patreon sessions expire naturally; re-authenticate when needed

## Features

### Current
- [x] QR code authentication
- [x] Home feed browsing
- [x] Creator list view
- [x] Video playback (native Patreon videos)
- [x] Audio playback
- [x] Image viewing
- [x] Text post reading
- [x] Infinite scroll/pagination

### Planned
- [ ] Embedded video support (YouTube, Vimeo)
- [ ] Bookmarks/favorites
- [ ] Continue watching
- [ ] Search functionality
- [ ] Push notifications (via Relay)

## Building from Source

### Requirements
- Xcode 16.0+
- XcodeGen (`brew install xcodegen`)

### Build Steps

```bash
cd PatreonTV
xcodegen generate
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

### "Authentication failed"
- Make sure you're copying the correct `session_id` cookie
- The cookie should be a long alphanumeric string
- Try logging out of Patreon and logging back in

### Video not playing
- Some embedded videos (YouTube, Vimeo) may not play directly
- Native Patreon-hosted videos should work
- Check if the content is available in your region

## License

MIT License - see [LICENSE](LICENSE) file.

## Author

Created by Jordan Koch.

## Disclaimer

This is an unofficial app and is not affiliated with or endorsed by Patreon. Use at your own risk and in accordance with Patreon's Terms of Service.
