const http = require('http');
const { WebSocket } = require('ws');
const { spawn } = require('child_process');

const PORT = 10001; // Use test port
let serverProcess;

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function httpGet(path) {
  return new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${PORT}${path}`, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ statusCode: res.statusCode, data: JSON.parse(data) });
      });
    }).on('error', reject);
  });
}

function createClient() {
  const ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
  const messages = [];
  ws.on('message', raw => {
    messages.push(JSON.parse(raw.toString()));
  });

  return {
    ws,
    messages,
    waitForOpen: () => new Promise(resolve => ws.on('open', resolve)),
    send: (obj) => ws.send(JSON.stringify(obj)),
    waitForMessage: async (predicate, timeoutMs = 3000) => {
      const start = Date.now();
      while (Date.now() - start < timeoutMs) {
        const found = messages.find(predicate);
        if (found) return found;
        await sleep(20);
      }
      throw new Error(`Timed out waiting for message matching predicate`);
    },
    close: () => ws.close()
  };
}

async function runTests() {
  console.log('--- STARTING RELAY SERVER INTEGRATION TESTS ---');

  // 1. Launch server on test port
  serverProcess = spawn('node', ['server.js'], {
    cwd: __dirname,
    env: { ...process.env, PORT: String(PORT) },
    stdio: 'inherit'
  });
  await sleep(600);

  try {
    // Test 1: Health check endpoint
    console.log('[TEST 1] HTTP /health endpoint...');
    const health = await httpGet('/health');
    if (health.statusCode !== 200 || health.data.status !== 'ok') {
      throw new Error(`Health check failed: ${JSON.stringify(health)}`);
    }
    console.log('✓ Health check returned 200 OK');

    // Test 2: Create room
    console.log('[TEST 2] Host create_room...');
    const host = createClient();
    await host.waitForOpen();
    host.send({ type: 'create_room', username: 'KitsuneKing', version: '1.0.0' });

    const roomCreated = await host.waitForMessage(m => m.type === 'room_created');
    const roomCode = roomCreated.room_code;
    console.log(`✓ Room created with code: ${roomCode}`);
    if (!roomCode || roomCode.length !== 4) {
      throw new Error(`Invalid room code: ${roomCode}`);
    }

    // Test 3: Ping / Pong
    console.log('[TEST 3] Ping/Pong latency check...');
    host.send({ type: 'ping', t: 45678 });
    const pong = await host.waitForMessage(m => m.type === 'pong' && m.t === 45678);
    console.log(`✓ Received Pong with timestamp: ${pong.t}`);

    // Test 4: Non-existent room
    console.log('[TEST 4] Join non-existent room...');
    const clientFake = createClient();
    await clientFake.waitForOpen();
    clientFake.send({ type: 'join_room', room_code: 'ZZZZ', username: 'Challenger', version: '1.0.0' });
    const fakeJoinResult = await clientFake.waitForMessage(m => m.type === 'join_result');
    if (fakeJoinResult.success !== false || fakeJoinResult.error !== 'ROOM_NOT_FOUND') {
      throw new Error(`Expected ROOM_NOT_FOUND, got: ${JSON.stringify(fakeJoinResult)}`);
    }
    clientFake.close();
    console.log('✓ Non-existent room rejected with ROOM_NOT_FOUND');

    // Test 5: Version mismatch
    console.log('[TEST 5] Version mismatch rejection...');
    const clientOld = createClient();
    await clientOld.waitForOpen();
    clientOld.send({ type: 'join_room', room_code: roomCode, username: 'OldClient', version: '0.9.0' });
    const oldJoinResult = await clientOld.waitForMessage(m => m.type === 'join_result');
    if (oldJoinResult.success !== false || oldJoinResult.error !== 'VERSION_MISMATCH') {
      throw new Error(`Expected VERSION_MISMATCH, got: ${JSON.stringify(oldJoinResult)}`);
    }
    clientOld.close();
    console.log('✓ Older version rejected with VERSION_MISMATCH');

    // Test 6: Valid join & name deduplication
    console.log('[TEST 6] Valid join with duplicate username...');
    const client = createClient();
    await client.waitForOpen();
    // Joining with the same name "KitsuneKing"
    client.send({ type: 'join_room', room_code: roomCode, username: 'KitsuneKing', version: '1.0.0' });

    const clientJoinResult = await client.waitForMessage(m => m.type === 'join_result');
    if (!clientJoinResult.success || clientJoinResult.assigned_username !== 'KitsuneKing (2)') {
      throw new Error(`Expected deduplicated name 'KitsuneKing (2)', got: ${JSON.stringify(clientJoinResult)}`);
    }

    const hostPeerJoined = await host.waitForMessage(m => m.type === 'peer_joined');
    if (hostPeerJoined.username !== 'KitsuneKing (2)') {
      throw new Error(`Host expected peer_joined with deduplicated name, got: ${JSON.stringify(hostPeerJoined)}`);
    }
    console.log(`✓ Client joined successfully. Deduplicated name: ${clientJoinResult.assigned_username}`);

    // Test 7: Room full rejection (3rd player tries to join)
    console.log('[TEST 7] Third player join rejected (ROOM_FULL)...');
    const client3 = createClient();
    await client3.waitForOpen();
    client3.send({ type: 'join_room', room_code: roomCode, username: 'ThirdWheel', version: '1.0.0' });
    const fullResult = await client3.waitForMessage(m => m.type === 'join_result');
    if (fullResult.success !== false || fullResult.error !== 'ROOM_FULL') {
      throw new Error(`Expected ROOM_FULL, got: ${JSON.stringify(fullResult)}`);
    }
    client3.close();
    console.log('✓ Third player rejected with ROOM_FULL');

    // Test 8: Game data forwarding (STATE and EVENT)
    console.log('[TEST 8] Game data forwarding (STATE & EVENT)...');
    // Client sends input event
    client.send({
      type: 'game_data',
      sub_type: 'event',
      event: 'client_input',
      payload: { mask: 32, tick: 101 }
    });
    const hostReceivedEvent = await host.waitForMessage(m => m.type === 'game_data' && m.event === 'client_input');
    if (hostReceivedEvent.payload.mask !== 32) {
      throw new Error(`Host received wrong event payload: ${JSON.stringify(hostReceivedEvent)}`);
    }

    // Host sends state snapshot
    host.send({
      type: 'game_data',
      sub_type: 'state',
      tick: 102,
      payload: { p1_pos: [800, 620], p2_pos: [1100, 620] }
    });
    const clientReceivedState = await client.waitForMessage(m => m.type === 'game_data' && m.sub_type === 'state');
    if (clientReceivedState.payload.p1_pos[0] !== 800) {
      throw new Error(`Client received wrong state payload: ${JSON.stringify(clientReceivedState)}`);
    }
    console.log('✓ Bidirectional STATE and EVENT game_data forwarded accurately');

    // Test 9: Host disconnect notification
    console.log('[TEST 9] Host disconnect notification...');
    host.close();
    const clientPeerLeft = await client.waitForMessage(m => m.type === 'peer_left');
    if (clientPeerLeft.reason !== 'Host left the match') {
      throw new Error(`Expected 'Host left the match', got: ${JSON.stringify(clientPeerLeft)}`);
    }
    client.close();
    console.log('✓ Client received peer_left on host exit');

    // Verify room cleaned up
    const healthAfter = await httpGet('/health');
    if (healthAfter.data.active_rooms !== 0) {
      throw new Error(`Expected 0 active rooms after host disconnect, got: ${healthAfter.data.active_rooms}`);
    }
    console.log('✓ Room memory purged successfully upon host disconnect');

    console.log('\n=======================================');
    console.log('ALL 9 RELAY INTEGRATION TESTS PASSED! ✓');
    console.log('=======================================');
    process.exit(0);

  } catch (err) {
    console.error('TEST FAILED:', err.message);
    process.exit(1);
  } finally {
    if (serverProcess) {
      serverProcess.kill();
    }
  }
}

runTests();
