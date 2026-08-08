/* 卡片溢出检查工具 (固化自 repro-overflow.cjs, 2026-08-09)
 *
 * 用途: 任何卡片模板改动(share-card CSS/渲染函数/常量)先跑此脚本, 全量扫 16 人格+2 彩蛋
 *       × 6 文件(16/48 × zh/en/hk) × 9:16, 断言 footer 不超卡底且有安全余量。
 *
 * 用法:
 *   node tests/check-card-overflow.cjs                # 扫全部 6 文件
 *   node tests/check-card-overflow.cjs --threshold 20  # 自定义最小 headroom (默认 20)
 *   node tests/check-card-overflow.cjs --file 16/zh    # 只扫单个 (16|48)/(zh|en|hk)
 *
 * 判定:
 *   - overflowPx > 1             = 溢出, 失败
 *   - headroomPx < threshold     = 余量不足, 失败 (headroom = footer.top - tagbox.bottom)
 *   - 输出完整扫描表 + 最差余量, 退出码 0=通过 1=失败
 */
const path = require('path');
const fs = require('fs');

// playwright 解析: 优先本地 node_modules, 回退 pipeline 仓库(本工作区无独立 node_modules)
let playwright;
try {
  playwright = require('playwright');
} catch (e) {
  const candidates = [
    'D:/Aion/NBTI/pipeline/NBTIMVP16/node_modules/playwright',
    'D:/Aion/NBTI/pipeline/NBTIMVP48/node_modules/playwright',
  ];
  for (const c of candidates) {
    try { playwright = require(c); break; } catch (e2) {}
  }
}
if (!playwright) {
  console.error('[check-card-overflow] 找不到 playwright, 请先 npm i 或确认 pipeline 仓库存在');
  process.exit(2);
}

const BASE = path.resolve(__dirname, '..'); // NBTIMVP16 或 NBTIMVP48
const REPO = path.basename(BASE); // NBTIMVP16 / NBTIMVP48
const repoNum = /NBTIMVP(\d+)/.test(REPO) ? REPO.match(/NBTIMVP(\d+)/)[1] : '16';

const FILES = [
  { name: 'zh', file: 'index.html' },
  { name: 'en', file: 'index-en.html' },
  { name: 'hk', file: 'index-hk.html' },
];
const EGGS = [
  { word: 'ATM', eggKey: 'allSameAnswer' },
  { word: 'OCD', eggKey: 'abcdCycle' },
];

function parseArgs(argv) {
  const out = { threshold: 20, filter: null };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--threshold') out.threshold = parseInt(argv[++i], 10) || 20;
    if (argv[i] === '--file') out.filter = argv[++i]; // e.g. '16/zh' or 'zh'
  }
  return out;
}

