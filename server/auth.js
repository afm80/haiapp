// HaiChat – تسجيل الدخول بالرقم/اليوزرنيم + كلمة المرور (Vercel)
const { tf, googleToken, fsGet, b64u, pemToBytes, verifyFirebase, DEFAULT_FB_PROJECT } = require('./lib');

const enc = new TextEncoder();
const subtle = globalThis.crypto.subtle;
const IDT = 'https://identitytoolkit.googleapis.com/v1';

function getSa(env) {
  if (!env.FIREBASE_SA) throw new Error('FIREBASE_SA missing');
  return JSON.parse(env.FIREBASE_SA);
}

// حد بسيط للمحاولات (لكل نسخة من الخادم)
const tries = new Map();
function tooMany(key) {
  const now = Date.now();
  const e = tries.get(key) || { n: 0, t: now };
  if (now - e.t > 15 * 60 * 1000) { e.n = 0; e.t = now; }
  e.n++;
  tries.set(key, e);
  if (tries.size > 5000) tries.clear();
  return e.n > 8;
}

// رقم (7-15 خانة) أو يوزرنيم -> uid
async function resolveUid(sa, gtoken, id) {
  id = String(id || '').trim().toLowerCase();
  let doc = null;
  if (/^[0-9]{7,15}$/.test(id)) doc = await fsGet(sa, gtoken, 'phones/' + id);
  else if (/^[a-z][a-z0-9_]{3,23}$/.test(id)) doc = await fsGet(sa, gtoken, 'usernames/' + id);
  return doc && typeof doc.uid === 'string' ? doc.uid : null;
}

async function emailOf(sa, gtoken, uid) {
  const r = await tf(`${IDT}/projects/${sa.project_id}/accounts:lookup`, {
    method: 'POST',
    headers: { authorization: 'Bearer ' + gtoken, 'content-type': 'application/json' },
    body: JSON.stringify({ localId: [uid] }),
  });
  const j = await r.json();
  const u = j.users && j.users[0];
  return u && u.email ? u.email : null;
}

// توقيع Custom Token بحساب الخدمة
async function customToken(sa, uid) {
  const now = Math.floor(Date.now() / 1000);
  const head = b64u(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claim = b64u(enc.encode(JSON.stringify({
    iss: sa.client_email,
    sub: sa.client_email,
    aud: 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
    iat: now,
    exp: now + 3000,
    uid,
  })));
  const key = await subtle.importKey('pkcs8', pemToBytes(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(head + '.' + claim)));
  return head + '.' + claim + '.' + b64u(sig);
}

// POST {id, password} -> [status, body]
async function login(env, ip, body) {
  try {
    const sa = getSa(env);
    if (!env.FB_WEB_API_KEY) return [500, { error: 'FB_WEB_API_KEY missing' }];
    body = body && typeof body === 'object' ? body : {};
    const id = String(body.id || '').trim().toLowerCase();
    const password = String(body.password || '');
    if (!id || !password || password.length > 128) return [400, { error: 'bad' }];
    if (tooMany('ip:' + ip) || tooMany('id:' + id)) return [429, { error: 'too-many' }];
    const gtoken = await googleToken(sa);
    const uid = await resolveUid(sa, gtoken, id);
    const email = uid ? await emailOf(sa, gtoken, uid) : null;
    if (!uid || !email) return [401, { error: 'invalid' }];
    const r = await tf(`${IDT}/accounts:signInWithPassword?key=${encodeURIComponent(env.FB_WEB_API_KEY)}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: false }),
    });
    const j = await r.json();
    if (!r.ok || j.localId !== uid) {
      const msg = (j.error && j.error.message) || '';
      if (msg.includes('TOO_MANY')) return [429, { error: 'too-many' }];
      return [401, { error: 'invalid' }];
    }
    return [200, { token: await customToken(sa, uid) }];
  } catch (e) {
    return [500, { error: 'failed', detail: String((e && e.message) || e).slice(0, 120) }];
  }
}

// POST {id} -> دائماً ok (لا نكشف هل الحساب موجود)
async function reset(env, ip, body) {
  try {
    const sa = getSa(env);
    body = body && typeof body === 'object' ? body : {};
    const id = String(body.id || '').trim().toLowerCase();
    if (tooMany('rip:' + ip) || tooMany('rid:' + id)) return [429, { error: 'too-many' }];
    const gtoken = await googleToken(sa);
    const uid = await resolveUid(sa, gtoken, id);
    const email = uid ? await emailOf(sa, gtoken, uid) : null;
    let hint = '';
    if (email) {
      await tf(`${IDT}/accounts:sendOobCode?key=${encodeURIComponent(env.FB_WEB_API_KEY || '')}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'X-Firebase-Locale': 'ar' },
        body: JSON.stringify({ requestType: 'PASSWORD_RESET', email }),
      });
      const [a, d] = email.split('@');
      hint = a.slice(0, 2) + '***@' + d;
    }
    return [200, { ok: true, hint }];
  } catch (e) {
    return [200, { ok: true, hint: '' }];
  }
}

// POST {password} + Bearer idToken: تعيين/تغيير كلمة المرور لصاحب الجلسة
async function setPassword(env, authHeader, body) {
  try {
    const sa = getSa(env);
    const uid = await verifyFirebase(env, String(authHeader || '').replace(/^Bearer\s+/i, ''));
    body = body && typeof body === 'object' ? body : {};
    const password = String(body.password || '');
    if (password.length < 8 || password.length > 128) return [400, { error: 'short' }];
    if (tooMany('sp:' + uid)) return [429, { error: 'too-many' }];
    const gtoken = await googleToken(sa);
    const email = await emailOf(sa, gtoken, uid);
    if (!email) return [400, { error: 'no-email' }];
    const r = await tf(`${IDT}/projects/${sa.project_id}/accounts:update`, {
      method: 'POST',
      headers: { authorization: 'Bearer ' + gtoken, 'content-type': 'application/json' },
      body: JSON.stringify({ localId: uid, password }),
    });
    if (!r.ok) {
      const t = await r.text();
      return [400, { error: 'update-failed', detail: t.slice(0, 160) }];
    }
    // علامة أن لهذا الحساب كلمة مرور (لا تُخزَّن الكلمة نفسها)
    const base = `projects/${sa.project_id}/databases/(default)/documents/users/${uid}`;
    await tf(`https://firestore.googleapis.com/v1/${base}?updateMask.fieldPaths=hasPassword`, {
      method: 'PATCH',
      headers: { authorization: 'Bearer ' + gtoken, 'content-type': 'application/json' },
      body: JSON.stringify({ fields: { hasPassword: { booleanValue: true } } }),
    });
    return [200, { ok: true }];
  } catch (e) {
    return [401, { error: 'unauthorized' }];
  }
}

module.exports = { login, reset, setPassword };
