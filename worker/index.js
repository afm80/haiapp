// HaiApp – خادم تذاكر المكالمات (Cloudflare Worker)
// يتحقق أن الطالب مسجّل دخوله في Firebase ثم يصدر تذكرة دخول مؤقتة لقناة Agora.
// المتغيّر السري المطلوب: AGORA_CERT (الشهادة من لوحة Agora)
// المتغيّر السري للإشعارات: FIREBASE_SA (محتوى ملف مفتاح حساب الخدمة JSON كاملاً)
// اختيارية: AGORA_APP_ID, FB_PROJECT (لهما قيم افتراضية أدناه)

const DEFAULT_APP_ID = '2a1312d2e66647ab9ba50eca869abb03';
const DEFAULT_FB_PROJECT = 'haiapp80';
const TOKEN_SECONDS = 4 * 3600;

const enc = new TextEncoder();

// ---------- تجميع البايتات (little-endian) كما في AccessToken2 ----------
const u16 = (n) => { const b = new Uint8Array(2); new DataView(b.buffer).setUint16(0, n, true); return b; };
const u32 = (n) => { const b = new Uint8Array(4); new DataView(b.buffer).setUint32(0, n >>> 0, true); return b; };
const cat = (...parts) => {
  const out = new Uint8Array(parts.reduce((a, p) => a + p.length, 0));
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
};
const pstr = (s) => { const b = typeof s === 'string' ? enc.encode(s) : s; return cat(u16(b.length), b); };

async function hmac(key, data) {
  const k = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', k, data));
}

async function deflate(bytes) {
  const cs = new CompressionStream('deflate'); // zlib
  const w = cs.writable.getWriter();
  w.write(bytes); w.close();
  return new Uint8Array(await new Response(cs.readable).arrayBuffer());
}

// ---------- بناء تذكرة RTC (الإصدار 007) ----------
async function buildRtcToken(appId, cert, channel, seconds) {
  const issueTs = Math.floor(Date.now() / 1000);
  const salt = crypto.getRandomValues(new Uint32Array(1))[0];

  // الخدمة: RTC (النوع 1) بصلاحيات الانضمام والنشر (صوت/فيديو/بيانات)
  const privs = [1, 2, 3, 4].map((k) => cat(u16(k), u32(seconds)));
  const service = cat(u16(1), u16(4), ...privs, pstr(channel), pstr('')); // uid فارغ = أي مستخدم

  const signing1 = await hmac(u32(issueTs), enc.encode(cert));
  const signing = await hmac(u32(salt), signing1);

  const info = cat(pstr(appId), u32(issueTs), u32(seconds), u32(salt), u16(1), service);
  const signature = await hmac(signing, info);
  const content = cat(pstr(signature), info);
  const packed = await deflate(content);
  let bin = '';
  for (const c of packed) bin += String.fromCharCode(c);
  return '007' + btoa(bin);
}

// ---------- التحقق من توكن Firebase ----------
let jwksCache = { keys: null, exp: 0 };
const b64uToBytes = (s) => {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
};

async function verifyFirebase(env, idToken) {
  const parts = idToken.split('.');
  if (parts.length !== 3) throw new Error('bad token');
  const header = JSON.parse(new TextDecoder().decode(b64uToBytes(parts[0])));
  const payload = JSON.parse(new TextDecoder().decode(b64uToBytes(parts[1])));
  const project = env.FB_PROJECT || DEFAULT_FB_PROJECT;

  if (!jwksCache.keys || Date.now() > jwksCache.exp) {
    const r = await fetch('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com');
    jwksCache = { keys: (await r.json()).keys, exp: Date.now() + 3600 * 1000 };
  }
  const jwk = jwksCache.keys.find((k) => k.kid === header.kid);
  if (!jwk || header.alg !== 'RS256') throw new Error('unknown key');
  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64uToBytes(parts[2]), enc.encode(parts[0] + '.' + parts[1]));
  const now = Math.floor(Date.now() / 1000);
  if (!ok || payload.aud !== project || payload.iss !== 'https://securetoken.google.com/' + project ||
      payload.exp < now || !payload.sub) throw new Error('invalid');
  return payload.sub;
}

