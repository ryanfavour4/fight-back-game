const http = require('http');
const { WebSocketServer, WebSocket } = require('ws');

const PORT = process.env.PORT || 10000;
const MAX_MESSAGE_SIZE = 16 * 1024; // 16 KB
const MAX_MESSAGES_PER_SEC = 120;
const MAX_FAILED_JOINS_PER_MIN = 5;
const ROOM_IDLE_TIMEOUT_MS = parseInt(process.env.ROOM_IDLE_TIMEOUT_MS, 10) || (15 * 60 * 1000); // 15 minutes
const IDLE_CHECK_INTERVAL_MS = parseInt(process.env.IDLE_CHECK_INTERVAL_MS, 10) || 60000; // 1 minute
const CODE_ALPHABET = '23456789ACDEFGHJKMNPQRSTUVWXYZ';

// In-memory data
// rooms: Map<string, Room>
// Room = { code, hostWs, clientWs, hostUsername, clientUsername, version, createdAt, lastActivity }
const rooms = new Map();

// ipRateLimits: Map<string, { failedJoins: number[], blockedUntil: number }>
const ipRateLimits = new Map();

function getClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) {
    return forwarded.split(',')[0].trim();
  }
  return req.socket.remoteAddress || '127.0.0.1';
}

function isIpBlocked(ip) {
  const now = Date.now();
  const record = ipRateLimits.get(ip);
  if (!record) return false;
  if (record.blockedUntil && record.blockedUntil > now) {
    return true;
  }
  // Filter attempts older than 60s
  record.failedJoins = record.failedJoins.filter(t => now - t < 60000);
  return record.failedJoins.length >= MAX_FAILED_JOINS_PER_MIN;
}

function recordFailedJoin(ip) {
  const now = Date.now();
  let record = ipRateLimits.get(ip);
  if (!record) {
    record = { failedJoins: [], blockedUntil: 0 };
    ipRateLimits.set(ip, record);
  }
  record.failedJoins.push(now);
  if (record.failedJoins.length >= MAX_FAILED_JOINS_PER_MIN) {
    record.blockedUntil = now + 30000; // 30 second cooldown
    console.log(`[SECURITY] IP ${ip} rate limited for 30s due to repeated failed joins`);
  }
}

