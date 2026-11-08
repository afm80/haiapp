const { notify } = require('../lib');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'method' });
  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }
  const [status, out] = await notify(process.env, req.headers.authorization, body);
  res.status(status).json(out);
};
