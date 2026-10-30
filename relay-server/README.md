# Fight Back Relay Server

Lightweight, zero-dependency (only `ws`) WebSocket room-code relay server for the 2D fighting game **Fight Back**.

---

## 1. How It Works

1. **Host-Authoritative**: The host's game client simulates all physics, collisions, damage, and rounds. The relay server has **zero game logic**.
2. **Room Pairing**: Players connect outward via WebSockets (`wss://`). The relay pairs two players using a short 4-character code (e.g., `K7QM`).
3. **Data Routing**:
   - **STATE updates** (fighter positions, animations): high frequency, stale packets can be dropped on the client.
   - **EVENTS** (projectile spawn, hits, round intro, KO, rematch): guaranteed delivery in order.
4. **Security & Performance**:
   - Max message size capped at 16 KB.
   - Rate limiting: max 120 messages/sec per connection.
   - Brute-force protection: max 5 failed room joins per minute per IP.
   - `X-Forwarded-For` support for reverse proxies (Render, Cloudflare, etc.).

---

## 2. Local Development & Testing

### Installation & Run
```bash
cd relay-server
npm install
npm start
```
The server will listen on `ws://127.0.0.1:10000` (or `PORT` environment variable).

### Automated Test Suite
Run the full 9-step integration test:
```bash
npm test
```

---

## 3. Deploying to Render (Free Tier)

### Recommended Region: **Frankfurt (EU Central)**
> [!IMPORTANT]
> When creating your service on Render, choose **Frankfurt (EU Central)**.
> Frankfurt offers the direct optical fiber trunk to West Africa (Nigeria), yielding the lowest possible round-trip latency (~110–140 ms one-way).
>
> **Honest Latency Note**:
> - Online play relayed across the internet over TCP will feel laggier than local LAN (0 ms).
> - The **host has zero input delay** because their game runs the local simulation.
> - The **client experiences round-trip delay** to the host. The game uses client-side visual interpolation (`lerp`) and predictive animation to keep movement smooth despite the latency.

### Deployment Steps on Render
1. Upload this repository or the `relay-server/` folder to GitHub.
2. Sign in to [Render](https://render.com) and click **New +** -> **Web Service**.
3. Select your repository.
4. Fill in the settings:
   - **Name**: `fight-back-relay`
   - **Region**: `Frankfurt (EU Central)`
   - **Branch**: `main`
   - **Root Directory**: `relay-server`
   - **Runtime**: `Node`
   - **Build Command**: `npm install`
   - **Start Command**: `node server.js`
   - **Instance Type**: `Free`
5. Click **Create Web Service**.
6. Render will assign a public domain, e.g.:
   `https://fight-back-relay.onrender.com`
   The WebSocket URL for the game is:
   `wss://fight-back-relay.onrender.com`

### Health Check & Cold Start (Keep-Alive)
- Render's free tier puts web services to sleep after 15 minutes of inactivity.
- The relay server exposes `GET /health` which returns `200 OK` and `{ status: "ok", active_rooms: X }`.
- When the game starts or opens the Lobby, it sends a quiet GET request to `/health` to wake up the server.
- While inside an active room, the host sends a periodic keep-alive ping every 25 seconds, keeping the Render container awake for the duration of the play session.

---

## 4. Pointing the Game to Your Relay Server

In Godot, open [`scripts/network_manager.gd`](file:///C:/Users/ryanf/Downloads/game/fight-back/scripts/network_manager.gd) and set:
```gdscript
const DEFAULT_RELAY_URL: String = "wss://your-service-name.onrender.com"
```
You can also override this per-machine without editing code by launching with:
```bash
godot --relay=ws://127.0.0.1:10000
```
or by saving it in `user://settings.cfg` under `[network] relay_url`.
