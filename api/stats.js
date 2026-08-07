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

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, X-Dash-Token',
  'Access-Control-Allow-Methods': 'GET, OPTIONS'
};

module.exports = async function handler(req, res) {
  if (req.method === 'OPTIONS') { res.set(CORS); return res.status(204).end(); }
  if (req.method !== 'GET') return res.status(405).json({ ok: false });

  const token = req.headers['x-dash-token'] || req.query.token || '';
  if (!process.env.DASH_TOKEN || token !== process.env.DASH_TOKEN) {
    res.set(CORS);
    return res.status(401).json({ ok: false });
  }

  let t_from, t_to;
  if (req.query.from && req.query.to) {
    t_from = req.query.from + 'T00:00:00+08:00';
    t_to = req.query.to + 'T23:59:59+08:00';
  } else {
    const days = Math.min(parseInt(req.query.days || '30', 10) || 30, 3650);
    t_to = new Date().toISOString();
    t_from = new Date(Date.now() - days * 86400000).toISOString();
  }

  /* mode=recent:最近事件明细(表格视图) */
  if (req.query.mode === 'recent') {
    const { data, error } = await supabase.rpc('dash_recent', { lim: Math.min(parseInt(req.query.n || '50', 10) || 50, 200) });
    if (error) {
      res.set(CORS);
      return res.status(500).json({ ok: false, error: error.message });
    }
    res.set(CORS);
    return res.json(data);
  }

  const { data, error } = await supabase.rpc('dash_stats', {
    t_from,
    t_to,
    f_country: req.query.country || null,
    f_event: req.query.event || null,
    f_version: req.query.version || null
  });

  if (error) {
    res.set(CORS);
    return res.status(500).json({ ok: false, error: error.message });
  }
  res.set(CORS);
  return res.json(data);
};
