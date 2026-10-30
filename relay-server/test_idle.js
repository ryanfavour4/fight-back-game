const http = require('http');
const { WebSocket } = require('ws');
const { spawn } = require('child_process');

const PORT = 10002;
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

async function runIdleTests() {
  console.log('--- STARTING IDLE & KEEP-ALIVE VERIFICATION TESTS (Amendment 4) ---');

  // Spawn server with short idle timeout (1500ms timeout, 400ms check interval)
  serverProcess = spawn('node', ['server.js'], {
    cwd: __dirname,
    env: {
      ...process.env,
      PORT: String(PORT),
      ROOM_IDLE_TIMEOUT_MS: '1500',
      IDLE_CHECK_INTERVAL_MS: '400'
    },
    stdio: 'inherit'
  });
  await sleep(600);

  try {
    // TEST A: Abandoned room without keep-alive -> should be purged after idle timeout
    console.log('[TEST A] Abandoned room without keep-alive...');
    const hostA = createClient();
    await hostA.waitForOpen();
    hostA.send({ type: 'create_room', username: 'IdleHost', version: '1.0.0' });
    const createdA = await hostA.waitForMessage(m => m.type === 'room_created');
    console.log(`✓ Room ${createdA.room_code} created.`);

    // Wait without sending any pings for 2.2 seconds (longer than 1.5s timeout)
    console.log('Waiting 2.2s without keep-alive...');
    const expMsg = await hostA.waitForMessage(m => m.type === 'error' && m.message.includes('expired'), 3500);
    console.log(`✓ Received expiration notification: "${expMsg.message}"`);

    // Verify room was purged from server memory
    const healthAfterPurge = await httpGet('/health');
    if (healthAfterPurge.data.active_rooms !== 0) {
      throw new Error(`Expected 0 active rooms after purge, got: ${healthAfterPurge.data.active_rooms}`);
    }
    console.log('✓ Room memory purged successfully from server.');

    // TEST B: Room with active keep-alive pings -> should stay alive past idle timeout
    console.log('\n[TEST B] Active room with keep-alive pings...');
    const hostB = createClient();
    await hostB.waitForOpen();
    hostB.send({ type: 'create_room', username: 'ActiveHost', version: '1.0.0' });
    const createdB = await hostB.waitForMessage(m => m.type === 'room_created');
    console.log(`✓ Room ${createdB.room_code} created.`);

    // Send keep-alive pings every 500ms for 3 seconds (well past the 1.5s idle threshold)
    const keepaliveInterval = setInterval(() => {
      if (hostB.ws.readyState === WebSocket.OPEN) {
        hostB.send({ type: 'ping', t: Date.now() });
      }
    }, 500);

    await sleep(2500);
    clearInterval(keepaliveInterval);

    // Verify room is still alive!
    const healthWithKeepalive = await httpGet('/health');
    if (healthWithKeepalive.data.active_rooms !== 1) {
      throw new Error(`Expected room to remain active with keepalive, but active_rooms was: ${healthWithKeepalive.data.active_rooms}`);
    }
    console.log('✓ Room stayed active after 2.5s because keep-alive pings refreshed lastActivity.');

    // Clean up
    hostB.close();
    await sleep(300);

    console.log('\n=============================================');
    console.log('IDLE & KEEP-ALIVE VERIFICATION TESTS PASSED! ✓');
    console.log('=============================================');
    process.exit(0);

  } catch (err) {
    console.error('IDLE TEST FAILED:', err.message);
    process.exit(1);
  } finally {
    if (serverProcess) {
      serverProcess.kill();
    }
  }
}

runIdleTests();
