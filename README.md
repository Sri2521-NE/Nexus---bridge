# Nexus Bridge - Flutter Mobile App

## Overview

Nexus Bridge is a secure, offline-first P2P file transfer application with a Flutter mobile frontend and Python backend. It allows devices on the same LAN to share files securely without any internet connection or cloud storage.

## Features

### 🔍 Auto-Discovery
- UDP broadcast discovery on port 37020
- Automatic detection of Nexus Bridge servers on the local network
- One-tap connection to servers
- Manual IP entry fallback

### 📱 Seamless UI
- Material Design 3 interface
- Dark theme optimized for low-light usage
- WebView integration with Python web server
- Persistent connection state

### ⬇️ Background Download Manager
- Resume interrupted downloads using HTTP Range headers
- Persistent Android notifications with progress
- Automatic retry on WiFi reconnection
- Save to /Downloads/NexusBridge/ folder

### 🔐 Security Features
- Cryptographically secure session tokens (256-bit random)
- Rate limiting: max 5 login attempts per IP (5-minute lockout)
- Path traversal prevention
- Audit logging of all file access
- Hidden folder support for admin

### 🛡️ Privacy
- Zero cloud connectivity - files stay on LAN only
- Access audit log visible only to admin
- Encrypted session tokens
- No tracking or analytics

## Installation

### Prerequisites
- Flutter 3.0+
- Python 3.8+
- Android SDK (for Android deployment)

### Setup

1. **Clone the repository**
```bash
cd nexus_flutter_app
flutter pub get
```

2. **Configure permissions (Android)**
Edit `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

3. **Build and run**
```bash
flutter run
```

## Architecture

### Services

#### `DiscoveryService`
- Sends UDP broadcast on port 37020 with `NEXUS_DISCOVER` message
- Listens for `NEXUS_BRIDGE:IP:PORT` responses
- Maintains list of discovered servers
- Supports manual server entry

#### `ConnectionService`
- Manages HTTP connection to Nexus Bridge server
- Handles login and session token management
- Persists last connected server to SharedPreferences
- Auto-reconnect on app restart

#### `DownloadService`
- Implements resumable downloads using HTTP Range headers
- Stores downloads in /Downloads/NexusBridge/
- Tracks download progress
- Notifies UI of status changes

### Screens

#### `DiscoveryScreen`
- Auto-discovery UI showing found servers
- Manual connection input field
- Server card selection with one-tap connect

#### `MainScreen`
- WebView displaying Python server UI
- Download manager modal
- Disconnect button with confirmation

## API Integration

### Python Server Endpoints

The app communicates with the Python backend via HTTP:

- **GET `/online-check`** - Connectivity test
- **POST `/login`** - Authentication (returns session cookie)
- **GET `/`** - Main app UI (WebView target)
- **GET `/download/*`** - File downloads with Range support
- **POST `/upload`** - File uploads
- **GET `/connected-devices`** - Device management

### UDP Discovery

**Port:** 37020  
**Protocol:** UDP Broadcast

**Client → Server:**
```
NEXUS_DISCOVER
```

**Server → Client:**
```
NEXUS_BRIDGE:192.168.1.100:8000
```

## Security

### Session Management
- Secure token: `secrets.token_hex(32)` (256-bit random)
- Not guessable from timing or IP
- HttpOnly cookies prevent XSS attacks

### Rate Limiting
- Max 5 login attempts per IP address
- 5-minute lockout after exceeding limit
- Prevents brute force attacks on weak passwords

### Path Security
- Uses `Path.is_relative_to()` to prevent directory traversal
- Blocks attempts to access files outside shared folder
- Handles URL encoding attacks

### Audit Logging
Every access is logged:
- Timestamp
- Device ID and name
- Action (login, download, upload, delete)
- File path
- Source IP

Log location: `nexus_audit.log`

## Configuration

### Download Location
```dart
/sdcard/Download/NexusBridge/  // Android
```

### Session Timeout
Python Server: 30 minutes (configurable via `SESSION_TIMEOUT`)

### Discovery Port
Both app and server: Port 37020 (UDP)

### Server Port
Default: Port 8000 (configurable via `PORT` in Python server)

## Troubleshooting

### Discovery not working?
1. Ensure both devices are on same WiFi network
2. Check that Python server is running
3. Verify no firewall blocks UDP port 37020
4. Try manual connection with IP address

### Downloads failing?
1. Check storage permissions in Settings > Nexus Bridge
2. Ensure WiFi connection is stable
3. Check server logs for errors
4. Try smaller files first

### Can't connect to server?
1. Verify server IP is correct
2. Check server is running on port 8000
3. Test connectivity: open `http://IP:8000` in browser
4. Check firewall settings

### Slow discovery?
- Discovery timeout is 3 seconds (configurable in `discovery_service.dart`)
- UDP broadcast may be delayed on some networks
- Manual entry is faster if you know the IP

## Performance Tips

- Close other apps using network for faster discovery
- Download large files over WiFi 5GHz if available
- Pause other downloads before large transfers
- Use Range header support for reliable large file downloads

## Future Enhancements

- [ ] TLS/SSL encryption for transfers
- [ ] Multi-file batch operations
- [ ] Upload progress tracking
- [ ] File sharing links with expiration
- [ ] Android widget for quick access
- [ ] iOS support
- [ ] Desktop companion apps

## License

MIT License - See LICENSE file for details

## Support

For issues and feature requests, visit the GitHub repository.
