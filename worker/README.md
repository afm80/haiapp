# خادم تذاكر المكالمات

1. في Agora: Configure لمشروع HaiApp ← Security ← انسخ **Primary Certificate** (أيقونة النسخ).
2. في Cloudflare: Workers ← haiapp-verify ← Edit code ← امسح الكود والصق محتوى index.js ← Deploy.
3. Settings ← Variables and Secrets ← أضف `AGORA_CERT` (النوع Secret) والصق الشهادة ← Deploy.