// ---------- الإشعارات (FCM) ----------
let saCache = { token: null, exp: 0 };
const pemToBytes = (pem) => {
  const b64 = pem.replace(/-----[A-Z ]+-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
};
const b64u = (bytes) => {
  let bin = '';
  for (const c of bytes) bin += String.fromCharCode(c);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

async function googleToken(sa) {
  if (saCache.token && Date.now() < saCache.exp) return saCache.token;
  const now = Math.floor(Date.now() / 1000);
  const head = b64u(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claim = b64u(enc.encode(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/cloud-platform',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })));
  const key = await crypto.subtle.importKey('pkcs8', pemToBytes(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(head + '.' + claim)));
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: 'grant_type=' + encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer') +
      '&assertion=' + head + '.' + claim + '.' + b64u(sig),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error('sa token failed');
  saCache = { token: j.access_token, exp: Date.now() + 50 * 60 * 1000 };
  return j.access_token;
}

const fsVal = (v) => {
  if (!v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fsVal);
  if ('mapValue' in v) return v.mapValue.fields || {};
  return null;
};

async function fsGet(sa, token, path) {
  const r = await fetch(`https://firestore.googleapis.com/v1/projects/${sa.project_id}/databases/(default)/documents/${path}`,
    { headers: { authorization: 'Bearer ' + token } });
  if (!r.ok) return null;
  const d = await r.json();
  const out = {};
  for (const [k, v] of Object.entries(d.fields || {})) out[k] = fsVal(v);
  return out;
}

async function handleNotify(req, env) {
  const auth = req.headers.get('authorization') || '';
  const sender = await verifyFirebase(env, auth.replace(/^Bearer\s+/i, ''));
  if (!env.FIREBASE_SA) return json({ error: 'FIREBASE_SA missing' }, 500);
  const sa = JSON.parse(env.FIREBASE_SA);
  const body = await req.json();
  const clip = (t, n) => String(t || '').slice(0, n);
  const gtoken = await googleToken(sa);

  let recipients = [];
  let title = clip(body.title, 60);
  let text = clip(body.body, 120);
  let data = {};
  let channelHigh = false;

  if (body.kind === 'call') {
    const call = await fsGet(sa, gtoken, 'calls/' + encodeURIComponent(clip(body.callId, 40)));
    if (!call || call.callerId !== sender) return json({ error: 'forbidden' }, 403);
    recipients = call.calleeIds || [];
    text = body.video ? 'مكالمة فيديو واردة' : 'مكالمة صوتية واردة';
    data = { kind: 'call' };
    channelHigh = true;
  } else {
    const chat = await fsGet(sa, gtoken, 'chats/' + encodeURIComponent(clip(body.chatId, 40)));
    if (!chat || !(chat.participants || []).includes(sender)) return json({ error: 'forbidden' }, 403);
    recipients = (chat.participants || []).filter((u) => u !== sender);
    if (chat.groupName) {
      text = title + ': ' + text;
      title = chat.groupName;
    }
    data = { kind: 'message', chatId: clip(body.chatId, 40) };
  }

  let sent = 0;
  for (const uid of recipients.slice(0, 50)) {
    const t = await fsGet(sa, gtoken, 'tokens/' + encodeURIComponent(uid));
    for (const tok of (t && t.list) || []) {
      const msg = {
        message: {
          token: tok,
          notification: { title: title || 'HaiApp', body: text },
          data,
          android: { priority: 'HIGH', ttl: channelHigh ? '45s' : '86400s' },
        },
      };
      const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: 'POST',
        headers: { authorization: 'Bearer ' + gtoken, 'content-type': 'application/json' },
        body: JSON.stringify(msg),
      });
      if (r.ok) sent++;
    }
  }
  return json({ sent });
}

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json' } });

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname === '/agora-token' && req.method === 'GET') {
      try {
        const auth = req.headers.get('authorization') || '';
        const uid = await verifyFirebase(env, auth.replace(/^Bearer\s+/i, ''));
        const channel = url.searchParams.get('channel') || '';
        if (!/^[A-Za-z0-9_-]{1,64}$/.test(channel)) return json({ error: 'bad channel' }, 400);
        if (!env.AGORA_CERT) return json({ error: 'AGORA_CERT missing' }, 500);
        const appId = env.AGORA_APP_ID || DEFAULT_APP_ID;
        const token = await buildRtcToken(appId, env.AGORA_CERT, channel, TOKEN_SECONDS);
        return json({ token, appId, uid });
      } catch (e) {
        return json({ error: 'unauthorized' }, 401);
      }
    }
    if (url.pathname === '/notify' && req.method === 'POST') {
      try {
        return await handleNotify(req, env);
      } catch (e) {
        return json({ error: 'failed' }, 400);
      }
    }
    return new Response('HaiApp calls worker');
  },
};
