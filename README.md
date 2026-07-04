# 📡 Digital Walkie-Talkie System using WebRTC SFU

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Go Version](https://img.shields.io/badge/Go-1.20+-00ADD8?style=flat\&logo=go)](https://golang.org)
[![Flutter Version](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat\&logo=flutter)](https://flutter.dev)
[![WebRTC](https://img.shields.io/badge/WebRTC-Realtime-green)](https://webrtc.org)

A real-time digital walkie-talkie platform inspired by traditional radio communication systems. The system enables low-latency voice communication over the Internet using **Flutter**, **WebRTC SFU**, **WebSockets**, **MongoDB**, and a concurrent **Golang backend**.

Unlike traditional walkie-talkie devices that rely on radio frequencies and limited coverage, this system operates entirely over IP networks and provides flexible room-based communication, channel management, Push-To-Talk (PTT), and room-wide Broadcast functionality.

---

## 🚀 Features

### Authentication & User Management

* JWT-based authentication
* User registration and login
* Change password
* Update display name
* Delete account

### Room Management

* Create room
* Join room using invite code
* Manage room members
* Owner / Member role management

### Channel Management

* Create channels inside rooms
* Join and switch channels
* Isolated voice communication per channel

### Real-Time Communication

* Push-To-Talk (PTT)
* WebRTC audio streaming
* Speaking state synchronization
* Low-latency communication

### Broadcast

* Room Owner can broadcast voice messages
* Audio can be delivered to all channels within a room simultaneously

### Security

* JWT Authentication
* HTTPS / WSS
* DTLS-SRTP media encryption
* Secure WebRTC communication

---

## 🏗️ System Architecture

```text
                        ┌─────────────────────┐
                        │   Flutter Client    │
                        └──────────┬──────────┘
                                   │
                                   │ REST API
                                   ▼
                        ┌─────────────────────┐
                        │   Golang Backend    │
                        │─────────────────────│
                        │ JWT Authentication  │
                        │ Room Management     │
                        │ Channel Management  │
                        └──────────┬──────────┘
                                   │
                                   │ WebSocket
                                   ▼
                        ┌─────────────────────┐
                        │ Signaling Server    │
                        └──────────┬──────────┘
                                   │
                                   ▼
                        ┌─────────────────────┐
                        │     WebRTC SFU      │
                        │ RTP Forwarding      │
                        │ Broadcast Engine    │
                        └──────────┬──────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    ▼              ▼              ▼
               Client A       Client B       Client C
```

---

## 🔄 Communication Flow

### Room Communication

```text
User
  │
  ▼
Join Room
  │
  ▼
Join Channel
  │
  ▼
Connect WebSocket
  │
  ▼
Establish WebRTC Connection
  │
  ▼
Push-To-Talk Communication
```

### Broadcast Communication

```text
Room Owner
     │
     ▼
Broadcast Audio
     │
     ▼
WebRTC SFU
     │
     ├── Channel A
     ├── Channel B
     ├── Channel C
     └── Channel N
```

---

## 🧰 Technology Stack

### Frontend

* Flutter
* Dart
* flutter_webrtc
* web_socket_channel
* flutter_secure_storage

### Backend

* Golang
* Gin Framework
* Gorilla WebSocket
* Pion WebRTC

### Database

* MongoDB
* MongoDB Atlas

### Infrastructure

* Docker
* Docker Compose
* AWS EC2
* Nginx

### DevOps

* GitHub Actions
* CI/CD Deployment

---

## 🔐 Security Architecture

The system follows WebRTC security standards:

```text
Microphone
      │
      ▼
 Opus Codec
      │
      ▼
 RTP Packet
      │
      ▼
 SRTP Encryption
      │
      ▼
 Internet
      │
      ▼
 WebRTC SFU
      │
      ▼
 Receiver Clients
```

Security mechanisms:

* DTLS for key exchange
* SRTP for media encryption
* JWT Authentication
* HTTPS
* Secure WebSocket (WSS)

---

## 🌐 Deployment

### Production Environment

* Frontend: Flutter Web
* Backend: Golang
* Database: MongoDB Atlas
* Hosting: AWS EC2
* Reverse Proxy: Nginx
* SSL: Let's Encrypt
* CI/CD: GitHub Actions

### NAT Traversal

The system supports:

* STUN Server
* TURN Server (recommended for production)

This ensures successful WebRTC connections across NATs and restrictive firewalls.

---

## 📚 Academic Context

This project was developed as a graduation thesis focusing on:

* Real-time communication systems
* WebRTC SFU architecture
* Concurrent programming in Golang
* Distributed systems
* Push-To-Talk communication
* Audio streaming over IP networks

---

## 👨‍💻 Author

Graduation Thesis Project

**Digital Walkie-Talkie System using WebRTC SFU**

---

## 📄 License

This project is intended for educational and academic purposes.