(async () => {
  const args = parseArgs(process.argv);
  const browser = await playwright.chromium.launch();
  const allRows = [];
  let failed = false;

  for (const f of FILES) {
    const label = repoNum + '-' + f.name;
    if (args.filter) {
      const parts = args.filter.split('/');
      if (parts.length === 2 && parts[0] !== repoNum) continue;
      if (parts.length === 1 && parts[0] !== f.name) continue;
      if (parts.length === 2 && parts[1] !== f.name) continue;
    }
    const page = await browser.newPage({ viewport: { width: 900, height: 1600 } });
    await page.addInitScript(() => {
      try { sessionStorage.setItem('nbti_redirect_done', '1'); localStorage.setItem('nbti_redirect_done', '1'); } catch (e) {}
    });
    const abs = path.join(BASE, f.file);
    await page.goto('file:///' + abs.replace(/\\/g, '/'), { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => window.RESULTS && window.RESULTS.results.length > 0, null, { timeout: 15000 });
    await page.waitForTimeout(600);

    const rows = await page.evaluate((eggs) => {
      const tpl = document.getElementById('shareCardTemplate916');
      const out = [];
      for (const p of RESULTS.results) {
        const t = tpl.cloneNode(true);
        t.style.position = 'absolute'; t.style.left = '-9999px'; t.style.top = '0'; t.style.width = '1080px';
        document.body.appendChild(t);
        try {
          bindShareCard(t, p, 87, '9:16');
          const tr = t.getBoundingClientRect();
          const footer = t.querySelector('.sc-footer').getBoundingClientRect();
          const tagbox = t.querySelector('.sc-tagbox').getBoundingClientRect();
          out.push({ kind: 'persona', word: p.word, overflowPx: Math.round(footer.bottom - tr.bottom), headroomPx: Math.round(footer.top - tagbox.bottom) });
        } catch (e) { out.push({ kind: 'persona', word: p.word, err: String(e).slice(0, 60) }); }
        t.remove();
      }
      for (const egg of eggs) {
        const t = tpl.cloneNode(true);
        t.style.position = 'absolute'; t.style.left = '-9999px'; t.style.top = '0'; t.style.width = '1080px';
        document.body.appendChild(t);
        try {
          const p = { word: egg.word, name: RESULTS.easterEggs[egg.eggKey].persona, tagline: RESULTS.easterEggs[egg.eggKey].note, code: null };
          bindShareCard(t, p, 100, '9:16');
          const tr = t.getBoundingClientRect();
          const footer = t.querySelector('.sc-footer').getBoundingClientRect();
          const tagbox = t.querySelector('.sc-tagbox').getBoundingClientRect();
          out.push({ kind: 'egg', word: egg.word, overflowPx: Math.round(footer.bottom - tr.bottom), headroomPx: Math.round(footer.top - tagbox.bottom) });
        } catch (e) { out.push({ kind: 'egg', word: egg.word, err: String(e).slice(0, 60) }); }
        t.remove();
      }
      return out;
    }, EGGS);
    allRows.push({ label, rows });
    await page.close();
  }
  await browser.close();

  // 汇总
  const allWords = ['SNIPER','TURTLE','BOT','GRANDMA','PROPHET','MONK','God of Gamblers','GEAR','MARTYR','BAGHOLDER','FOMO','STALKER','DREAMER','GHOST','YOLO','CHICKEN','ATM','OCD'];
  console.log('=== 卡片溢出扫描 ' + REPO + ' (threshold=' + args.threshold + 'px) ===');
  console.log('word'.padEnd(16) + ' | ' + allRows.map(r => r.label.padStart(7)).join(' | '));
  for (const w of allWords) {
    const cells = allRows.map(r => {
      const row = r.rows.find(x => x.word === w);
      if (!row) return '  n/a  ';
      if (row.err) return ' ERR  ';
      const hr = row.headroomPx;
      const mark = hr < args.threshold ? '!low' : (hr < 0 ? '!OVF' : '    ');
      return String(hr).padStart(6) + mark;
    });
    console.log(w.padEnd(16) + ' | ' + cells.join(' | '));
  }
  // 失败判定
  const issues = [];
  for (const r of allRows) {
    for (const row of r.rows) {
      if (row.err) issues.push({ label: r.label, word: row.word, err: row.err });
      else if (row.overflowPx > 1) issues.push({ label: r.label, word: row.word, overflowPx: row.overflowPx });
      else if (row.headroomPx < args.threshold) issues.push({ label: r.label, word: row.word, headroomPx: row.headroomPx, belowThreshold: true });
    }
  }
  const worsts = allRows.map(r => {
    const sorted = r.rows.filter(x => !x.err).sort((a, b) => a.headroomPx - b.headroomPx);
    return { label: r.label, worst: sorted[0] ? { word: sorted[0].word, headroomPx: sorted[0].headroomPx } : null };
  });
  console.log('\n=== 每文件最差余量 ===');
  for (const w of worsts) console.log(w.label + ': ' + JSON.stringify(w.worst));
  console.log('\n=== 问题清单 (应为空) ===');
  if (issues.length) {
    console.log(JSON.stringify(issues, null, 1));
    failed = true;
  } else {
    console.log('无溢出/无余量不足');
  }
  console.log(failed ? '\n[FAIL] 存在溢出或余量不足' : '\n[PASS] 全部通过');
  process.exit(failed ? 1 : 0);
})();
