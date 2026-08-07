/* Dashboard 统计 API:GET /api/stats
 * 门禁:请求头 X-Dash-Token 或 ?token= 必须等于环境变量 DASH_TOKEN
 * 参数:days(默认30) 或 from+to(YYYY-MM-DD);country / event / version 过滤
 * 返回:dash_stats 聚合 JSON(漏斗/人格/地区/日趋势/KPI)
 * 部署:与 api/event.js 同目录,Vercel 自动识别
 */
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_KEY
);

const setCORS = (res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Dash-Token');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
};

module.exports = async function handler(req, res) {
  if (req.method === 'OPTIONS') { setCORS(res); return res.status(204).end(); }
  if (req.method !== 'GET') { setCORS(res); return res.status(405).json({ ok: false }); }

  const token = req.headers['x-dash-token'] || req.query.token || '';
  if (!process.env.DASH_TOKEN || token !== process.env.DASH_TOKEN) {
    setCORS(res);
    return res.status(401).json({ ok: false });
  }

  let t_from, t_to;
  if (req.query.from && req.query.to) {
    /* from/to 格式校验:拒绝非法日期,避免拼进 timestamptz 后 RPC 抛错(500) */
    if (!/^\d{4}-\d{2}-\d{2}$/.test(req.query.from) || !/^\d{4}-\d{2}-\d{2}$/.test(req.query.to)) {
      setCORS(res);
      return res.status(400).json({ ok: false });
    }
    t_from = req.query.from + 'T00:00:00+08:00';
    t_to = req.query.to + 'T23:59:59+08:00';
  } else {
    const days = Math.min(parseInt(req.query.days || '30', 10) || 30, 3650);
    /* days 路径同样按 +08:00 构造,与 RPC 的 Asia/Shanghai 分日一致(旧实现用 UTC,边界差 8 小时) */
    const nowCn = new Date(Date.now() + 8 * 3600000);
    t_to = nowCn.toISOString().slice(0, 10) + 'T23:59:59+08:00';
    const fromCn = new Date(Date.now() - days * 86400000 + 8 * 3600000);
    t_from = fromCn.toISOString().slice(0, 10) + 'T00:00:00+08:00';
  }

  /* mode=recent:最近事件明细(表格视图) */
  if (req.query.mode === 'recent') {
    const { data, error } = await supabase.rpc('dash_recent', { lim: Math.min(parseInt(req.query.n || '50', 10) || 50, 200) });
    if (error) {
      setCORS(res);
      return res.status(500).json({ ok: false, error: error.message });
    }
    setCORS(res);
    return res.json(data);
  }

  /* mode=times:时长与参与度(G5,零新埋点:基于 test_progress.perQuestionMs[] + 事件时间差) */
  if (req.query.mode === 'times') {
    const { data, error } = await supabase.rpc('dash_times', {
      t_from,
      t_to,
      f_version: req.query.version || null,
      f_lang: req.query.lang || null,
      f_country: req.query.country || null,
      f_ua: req.query.ua || null
    });
    if (error) {
      setCORS(res);
      return res.status(500).json({ ok: false, error: error.message });
    }
    setCORS(res);
    return res.json(data);
  }

  const { data, error } = await supabase.rpc('dash_stats', {
    t_from,
    t_to,
    f_country: req.query.country || null,
    f_event: req.query.event || null,
    f_version: req.query.version || null,
    f_excl_speed: req.query.excl_speed === '1'
  });

  if (error) {
    setCORS(res);
    return res.status(500).json({ ok: false, error: error.message });
  }
  setCORS(res);
  return res.json(data);
};
