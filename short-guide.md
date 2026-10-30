# Fight Back

2D online fighting game made with Godot. Two players, create a room, share the code, fight.

## What you need

- [Godot 4.7.2](https://godotengine.org/download) (the standard version, not .NET)
- [Node.js](https://nodejs.org) (only if you want to run the relay server on your own PC)

## Run the game

1. Clone the repo: `git clone https://github.com/ryanfavour4/fight-back-game.git`
2. Open Godot, click **Import**, and select the `project.godot` file in the repo folder.
3. Press **Play** (F5).

## Play online with a friend

1. Both players open the game and go to **Online (Room Code)**.
2. Player 1 enters a username and presses **Create Room**. A 4-letter code appears.
3. Player 1 sends the code to the friend.
4. Player 2 enters a username and the code, then presses **Join Room**.
5. Pick your fighters and play!

Note: the online server sleeps when nobody is using it. The first connection can take up to a minute to wake it up. Please be patient.

## Controls

| Action | Keyboard |
| --- | --- |
| Move | A / D (or arrow keys) |
| Jump | W |
| Light attack | J |
| Heavy attack | K |
| Special | L |

## Test alone on one PC (two windows)

1. In a terminal, go to the `relay-server` folder and run `npm install`, then `node server.js`. Keep it running.
2. In Godot: **Debug → Customize Run Instances**, enable **Multiple Instances** (2), and in each instance's Launch Arguments add: `--relay=ws://127.0.0.1:10000`
3. Press **Play**. Two windows open. Create a room in one, join in the other.

## Local network (LAN) mode

Use the **Local Network** tab in the lobby. One player hosts, the other types the host's IP address.

## Known issues

- Online play uses a relay server, so it will feel laggier than LAN.
- Report bugs by opening an issue.
