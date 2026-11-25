// Краш-тест WorkDesk AI на локальной консоли: кривые данные, двойные отправки, перезапуск под нагрузкой.
// node ai-crash.mjs <папка консоли>
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const ROOT = process.argv[2];
const PORT = 23000 + Math.floor(Math.random() * 500);
const BASE = `http://127.0.0.1:${PORT}`;
const DATA = fs.mkdtempSync(path.join(os.tmpdir(), 'wd-ai-crash-'));
const PASS = 'crash-test-admin-1';
for (const f of ['workdesk-ai-1.5.3-x86_64.msi', 'workdesk-ai-1.5.3-aarch64.apk', 'workdesk-claude-0.1.1-linux-amd64', 'WorkDesk-1.5.3-x86_64.msi']) fs.writeFileSync(path.join(DATA, f), 'x'.repeat(1024));
let proc;
const results = [];
const check = (name, ok, extra = '') => { results.push([name, ok]); console.log(`${ok ? '✓' : '✗'} ${name}${extra ? ' — ' + extra : ''}`); };

async function start() {
  proc = spawn(process.execPath, ['src/server.js'], {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, ENV_FILE: path.join(DATA, 'none.env'), HOST: '127.0.0.1', PORT: String(PORT), DATA_DIR: DATA, DOWNLOADS_DIR: DATA,
      ADMIN_USERNAME: 'admin', ADMIN_PASSWORD: PASS, AUTH_MODE: 'local', SESSION_SECRET: 'y'.repeat(64),
      WORKDESK_ID_SERVER: 'wd.example.kz', WORKDESK_RELAY_SERVER: 'wd.example.kz', WORKDESK_API_SERVER: 'https://wd.example.kz', WORKDESK_PUBLIC_KEY: 'TESTKEY=' },
  });
  for (let i = 0; i < 80; i++) { try { if ((await fetch(BASE + '/healthz')).ok) return; } catch {} await new Promise((r) => setTimeout(r, 100)); }
  throw new Error('консоль не запустилась');
}
async function stop() { const ex = new Promise((r) => proc.once('exit', r)); proc.kill(); await ex; }
const j = (m, p, body, headers = {}) => fetch(BASE + p, { method: m, headers: { 'Content-Type': 'application/json', ...headers }, body: body === undefined ? undefined : (typeof body === 'string' ? body : JSON.stringify(body)) });

await start();
const login = await j('POST', '/admin/api/login', { username: 'admin', password: PASS });
const cookie = login.headers.get('set-cookie').split(';')[0];
const A = { Cookie: cookie };
const me = await (await fetch(BASE + '/admin/api/me', { headers: A })).json();
const cid = me.companies[0].id;
await j('POST', '/admin/api/users', { username: 'emp', password: 'emp-password-123', company_id: cid }, A);
const tok = (await (await j('POST', '/api/login', { username: 'emp', password: 'emp-password-123', id: '', uuid: 'u1', type: 'account' })).json()).access_token;
const B = { Authorization: `Bearer ${tok}` };

// Кривые и пустые данные
for (const [name, v] of [['пусто', ''], ['null', null], ['мусор', 'abc'], ['13-й месяц', '2026-13-01'], ['32 число', '2026-01-32'], ['число', 12345], ['объект', { a: 1 }], ['SQL', "2026-01-01'; DROP TABLE companies;--"], ['10 КБ', 'x'.repeat(10000)]]) {
  const r = await j('PATCH', `/admin/api/companies/${cid}`, { ai_until: v }, A);
  const okCodes = (v === '' || v === null) ? [200] : [400];
  check(`ai_until ${name}`, okCodes.includes(r.status), `HTTP ${r.status}`);
}
check('битый JSON в PATCH', [400].includes((await j('PATCH', `/admin/api/companies/${cid}`, '{ai_until:', A)).status));
check('PATCH без входа', [401, 403].includes((await j('PATCH', `/admin/api/companies/${cid}`, { ai_until: '2099-01-01' })).status));
check('PATCH сотрудником (не админ)', [401, 403].includes((await j('PATCH', `/admin/api/companies/${cid}`, { ai_until: '2099-01-01' }, B)).status));
for (const [name, h] of [['пустой Bearer', 'Bearer '], ['мусорный токен', 'Bearer zzz'], ['токен 64 КБ', 'Bearer ' + 'a'.repeat(65536)], ['не Bearer', 'Basic abc']]) {
  let st; try { st = (await fetch(BASE + '/api/workdesk-ai/status', { headers: { Authorization: h } })).status; } catch (e) { st = 'сеть: ' + e.message; }
  check(`status: ${name}`, st === 401 || st === 431 || st === 400, `HTTP ${st}`);
}
check('edition — мусор', (await fetch(BASE + '/api/workdesk/update?platform=windows&edition=%00%ff' + 'z'.repeat(5000))).status === 200);
check('platform — мусор', (await fetch(BASE + '/api/workdesk/update?platform=../../etc/passwd')).status === 200);
check('путь файла с ../', (await fetch(BASE + '/download/..%2F..%2Fworkdesk.db')).status === 404);
check('AI-файл без подписки', (await fetch(BASE + '/download/workdesk-ai-1.5.3-x86_64.msi', { headers: B })).status === 404);

// Двойные и одновременные отправки
const many = await Promise.all(Array.from({ length: 20 }, (_, i) => j('PATCH', `/admin/api/companies/${cid}`, { ai_until: i % 2 ? '2030-01-01' : '2031-01-01' }, A)));
check('20 одновременных PATCH — без 5xx', many.every((r) => r.status === 200));
const after = (await (await fetch(BASE + '/admin/api/companies', { headers: A })).json()).data.find((c) => c.id === cid).ai_until;
check('после гонки дата — одна из отправленных', [Date.parse('2030-01-01T23:59:59.999+05:00'), Date.parse('2031-01-01T23:59:59.999+05:00')].includes(after));
check('с подпиской файл AI отдается', (await fetch(BASE + '/download/workdesk-ai-1.5.3-x86_64.msi', { headers: B })).status === 200);

// Перезапуск сервиса под нагрузкой
let ok = 0, fail = 0, s5 = 0, stopLoad = false;
const load = (async () => {
  while (!stopLoad) {
    try { const r = await fetch(BASE + '/api/workdesk-ai/status', { headers: B, signal: AbortSignal.timeout(3000) }); if (r.status >= 500) s5++; else ok++; }
    catch { fail++; await new Promise((r) => setTimeout(r, 50)); }
  }
})();
await new Promise((r) => setTimeout(r, 500));
await stop();
await start();
await new Promise((r) => setTimeout(r, 800));
stopLoad = true; await load;
const st = await (await fetch(BASE + '/api/workdesk-ai/status', { headers: B })).json();
check('после перезапуска подписка и токен сохранились', st.active === true, `ок ${ok}, обрывов во время рестарта ${fail}, 5xx ${s5}`);
check('после перезапуска 5xx не было', s5 === 0);
await stop();
fs.rmSync(DATA, { recursive: true, force: true });
const failed = results.filter((r) => !r[1]).length;
console.log(`\nКраш-тест: ${results.length - failed} из ${results.length} проверок пройдено`);
process.exit(failed ? 1 : 0);
