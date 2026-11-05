// HaiApp – خادم توثيق الأرقام (Cloudflare Worker)
// يستقبل رسائل تيليجرام وواتساب ويوثّق الرقم في Firestore.
// المتغيرات السرية (Secrets): TG_TOKEN, TG_SECRET, WA_TOKEN, WA_PHONE_ID, WA_VERIFY, FB_PROJECT, FB_CLIENT_EMAIL, FB_PRIVATE_KEY

const FS = (e) => `https://firestore.googleapis.com/v1/projects/${e.FB_PROJECT}/databases/(default)/documents`;

// ---------- تسجيل الدخول لـ Firestore بحساب الخدمة ----------
let tokenCache = { t: null, exp: 0 };
const b64u = (b) => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const b64uStr = (s) => b64u(new TextEncoder().encode(s));

async function accessToken(env) {
  if (tokenCache.t && Date.now() < tokenCache.exp) return tokenCache.t;
  const now = Math.floor(Date.now() / 1000);
  const head = b64uStr(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64uStr(JSON.stringify({
    iss: env.FB_CLIENT_EMAIL, scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600,
  }));
  const pem = env.FB_PRIVATE_KEY.replace(/\\n/g, '\n').replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${head}.${claim}`));
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${head}.${claim}.${b64u(sig)}`,
  });
  const j = await r.json();
  tokenCache = { t: j.access_token, exp: Date.now() + 3300 * 1000 };
  return j.access_token;
}

async function fsGet(env, path) {
  const r = await fetch(`${FS(env)}/${path}`, { headers: { authorization: `Bearer ${await accessToken(env)}` } });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error('fsGet ' + r.status);
  return r.json();
}
const sv = (d, k) => d?.fields?.[k]?.stringValue;

async function fsCommit(env, writes) {
  const base = `projects/${env.FB_PROJECT}/databases/(default)/documents`;
  const full = writes.map((w) => {
    if (w.update) w.update.name = `${base}/${w.update.name}`;
    if (w.delete) w.delete = `${base}/${w.delete}`;
    return w;
  });
  const r = await fetch(`https://firestore.googleapis.com/v1/${`projects/${env.FB_PROJECT}/databases/(default)`}/documents:commit`, {
    method: 'POST', headers: { authorization: `Bearer ${await accessToken(env)}`, 'content-type': 'application/json' },
    body: JSON.stringify({ writes: full }),
  });
  if (!r.ok) throw new Error('commit ' + r.status + ' ' + (await r.text()));
}

// ---------- منطق التوثيق ----------
// يرجع نص النتيجة للمستخدم
async function complete(env, code, provenPhone) {
  code = String(code || '').toUpperCase();
  if (!/^[A-Z0-9]{12}$/.test(code)) return 'الرمز غير صحيح.';
  const v = await fsGet(env, `verifications/${code}`);
  if (!v) return 'الرمز غير صحيح أو انتهت صلاحيته. ارجع للتطبيق وابدأ من جديد.';
  const created = new Date(v.fields?.createdAt?.timestampValue || 0).getTime();
  if (Date.now() - created > 30 * 60 * 1000) return 'انتهت صلاحية الرمز. ارجع للتطبيق وابدأ من جديد.';
  const uid = sv(v, 'uid'), key = sv(v, 'phoneKey'), country = sv(v, 'country');
  const claim = v.fields?.claim?.booleanValue === true;
  if (!uid || !key) return 'طلب غير صالح.';
  if (String(provenPhone).replace(/\D/g, '') !== key) return 'الرقم الذي أرسلت منه لا يطابق الرقم المطلوب توثيقه.';

  const writes = [];
  const ph = await fsGet(env, `phones/${key}`);
  const owner = ph ? sv(ph, 'uid') : null;
  if (owner && owner !== uid) {
    const ou = await fsGet(env, `users/${owner}`);
    if (ou?.fields?.phoneVerified?.booleanValue === true) return 'هذا الرقم موثّق لحساب آخر.';
    if (!claim) return 'هذا الرقم محجوز لحساب آخر.';
    // انقل الرقم من الحساب غير الموثّق: احذف حقول الرقم من ملفه
    if (ou) writes.push({
      update: { name: `users/${owner}`, fields: { phoneVerified: { booleanValue: false } } },
      updateMask: { fieldPaths: ['phone', 'phoneKey', 'phoneCountry', 'phoneVerified'] },
    });
  }
  writes.push({
    update: { name: `phones/${key}`, fields: { uid: { stringValue: uid }, createdAt: { timestampValue: new Date().toISOString() } } },
  });
  writes.push({
    update: { name: `users/${uid}`, fields: {
      phone: { stringValue: '+' + key }, phoneKey: { stringValue: key },
      phoneCountry: { stringValue: country || '' }, phoneVerified: { booleanValue: true } } },
    updateMask: { fieldPaths: ['phone', 'phoneKey', 'phoneCountry', 'phoneVerified'] },
  });
  writes.push({ delete: `verifications/${code}` });
  await fsCommit(env, writes);
  return 'تم توثيق رقمك بنجاح ✅ ارجع إلى HaiApp.';
}

