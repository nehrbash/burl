import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:net';
import { test } from 'node:test';

const haveSocat = spawnSync('socat', ['-V']).status === 0;

async function withServer(onConnection, run) {
    const dir = mkdtempSync(join(tmpdir(), 'burl-askpass-'));
    mkdirSync(join(dir, 'burl'));
    const server = createServer(onConnection);
    await new Promise(resolve => server.listen(join(dir, 'burl', 'askpass.sock'), resolve));
    try {
        return await run(dir);
    } finally {
        server.close();
        rmSync(dir, { recursive: true });
    }
}

function askpass(dir, prompt) {
    return new Promise(resolve => {
        const child = spawn('sh', ['bin/burl-askpass', prompt], { env: { ...process.env, XDG_RUNTIME_DIR: dir } });
        let out = '';
        child.stdout.on('data', chunk => out += chunk);
        child.on('close', status => resolve({ status, out }));
    });
}

test('askpass exits 1 when Burl is not listening', () => {
    const dir = mkdtempSync(join(tmpdir(), 'burl-askpass-'));
    try {
        const result = spawnSync('sh', ['bin/burl-askpass', 'Password:'], { env: { ...process.env, XDG_RUNTIME_DIR: dir } });
        assert.equal(result.status, 1);
        assert.equal(result.stdout.length, 0);
    } finally {
        rmSync(dir, { recursive: true });
    }
});

test('askpass sends one prompt line and prints the reply line', { skip: !haveSocat }, async () => {
    const seen = [];
    await withServer(socket => {
        let buffer = '';
        socket.on('data', chunk => {
            buffer += chunk;
            if (buffer.includes('\n')) {
                seen.push(buffer);
                // Delayed so the client must outlive its own stdin EOF.
                setTimeout(() => socket.end('s3cret pw\nignored\n'), 800);
            }
        });
    }, async dir => {
        const result = await askpass(dir, '[sudo] password for me:\nsecond line');
        assert.equal(result.status, 0);
        assert.equal(result.out, 's3cret pw\n');
    });
    assert.deepEqual(seen, ['[sudo] password for me: second line\n']);
});

test('askpass keeps an empty password distinct from a cancel', { skip: !haveSocat }, async () => {
    await withServer(socket => socket.once('data', () => socket.end('\n')), async dir => {
        assert.deepEqual(await askpass(dir, 'p'), { status: 0, out: '\n' });
    });
    await withServer(socket => socket.once('data', () => socket.end()), async dir => {
        assert.deepEqual(await askpass(dir, 'p'), { status: 1, out: '' });
    });
});
