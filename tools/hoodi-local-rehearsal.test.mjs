import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

const script = new URL('./hoodi-local-rehearsal.mjs', import.meta.url).pathname;
const cowScript = new URL('./hoodi-local-cow.mjs', import.meta.url).pathname;

function rejected(program, args, rpc, reason) {
  const run = spawnSync(process.execPath, [program, ...args], {
    env: { ...process.env, HOODI_LOCAL_RPC: rpc },
    encoding: 'utf8',
    timeout: 10_000,
  });
  assert.notEqual(run.status, 0);
  assert.match(run.stderr, reason);
}

test('rehearsal refuses public and non-loopback RPCs before any transaction', () => {
  rejected(script, ['v1'], 'https://rpc.hoodi.example', /Local loopback RPC required/);
  rejected(script, ['v1'], 'http://0.0.0.0:8547', /Local loopback RPC required/);
});

test('rehearsal refuses invalid phase and missing previous evidence', () => {
  rejected(script, ['deploy'], 'http://127.0.0.1:8547', /phase must be/);
  rejected(script, ['stage-b'], 'http://127.0.0.1:8547', /previous immutable manifest path required/);
});

test('CoW mock operations refuse public RPC and malformed actions', () => {
  rejected(cowScript, ['open', 'fake.json'], 'https://rpc.hoodi.example', /loopback Anvil RPC/);
  rejected(cowScript, ['settle', 'fake.json'], 'http://127.0.0.1:8547', /open\|inspect\|fill\|finalize/);
});

test('rETH leg investment requires completed ysy order evidence', () => {
  rejected(cowScript, ['invest-reth', 'fake.json'], 'http://127.0.0.1:8549', /settled order evidence path required/);
});