// ---------- تيليجرام ----------
async function tg(env, method, body) {
  return fetch(`https://api.telegram.org/bot${env.TG_TOKEN}/${method}`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
}
async function onTelegram(env, update) {
  const m = update.message;
  if (!m) return;
  const chat = m.chat.id;
  if (m.text && m.text.startsWith('/start')) {
    const code = (m.text.split(' ')[1] || '').toUpperCase();
    if (!/^[A-Z0-9]{12}$/.test(code)) return tg(env, 'sendMessage', { chat_id: chat, text: 'ابدأ التوثيق من داخل تطبيق HaiApp.' });
    await fsCommit(env, [{ update: { name: `tgPending/${chat}`, fields: {
      code: { stringValue: code }, at: { timestampValue: new Date().toISOString() } } } }]);
    return tg(env, 'sendMessage', {
      chat_id: chat, text: 'اضغط الزر بالأسفل لمشاركة رقمك وإثبات ملكيته.',
      reply_markup: { keyboard: [[{ text: '📱 مشاركة رقمي', request_contact: true }]], one_time_keyboard: true, resize_keyboard: true } });
  }
  if (m.contact) {
    // يجب أن تكون جهة الاتصال هي المستخدم نفسه وليس رقماً آخر
    if (m.contact.user_id !== m.from.id) return tg(env, 'sendMessage', { chat_id: chat, text: 'شارك رقمك أنت عبر الزر فقط.' });
    const p = await fsGet(env, `tgPending/${chat}`);
    if (!p) return tg(env, 'sendMessage', { chat_id: chat, text: 'ابدأ التوثيق من داخل التطبيق أولاً.' });
    const msg = await complete(env, sv(p, 'code'), m.contact.phone_number);
    await fsCommit(env, [{ delete: `tgPending/${chat}` }]);
    return tg(env, 'sendMessage', { chat_id: chat, text: msg, reply_markup: { remove_keyboard: true } });
  }
}

// ---------- واتساب (Meta Cloud API) ----------
async function onWhatsApp(env, body) {
  for (const e of body.entry || []) for (const c of e.changes || []) for (const m of c.value?.messages || []) {
    if (m.type !== 'text') continue;
    const mm = /HaiApp\s+([A-Za-z0-9]{12})/i.exec(m.text.body || '');
    if (!mm) continue;
    const msg = await complete(env, mm[1], m.from); // m.from = الرقم المرسِل (موثوق من واتساب)
    await fetch(`https://graph.facebook.com/v20.0/${env.WA_PHONE_ID}/messages`, {
      method: 'POST', headers: { authorization: `Bearer ${env.WA_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify({ messaging_product: 'whatsapp', to: m.from, type: 'text', text: { body: msg } }) });
  }
}

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    try {
      if (url.pathname === '/telegram' && req.method === 'POST') {
        if (req.headers.get('x-telegram-bot-api-secret-token') !== env.TG_SECRET) return new Response('no', { status: 403 });
        const u = await req.json();
        ctx.waitUntil(onTelegram(env, u).catch((e) => console.log('tg', e)));
        return new Response('ok');
      }
      if (url.pathname === '/whatsapp') {
        if (req.method === 'GET') {
          return url.searchParams.get('hub.verify_token') === env.WA_VERIFY
            ? new Response(url.searchParams.get('hub.challenge')) : new Response('no', { status: 403 });
        }
        const b = await req.json();
        ctx.waitUntil(onWhatsApp(env, b).catch((e) => console.log('wa', e)));
        return new Response('ok');
      }
    } catch (e) { console.log(e); }
    return new Response('HaiApp verify worker');
  },
};
