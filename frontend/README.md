# Walkie-Talkie Frontend

Frontend application for the Digital Walkie-Talkie System built with Flutter, WebSocket and WebRTC SFU.

The application enables real-time voice communication through a Room–Channel architecture with Push-To-Talk (PTT) and Broadcast functionality.

---

## Features

### Authentication

* User registration
* User login
* JWT-based authentication
* Secure token storage

### Room Management

* Create room
* Join room using invite code
* Manage room members

### Channel Management

* Create channel
* Join channel
* Switch between channels

### Real-Time Communication

* Push-To-Talk (PTT)
* Broadcast to all channels in a room
* Speaking state synchronization
* WebRTC SFU audio streaming

### User Profile

* Update display name
* Change password
* Delete account

---

## Technology Stack

### Frontend

* Flutter
* Dart

### Communication

* REST API
* WebSocket
* WebRTC

### Security

* JWT Authentication
* HTTPS
* WSS
* DTLS-SRTP

---

## Project Structure

```text
lib/
├── config/
│   └── constants.dart
│
├── models/
│   ├── user.dart
│   ├── room.dart
│   └── channel.dart
│
├── screens/
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── room_list_screen.dart
│   ├── room_screen.dart
│   ├── channel_screen.dart
│   └── profile_screen.dart
│
├── services/
│   ├── auth_service.dart
│   ├── room_service.dart
│   ├── websocket_service.dart
│   ├── webrtc_sfu_service.dart
│   └── storage_service.dart
│
├── widgets/
│
└── main.dart
```

---

## Application Flow

### 1. Authentication

```text
User
  │
  ▼
Login / Register
  │
  ▼
Backend Authentication
  │
  ▼
JWT Token
  │
  ▼
Local Storage
```

### 2. Join Room

```text
User
  │
  ▼
Create / Join Room
  │
  ▼
Backend Validation
  │
  ▼
Room Loaded
```

### 3. Join Channel

```text
User
  │
  ▼
Select Channel
  │
  ▼
Connect WebSocket
  │
  ▼
Initialize WebRTC
```

### 4. WebRTC Connection

```text
Microphone Access
        │
        ▼
Create Offer
        │
        ▼
Send Offer to SFU
        │
        ▼
Receive Answer
        │
        ▼
ICE Negotiation
        │
        ▼
Connection Established
```

### 5. Push-To-Talk

```text
Press PTT
     │
     ▼
Capture Audio
     │
     ▼
Opus Encoding
     │
     ▼
WebRTC Transmission
     │
     ▼
SFU Forwarding
     │
     ▼
Other Users Receive Audio
```

### 6. Broadcast

```text
Owner
   │
   ▼
Broadcast Audio
   │
   ▼
SFU
   │
   ├── Channel A
   ├── Channel B
   └── Channel C
```

---

## Security

The system implements multiple security mechanisms:

* JWT Authentication
* HTTPS
* Secure WebSocket (WSS)
* DTLS for key exchange
* SRTP for media encryption

All audio streams are encrypted during transmission according to WebRTC security standards.

---

## Getting Started

### Install Dependencies

```bash
flutter pub get
```

### Run Application

```bash
flutter run -d chrome
```

### Build Production

```bash
flutter build web --release
```

Build output:

```text
build/web/
```

---

## Deployment

The application can be deployed using:

* Nginx
* Docker
* AWS EC2

---

## Author

Graduation Thesis

**Digital Walkie-Talkie System Using WebRTC SFU**
