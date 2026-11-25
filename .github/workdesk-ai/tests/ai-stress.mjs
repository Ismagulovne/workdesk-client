// Стресс-тест WorkDesk AI на консоли: node ai-stress.mjs <base> <total> <concurrency>
// Без входа: список загрузок, проверка подписки (401), проверка обновлений edition=ai, закрытый файл AI (404), страница консоли.
const [base = 'https://workdesk.kz', total = '300', conc = '10'] = process.argv.slice(2);
const URLS = [
  ['GET', '/admin/api/downloads', [200]],
  ['GET', '/api/workdesk-ai/status', [401]],
  ['GET', '/api/workdesk/update?platform=windows&edition=ai', [200]],
  ['GET', '/api/workdesk/update?platform=linux', [200]],
  ['HEAD', '/download/workdesk-mcp-1.5.3-x86_64.msi', [404]],
  ['GET', '/console', [200]],
];
const N = Number(total), C = Number(conc);
const times = [], stats = {};
let i = 0, bad = 0, s5xx = 0, neterr = 0;
async function worker() {
  while (i < N) {
    const [m, p, ok] = URLS[i++ % URLS.length];
    const t = performance.now();
    try {
      const r = await fetch(base + p, { method: m, signal: AbortSignal.timeout(15000) });
      await r.arrayBuffer();
      const ms = performance.now() - t;
      times.push(ms);
      (stats[p] ??= []).push(ms);
      if (r.status >= 500) s5xx++;
      if (!ok.includes(r.status)) { bad++; if (bad <= 5) console.log('неожиданный ответ', m, p, r.status); }
    } catch (e) { neterr++; if (neterr <= 5) console.log('сеть', p, e.message); }
  }
}
const pct = (a, q) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.min(s.length - 1, Math.floor(q * s.length))] : 0; };
const t0 = performance.now();
await Promise.all(Array.from({ length: C }, worker));
const sec = (performance.now() - t0) / 1000;
console.log(`запросов ${N}, параллельно ${C}, за ${sec.toFixed(1)} с (${(N / sec).toFixed(1)}/с)`);
console.log(`p50 ${pct(times, 0.5).toFixed(0)} мс, p95 ${pct(times, 0.95).toFixed(0)} мс, max ${Math.max(...times).toFixed(0)} мс`);
console.log(`5xx: ${s5xx}, неожиданных кодов: ${bad}, сетевых ошибок: ${neterr}`);
for (const [p, a] of Object.entries(stats)) console.log(`  ${p}: p95 ${pct(a, 0.95).toFixed(0)} мс (${a.length})`);
process.exit(s5xx || bad || neterr ? 1 : 0);
