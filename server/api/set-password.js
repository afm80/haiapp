const { setPassword } = require('../auth');
module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'post' });
  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch (_) { body = {}; } }
  const [s, b] = await setPassword(process.env, req.headers.authorization, body);
  res.status(s).json(b);
};
