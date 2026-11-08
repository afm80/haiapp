const { DEFAULT_APP_ID, TOKEN_SECONDS, buildRtcToken, verifyFirebase } = require('../lib');

module.exports = async (req, res) => {
  try {
    const uid = await verifyFirebase(process.env, String(req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
    const channel = String((req.query && req.query.channel) || '');
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(channel)) return res.status(400).json({ error: 'bad channel' });
    if (!process.env.AGORA_CERT) return res.status(500).json({ error: 'AGORA_CERT missing' });
    const appId = process.env.AGORA_APP_ID || DEFAULT_APP_ID;
    const token = await buildRtcToken(appId, process.env.AGORA_CERT, channel, TOKEN_SECONDS);
    res.status(200).json({ token, appId, uid });
  } catch (e) {
    res.status(401).json({ error: 'unauthorized' });
  }
};
