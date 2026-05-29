📡 Walkie-Talkie Realtime System (Push-to-Talk using WebRTC)

A real-time voice communication system inspired by walkie-talkie devices, built with Flutter, WebRTC, WebSocket, and a Golang backend. The system enables low-latency push-to-talk (PTT) voice communication through room and channel-based architecture.

🚀 Features
🔐 JWT-based authentication
🏠 Room & Channel management
🎙️ Push-To-Talk (PTT) real-time voice streaming
📡 WebRTC peer-to-peer audio communication
🔄 WebSocket-based signaling server
👥 Multi-user voice channels
🌐 STUN/TURN support for NAT traversal
⚡ Low-latency audio transmission
🏗️ System Architecture
Flutter Client
     │
     │ WebSocket (Signaling)
     ▼
Golang Backend Server
     │
     ├── Authentication (JWT)
     ├── Room / Channel Management
     └── WebRTC Signaling Handler
     │
     ▼
WebRTC Peer-to-Peer Audio Stream
🧰 Tech Stack
Frontend
Flutter
Dart
WebRTC plugin
WebSocket client
Backend
Golang (Go)
Gin / Fiber (depending on implementation)
WebSocket
JWT Authentication
MongoDB
Infrastructure
MongoDB Atlas
STUN: Google STUN servers
TURN: Coturn (optional)
Docker (deployment support)
📁 Project Structure
walkie-talkie/
│
├── backend/
│   ├── controllers/
│   ├── services/
│   ├── models/
│   ├── sockets/
│   └── main.go
│
├── frontend/
│   ├── lib/
│   │   ├── screens/
│   │   ├── services/
│   │   ├── widgets/
│   │   └── webrtc/
│
├── docker/
└── README.md


🌐 Deployment

Backend can be deployed using:

AWS EC2
DigitalOcean
VPS (Ubuntu Server)

Frontend:

Flutter Mobile App (Android/iOS)
Flutter Web (optional build)
📸 Screenshots

Add application screenshots here:

Login Screen
Room List
Channel Interface
Push-To-Talk Interface
📌 Key Concepts
WebRTC peer-to-peer communication
WebSocket signaling server
Push-To-Talk mechanism
Real-time voice streaming
Room-based communication model
Golang backend concurrency handling
⚠️ Notes
WebRTC requires STUN/TURN for reliable NAT traversal
TURN server is recommended for production environments
Audio latency depends on network conditions
👨‍💻 Author

Walkie-Talkie Realtime System
Built as an academic project focusing on real-time communication systems using WebRTC and Golang.

📄 License
For educational and research purposes only.