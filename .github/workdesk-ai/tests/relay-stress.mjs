// Щадящий стресс-тест релея Claude (wss://workdesk.kz/api/claude/ws): N одновременных подключений «телефон»
// служебной учетной записи CI с подпиской WorkDesk AI. Пароль — из переменной CI_PASS (не печатается).
const BASE = 'https://workdesk.kz';
const N = Number(process.argv[2] || 20);
const login = await fetch(BASE + '/api/login', {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username: 'ci-e2e', password: process.env.CI_PASS, id: '', uuid: 'ci-e2e-relay-stress', autoLogin: true, type: 'account' }),
});
const token = (await login.json()).access_token;
if (!token) { console.log('вход не удался, HTTP', login.status); process.exit(1); }
const pct = (a, q) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(q * s.length))]; };
const open = [], times = [];
let fail = 0;
const t0 = performance.now();
await Promise.all(Array.from({ length: N }, () => new Promise((resolve) => {
  const t = performance.now();
  const ws = new WebSocket(`wss://workdesk.kz/api/claude/ws?role=phone&token=${encodeURIComponent(token)}`);
  const to = setTimeout(() => { fail++; try { ws.close(); } catch {} resolve(); }, 10000);
  ws.addEventListener('open', () => { clearTimeout(to); times.push(performance.now() - t); open.push(ws); resolve(); });
  ws.addEventListener('error', () => { clearTimeout(to); fail++; resolve(); });
})));
console.log(`подключений ${N}: открыто ${open.length}, ошибок ${fail}, за ${((performance.now() - t0) / 1000).toFixed(1)} с`);
if (times.length) console.log(`время открытия p50 ${pct(times, 0.5).toFixed(0)} мс, p95 ${pct(times, 0.95).toFixed(0)} мс`);
await new Promise((r) => setTimeout(r, 3000)); // держим 3 с
const alive = open.filter((w) => w.readyState === WebSocket.OPEN).length;
console.log(`через 3 с открыто: ${alive}`);
for (const w of open) w.close();
const bad = new WebSocket('wss://workdesk.kz/api/claude/ws?role=phone&token=zzz');
const badRes = await new Promise((r) => { bad.addEventListener('open', () => r('открыт (ПЛОХО)')); bad.addEventListener('error', () => r('отклонен')); setTimeout(() => r('таймаут'), 8000); });
console.log(`мусорный токен: ${badRes}`);
process.exit(fail || alive !== open.length || badRes !== 'отклонен' ? 1 : 0);