function generateRoomCode() {
  for (let attempt = 0; attempt < 1000; attempt++) {
    let code = '';
    for (let i = 0; i < 4; i++) {
      code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
    }
    if (!rooms.has(code)) {
      return code;
    }
  }
  // Fallback to 5 chars if collision density is high
  let code = '';
  for (let i = 0; i < 5; i++) {
    code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return code;
}

// HTTP Server for Render health check
const server = http.createServer((req, res) => {
  if (req.method === 'GET' && (req.url === '/health' || req.url === '/')) {
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    });
    res.end(JSON.stringify({
      status: 'ok',
      service: 'fight-back-relay',
      active_rooms: rooms.size,
      timestamp: Date.now()
    }));
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

// WebSocket Server
const wss = new WebSocketServer({
  server,
  maxPayload: MAX_MESSAGE_SIZE
});

wss.on('connection', (ws, req) => {
  const clientIp = getClientIp(req);
  ws.clientIp = clientIp;
  ws.msgCount = 0;
  ws.msgRateReset = Date.now();
  ws.roomCode = null;
  ws.role = null; // 'host' | 'client'
  ws.isAlive = true;

  ws.on('message', (raw) => {
    // 1. Message rate limiting
    const now = Date.now();
    if (now - ws.msgRateReset > 1000) {
      ws.msgCount = 0;
      ws.msgRateReset = now;
    }
    ws.msgCount++;
    if (ws.msgCount > MAX_MESSAGES_PER_SEC) {
      console.warn(`[SECURITY] Connection from ${clientIp} exceeded rate limit (${MAX_MESSAGES_PER_SEC}/s). Terminating.`);
      ws.close(1008, 'Rate limit exceeded');
      return;
    }

    // 2. Parse payload
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch (e) {
      console.warn(`[SECURITY] Invalid JSON from ${clientIp}. Terminating.`);
      ws.close(1008, 'Invalid JSON payload');
      return;
    }

    if (!data || typeof data.type !== 'string') {
      ws.close(1008, 'Missing message type');
      return;
    }

    handleMessage(ws, data);
  });

  ws.on('close', () => {
    handleDisconnect(ws);
  });

  ws.on('error', (err) => {
    console.error(`[WS_ERROR] ${clientIp}:`, err.message);
    handleDisconnect(ws);
  });
});

function handleMessage(ws, data) {
  const type = data.type;

  // Keep-alive ping
  if (type === 'ping') {
    ws.send(JSON.stringify({ type: 'pong', t: data.t || 0 }));
    if (ws.roomCode && rooms.has(ws.roomCode)) {
      rooms.get(ws.roomCode).lastActivity = Date.now();
    }
    return;
  }

  // Create room (Host)
  if (type === 'create_room') {
    if (ws.roomCode) {
      ws.send(JSON.stringify({ type: 'error', message: 'Socket already in a room' }));
      return;
    }

    const code = generateRoomCode();
    const username = (data.username || 'Host').trim().substring(0, 24);
    const version = (data.version || '1.0.0').trim();

    const room = {
      code,
      hostWs: ws,
      clientWs: null,
      hostUsername: username,
      clientUsername: null,
      version,
      createdAt: Date.now(),
      lastActivity: Date.now()
    };

    rooms.set(code, room);
    ws.roomCode = code;
    ws.role = 'host';

    ws.send(JSON.stringify({
      type: 'room_created',
      room_code: code,
      assigned_username: username
    }));
    console.log(`[ROOM] Created ${code} by ${username} (${ws.clientIp})`);
    return;
  }

  // Join room (Client)
  if (type === 'join_room') {
    if (isIpBlocked(ws.clientIp)) {
      ws.send(JSON.stringify({
        type: 'join_result',
        success: false,
        error: 'RATE_LIMITED',
        message: 'Too many failed attempts. Please wait 30 seconds.'
      }));
      return;
    }

    const rawCode = (data.room_code || '').trim().toUpperCase();
    const room = rooms.get(rawCode);

    if (!room) {
      recordFailedJoin(ws.clientIp);
      ws.send(JSON.stringify({
        type: 'join_result',
        success: false,
        error: 'ROOM_NOT_FOUND',
        message: `Room code ${rawCode} not found.`
      }));
      return;
    }

    if (room.clientWs && room.clientWs.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        type: 'join_result',
        success: false,
        error: 'ROOM_FULL',
        message: `Room ${rawCode} already has 2 players.`
      }));
      return;
    }

    const clientVersion = (data.version || '1.0.0').trim();
    if (clientVersion !== room.version) {
      ws.send(JSON.stringify({
        type: 'join_result',
        success: false,
        error: 'VERSION_MISMATCH',
        message: `Game version mismatch (Host: ${room.version}, You: ${clientVersion}). Please update.`
      }));
      return;
    }

    // Name deduplication
    let clientUsername = (data.username || 'Client').trim().substring(0, 24);
    if (clientUsername.toLowerCase() === room.hostUsername.toLowerCase()) {
      clientUsername = `${clientUsername} (2)`;
    }

    room.clientWs = ws;
    room.clientUsername = clientUsername;
    room.lastActivity = Date.now();
    ws.roomCode = room.code;
    ws.role = 'client';

    // Notify joiner of success
    ws.send(JSON.stringify({
      type: 'join_result',
      success: true,
      room_code: room.code,
      host_username: room.hostUsername,
      assigned_username: clientUsername
    }));

    // Notify host that opponent joined
    if (room.hostWs && room.hostWs.readyState === WebSocket.OPEN) {
      room.hostWs.send(JSON.stringify({
        type: 'peer_joined',
        role: 'client',
        username: clientUsername
      }));
    }

    console.log(`[ROOM] ${clientUsername} joined room ${room.code} with host ${room.hostUsername}`);
    return;
  }

  // Game data forwarding (STATE or EVENT)
  if (type === 'game_data') {
    if (!ws.roomCode || !rooms.has(ws.roomCode)) {
      return;
    }
    const room = rooms.get(ws.roomCode);
    room.lastActivity = Date.now();

    const targetWs = (ws.role === 'host') ? room.clientWs : room.hostWs;
    if (targetWs && targetWs.readyState === WebSocket.OPEN) {
      // Direct forwarding of message to opponent
      targetWs.send(JSON.stringify(data));
    }
    return;
  }
}

function handleDisconnect(ws) {
  const code = ws.roomCode;
  if (!code || !rooms.has(code)) return;

  const room = rooms.get(code);

  if (ws.role === 'host') {
    console.log(`[ROOM] Host disconnected from ${code}. Closing room.`);
    if (room.clientWs && room.clientWs.readyState === WebSocket.OPEN) {
      room.clientWs.send(JSON.stringify({
        type: 'peer_left',
        reason: 'Host left the match'
      }));
    }
    rooms.delete(code);
  } else if (ws.role === 'client') {
    console.log(`[ROOM] Client disconnected from ${code}.`);
    room.clientWs = null;
    room.clientUsername = null;
    if (room.hostWs && room.hostWs.readyState === WebSocket.OPEN) {
      room.hostWs.send(JSON.stringify({
        type: 'peer_left',
        reason: 'Opponent left the match'
      }));
    }
  }
}

// Cleanup expired idle rooms
setInterval(() => {
  const now = Date.now();
  for (const [code, room] of rooms.entries()) {
    // If no client has joined and room has been idle without activity > ROOM_IDLE_TIMEOUT_MS, purge
    if (!room.clientWs && (now - (room.lastActivity || room.createdAt) > ROOM_IDLE_TIMEOUT_MS)) {
      console.log(`[CLEANUP] Purging expired idle room ${code}`);
      if (room.hostWs && room.hostWs.readyState === WebSocket.OPEN) {
        room.hostWs.send(JSON.stringify({
          type: 'error',
          message: 'Room expired due to inactivity'
        }));
        room.hostWs.close();
      }
      rooms.delete(code);
    }
  }

  // Clean old IP rate-limit records
  for (const [ip, record] of ipRateLimits.entries()) {
    record.failedJoins = record.failedJoins.filter(t => now - t < 60000);
    if (record.failedJoins.length === 0 && (!record.blockedUntil || record.blockedUntil < now)) {
      ipRateLimits.delete(ip);
    }
  }
}, IDLE_CHECK_INTERVAL_MS);

server.listen(PORT, () => {
  console.log(`[SERVER] Fight Back Relay Server listening on port ${PORT}`);
});
