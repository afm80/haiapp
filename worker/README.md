# خادم توثيق الأرقام (تيليجرام أولاً)

الخطوات بالترتيب. افعل خطوة وأخبرني، ولا تنتقل قبل ذلك.

## 1) إنشاء بوت تيليجرام
1. في تيليجرام افتح `@BotFather` واكتب `/newbot`.
2. اختر اسماً ثم معرّفاً ينتهي بـ bot (مثال: HaiAppVerifyBot).
3. سيعطيك **توكن** طويل: احفظه.

## 2) مفتاح Firebase للخادم
1. Firebase ← ⚙️ إعدادات المشروع ← Service accounts ← Generate new private key. سينزل ملف JSON.
2. ستحتاج منه: `project_id` و `client_email` و `private_key`.

## 3) إنشاء الخادم
1. سجّل مجاناً في cloudflare.com ← Workers & Pages ← Create ← Worker.
2. افتح Edit code والصق محتوى `worker/index.js` ثم Deploy.
3. من Settings ← Variables and Secrets أضف (نوع Secret):
   - `TG_TOKEN` = توكن البوت
   - `TG_SECRET` = أي كلمة سرية طويلة (حروف وأرقام فقط)
   - `FB_PROJECT` = project_id
   - `FB_CLIENT_EMAIL` = client_email
   - `FB_PRIVATE_KEY` = private_key كاملاً
4. انسخ رابط الخادم (مثل https://xxx.workers.dev).

## 4) ربط البوت بالخادم
افتح هذا الرابط في المتصفح (بدّل القيم):
`https://api.telegram.org/bot<TG_TOKEN>/setWebhook?url=<رابط الخادم>/telegram&secret_token=<TG_SECRET>`
يجب أن ترى `"ok":true`.

## 5) تفعيل الزر في التطبيق
في `lib/verify_config.dart` ضع معرّف البوت بدون @:
`const kTelegramBot = 'HaiAppVerifyBot';`
ثم ارفع الملف وابنِ التطبيق.

## واتساب (لاحقاً)
يحتاج حساب Meta للأعمال ورقماً مخصصاً. الرابط: `<رابط الخادم>/whatsapp`، والمتغيرات: `WA_TOKEN` و `WA_PHONE_ID` و `WA_VERIFY`. ثم ضع الرقم في `kWhatsAppNumber`.
