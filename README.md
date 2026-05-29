# 📡 Walkie-Talkie Realtime System (Push-to-Talk using WebRTC)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Go Version](https://img.shields.io/badge/Go-1.20+-00ADD8?style=flat&logo=go)](https://golang.org)
[![Flutter Version](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat&logo=flutter)](https://flutter.dev)

A real-time voice communication system inspired by traditional walkie-talkie devices. Built with **Flutter**, **WebRTC**, **WebSockets**, and a concurrent **Golang** backend, this system enables ultra-low latency Push-to-Talk (PTT) communication through a structured room and channel-based architecture.

---

## 🚀 Features

* **Secure Authentication:** JWT-based user login and session management.
* **Room & Channel Management:** Multi-tenant rooms with dedicated sub-channels for structured team communication.
* **True Push-To-Talk (PTT):** Instant, half-duplex style real-time voice streaming triggered by button hold.
* **WebRTC Audio Pipeline:** High-fidelity, low-latency peer-to-peer audio communication.
* **WebSocket Signaling:** Robust signaling server built in Go to handle state synchronization and WebRTC negotiation.
* **NAT Traversal Ready:** Integrated STUN/TURN server support to ensure seamless connectivity across different network topologies.

---

## 🏗️ System Architecture
┌─────────────────────────┐
                   │     Flutter Client      │
                   └────────────┬────────────┘
                                │
                                │ WebSocket (Signaling & Events)
                                ▼
                   ┌─────────────────────────┐
                   │  Golang Backend Server  │
                   │ ─────────────────────── │
                   │  • JWT Authentication   │
                   │  • Room/Channel Manager │
                   │  • Signaling Handler    │
                   └────────────┬────────────┘
                                │
                                ▼
           ┌─────────────────────────────────────────┐
           │   WebRTC Peer-to-Peer Audio Streaming   │
           └─────────────────────────────────────────┘
---

## 🧰 Tech Stack

### Frontend
* **Framework:** Flutter (Dart)
* **Core Packages:** `flutter_webrtc`, `web_socket_channel`, `flutter_secure_storage`

### Backend
* **Language:** Golang (Go)
* **Framework:** Gin Gonic / Fiber
* **Protocols:** WebSockets (`gorilla/websocket`), WebRTC
* **Database:** MongoDB (with `mongo-go-driver`)

### Infrastructure & DevOps
* **Database Hosting:** MongoDB Atlas
* **NAT Traversal:** Google STUN servers / Coturn (TURN server for production)
* **Containerization:** Docker & Docker Compose

---
🌐 Production Deployment Considerations
Backend Deployment: Highly recommended to host on AWS EC2, DigitalOcean VPS, or any Ubuntu Server with proper reverse proxy setups.

NAT Traversal (Crucial): While Google STUN servers work fine for local testing, a dedicated Coturn (TURN Server) deployment is highly recommended for production to guarantee connection establishment across symmetric NATs and strict corporate firewalls.

Audio Quality: Voice performance is highly correlated with network stability. Implementing Opus codec fine-tuning within the SDP exchange is recommended for low-bandwidth environments.
👨‍💻 Author
Walkie-Talkie Realtime System

Developed as an academic project focused on real-time systems, concurrency handling in Go, and peer-to-peer mobile communications.

📄 License
This project is licensed under the MIT License - see the LICENSE file for details.

For educational and academic purposes only.