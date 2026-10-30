# Fight Back - 2D Multiplayer Fighting Game

A complete, runnable 2D multiplayer fighting game built with **Godot 4.7 (Forward+ / Mobile compatible GDScript)**.

---

## 1. Quick Start: How to Open and Run

### In Godot Editor:
1. Open the Godot 4.7 project manager.
2. Click **Import**, navigate to `C:\Users\ryanf\Downloads\game\fight-back`, and select `project.godot`.
3. Click **Import & Edit**.
4. Press **F5** (or click the **Play** button in the top right) to launch the game.

### From Command Line:
Using the Godot console executable:
```powershell
& "C:\Users\ryanf\Downloads\apps\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "C:\Users\ryanf\Downloads\game\fight-back"
```

---

## 2. Testing 2 Players on One PC

You can test full 2-player multiplayer on a single PC using either of two methods:

### Method A: Command-Line Flags (Instant Test)
Open two PowerShell terminals and run:

**Terminal 1 (Host - Alice):**
```powershell
& "C:\Users\ryanf\Downloads\apps\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "C:\Users\ryanf\Downloads\game\fight-back" --host --name=Alice
```

**Terminal 2 (Client - Bob):**
```powershell
& "C:\Users\ryanf\Downloads\apps\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path "C:\Users\ryanf\Downloads\game\fight-back" --join=127.0.0.1 --name=Bob
```
The two instances will connect automatically via loopback `127.0.0.1:7777` and transition straight into Character Select!

### Method B: Godot Editor Run Multiple Instances
1. In the Godot 4.7 editor, click **Debug** in the top menu bar.
2. Set **Run Multiple Instances** to `2 Instances`.
3. Press **F5** (Run Project).
4. In Instance 1: Click **Versus / Multiplayer** -> Click **HOST MATCH**.
5. In Instance 2: Click **Versus / Multiplayer** -> Click **JOIN MATCH** (target IP defaults to `127.0.0.1`).
6. In Instance 1 (Host): Click **PROCEED TO CHARACTER SELECT**.

---

## 3. Controls

Both fighters share unified input mappings:

### Keyboard:
| Action | Primary Key | Secondary Key |
| :--- | :--- | :--- |
| **Move Left** | `A` | `Left Arrow` |
| **Move Right** | `D` | `Right Arrow` |
| **Jump** | `W` | `Up Arrow` / `Space` |
| **Light Attack** | `J` | `Z` |
| **Heavy Attack** | `K` | `X` |
| **Special Attack** | `L` | `C` |
| **Toggle Debug Overlay** | `F3` | |
| **Leave Match Menu** | `Escape` | |

### Gamepad:
| Action | Gamepad Input |
| :--- | :--- |
| **Move** | D-Pad Left / Right or Left Analog Stick |
| **Jump** | D-Pad Up or `A` / Bottom Face Button |
| **Light Attack** | `X` / Left Face Button |
| **Heavy Attack** | `Y` / Top Face Button |
| **Special Attack** | `B` / Right Face Button |

### Touch Controls:
- Virtual D-pad (left side) and Action Buttons (right side: Light, Heavy, Special, Jump).
- Automatically enabled on mobile and touchscreen devices (`DisplayServer.is_touchscreen_available()`).
- On desktop, click the **Touch Controls** pill button in the top-left corner of the arena to toggle on-screen touch controls for testing.

---

## 4. LAN & Online Play (Port Forwarding)

### LAN Play:
1. The Host clicks **HOST MATCH** in the Lobby.
2. The Lobby displays the Host's LAN IP (e.g. `192.168.1.125 : 7777`).
3. The Client enters that LAN IP in the Host IP field and clicks **JOIN MATCH**.

### Online Play (Over the Internet):
1. The game attempts best-effort automatic UPnP port mapping upon hosting.
2. If router UPnP is disabled, forward UDP port **7777** on the host's router to the host PC's internal IP address.
3. The client connects using the host's public IP address.

---

## 5. Fighter Roster & Data-Driven Moves

All characters are configured via `CharacterData` and `MoveData` resources (`resources/characters/` and `resources/moves/`):

1. **Karasu Tengu** (Swift Assassin):
   - High speed (280 px/s), 100 HP.
   - Light: Katana Slash (Fast startup, 8 damage).
   - Heavy: Heavy Cleave (16 damage, solid knockback).
   - Special: Wing Tempest (22 damage, wide hitbox).

2. **Kitsune** (Fox Spirit Zoner):
   - 250 px/s, 90 HP, 1.1x damage multiplier.
   - Light: Spirit Palm (7 damage).
   - Heavy: Tails Whirl (14 damage).
   - Special: Fox-Fire Blast (Spawns a blue spirit projectile traveling across the stage, 18 damage).

3. **Yamabushi Tengu** (Power Juggernaut):
   - High health (120 HP), 1.25x damage multiplier, 210 px/s.
   - Light: Iron Hilt strike (11 damage).
   - Heavy: Mountain Splitter (20 damage, heavy hitstop).
   - Special: Earth Quake (26 damage, high vertical knockback).

### Mirror Matches:
Both players are free to select the same fighter. Player 2's sprite is subtly modulated with a cool blue tint, and floating "P1" / "P2" overhead indicators keep fighters distinct.

---

## 6. Exporting to Android

1. In Godot, go to **Project > Export**.
2. Click **Add...** and choose **Android**.
3. Ensure Android SDK, build-tools, and JDK 17 are installed in **Editor > Editor Settings > Export > Android**.
4. Set package unique name (e.g., `com.ryanf.fightback`).
5. The rendering method is configured for Mobile compatibility (`rendering/renderer/rendering_method.mobile="mobile"`).
6. Click **Export Project** to produce an `.apk` file.

---

## 7. Architecture & Polish Details

- **Host-Authoritative 60 Hz Simulation**: The host runs the authoritative physics step and hit registration. Clients stream lightweight input bitmasks to the host via unreliable-ordered RPCs. The host replicates positions, state enum, animations, frames, and health through `MultiplayerSynchronizer` with client interpolation.
- **Hitstop**: 3 frames of physics freeze applied on both attacker and target on solid hits.
- **Screen Shake**: Dynamic camera shake on heavy attacks and KOs.
- **Dynamic Camera**: Midpoint tracking between fighters with smooth zoom-in and zoom-out based on distance, clamped to the castle battlement stage bounds.
- **Particles**: Landing dust on floor landing, hit sparks on impact.
- **Zero Assets Touched**: All original asset files in `assets/` remain completely untouched; `logo.png` was copied to `assets/logo/logo.png` and animated on the main menu.
