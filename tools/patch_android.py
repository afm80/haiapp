"""يعدّل مشروع أندرويد المولَّد تلقائياً: Firebase + minSdk + الصلاحيات + اسم التطبيق"""
import json, re, shutil, sys
from pathlib import Path

EXPECTED_PACKAGE = "app.haichat.com"
android = Path("android")

# --- فحص google-services.json ---
gs = Path("google-services.json")
data = json.loads(gs.read_text(encoding="utf-8"))
packages = [c["client_info"]["android_client_info"]["package_name"] for c in data["client"]]
if EXPECTED_PACKAGE not in packages:
    sys.exit(f"::error::اسم الحزمة في google-services.json هو {packages} ويجب أن يكون {EXPECTED_PACKAGE}")
shutil.copy(gs, android / "app" / "google-services.json")

# --- settings.gradle: تعريف إضافة google-services ---
done = False
for name, kts in (("settings.gradle.kts", True), ("settings.gradle", False)):
    p = android / name
    if not p.exists():
        continue
    s = p.read_text()
    if "com.google.gms.google-services" not in s:
        if kts:
            s, n = re.subn(r'(id\("com\.android\.application"\)[^\n]*\n)',
                           r'\1    id("com.google.gms.google-services") version "4.4.2" apply false\n', s, count=1)
        else:
            s, n = re.subn(r'(id\s+"com\.android\.application"[^\n]*\n)',
                           r'\1    id "com.google.gms.google-services" version "4.4.2" apply false\n', s, count=1)
        if n == 0:
            sys.exit("::error::تعذر تعديل " + name)
        p.write_text(s)
    done = True
if not done:
    sys.exit("::error::لم أجد settings.gradle")

# --- app/build.gradle: تفعيل الإضافة + minSdk ---
done = False
for name, kts in (("build.gradle.kts", True), ("build.gradle", False)):
    p = android / "app" / name
    if not p.exists():
        continue
    s = p.read_text()
    if "com.google.gms.google-services" not in s:
        if kts:
            s = s.replace('id("com.android.application")',
                          'id("com.android.application")\n    id("com.google.gms.google-services")', 1)
        else:
            s = s.replace('id "com.android.application"',
                          'id "com.android.application"\n    id "com.google.gms.google-services"', 1)
    if kts:
        s = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23', s)
    else:
        s = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23', s)
        s = re.sub(r'minSdkVersion\s*=\s*flutter\.minSdkVersion', 'minSdkVersion 23', s)
    p.write_text(s)
    done = True
if not done:
    sys.exit("::error::لم أجد app/build.gradle")

# --- ضبط اسم الحزمة النهائي ---
for name in ("build.gradle.kts", "build.gradle"):
    p = android / "app" / name
    if p.exists():
        s = p.read_text()
        s = re.sub(r'(namespace\s*=?\s*)"[^"]+"', r'\1"' + EXPECTED_PACKAGE + '"', s)
        s = re.sub(r'(applicationId\s*=?\s*)"[^"]+"', r'\1"' + EXPECTED_PACKAGE + '"', s)
        p.write_text(s)

main_root = android / "app" / "src" / "main"
for f in list(main_root.rglob("MainActivity.*")):
    text = re.sub(r"^package\s+[\w.]+", "package " + EXPECTED_PACKAGE, f.read_text(), count=1, flags=re.M)
    parts = f.parts
    idx = max(i for i, x in enumerate(parts) if x in ("kotlin", "java"))
    root = Path(*parts[: idx + 1])
    new = root / EXPECTED_PACKAGE.replace(".", "/") / f.name
    new.parent.mkdir(parents=True, exist_ok=True)
    new.write_text(text)
    if new.resolve() != f.resolve():
        f.unlink()
        d = f.parent
        while d != root and d.exists() and not any(d.iterdir()):
            d.rmdir()
            d = d.parent


# --- توقيع ثابت: بصمة SHA ثابتة في كل بناء (مطلوبة لتسجيل الدخول بـ Google) ---
ks = Path("tools/haiapp.keystore").resolve()
if not ks.exists():
    sys.exit("::error::ملف tools/haiapp.keystore غير موجود")
for name, kts in (("build.gradle.kts", True), ("build.gradle", False)):
    p = android / "app" / name
    if not p.exists():
        continue
    s = p.read_text()
    if "haiapp.keystore" not in s:
        if kts:
            block = ('    signingConfigs {\n        create("haiapp") {\n'
                     f'            storeFile = file("{ks.as_posix()}")\n'
                     '            storePassword = "haiapp123"\n            keyAlias = "haiapp"\n'
                     '            keyPassword = "haiapp123"\n        }\n    }\n')
            s, n = re.subn(r'(\n\s*buildTypes\s*\{)', "\n" + block + r"\1", s, count=1)
            s = s.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("haiapp")')
        else:
            block = ('    signingConfigs {\n        haiapp {\n'
                     f'            storeFile file("{ks.as_posix()}")\n'
                     '            storePassword "haiapp123"\n            keyAlias "haiapp"\n'
                     '            keyPassword "haiapp123"\n        }\n    }\n')
            s, n = re.subn(r'(\n\s*buildTypes\s*\{)', "\n" + block + r"\1", s, count=1)
            s = s.replace('signingConfigs.debug', 'signingConfigs.haiapp')
        if n == 0 or "haiapp" not in s:
            sys.exit("::error::تعذر ضبط التوقيع في " + name)
        p.write_text(s)

# --- AndroidManifest: الاسم + الصلاحيات ---
mf = android / "app" / "src" / "main" / "AndroidManifest.xml"
s = mf.read_text()
s = re.sub(r'android:label="[^"]*"', 'android:label="HaiChat"', s, count=1)
perms = ('    <uses-permission android:name="android.permission.INTERNET"/>\n'
         '    <uses-permission android:name="android.permission.CAMERA"/>\n'
         '    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n'
         '    <uses-permission android:name="android.permission.READ_CONTACTS"/>\n'
         '    <uses-permission android:name="android.permission.WRITE_CONTACTS"/>\n'
         '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
         '    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>\n'
         '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>\n'
         '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>\n'
         '    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n'
         '    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>\n'
         '    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n'
         '    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>\n')
if "android.permission.INTERNET" not in s.split("<application")[0]:
    s = s.replace("<application", perms + "    <application", 1)
meta = ('        <meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/ic_stat"/>\n'
        '        <meta-data android:name="com.google.firebase.messaging.default_notification_color" android:resource="@color/hai_green"/>\n'
        '        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="messages"/>\n')
if "default_notification_icon" not in s:
    s = re.sub(r'(<application[^>]*>)', lambda m: m.group(1) + "\n" + meta, s, count=1)
mf.write_text(s)

# --- أيقونة الإشعار (أحادية اللون) + لونها ---
res = android / "app" / "src" / "main" / "res"
(res / "drawable").mkdir(parents=True, exist_ok=True)
(res / "values").mkdir(parents=True, exist_ok=True)
shutil.copy("tools/ic_stat.png", res / "drawable" / "ic_stat.png")
(res / "values" / "hai_colors.xml").write_text(
    '<resources><color name="hai_green">#A61E4E</color></resources>')

# --- ثيم متوافق مع نافذة البصمة (يمنع انهيار أندرويد 8 وما دونه) ---
for st in res.rglob("styles.xml"):
    t = st.read_text()
    t2 = re.sub(r'(<style name="(?:LaunchTheme|NormalTheme)" parent=")[^"]+(")',
                r'\1Theme.AppCompat.DayNight.NoActionBar\2', t)
    if t2 != t:
        st.write_text(t2)

# --- MainActivity: قنوات الإشعارات (رسائل بصوت، مكالمات برنين) ---
for f in main_root.rglob("MainActivity.kt"):
    f.write_text('''package PKG_PLACEHOLDER

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(NotificationManager::class.java)
            val msg = NotificationChannel("messages", "الرسائل", NotificationManager.IMPORTANCE_HIGH)
            msg.enableVibration(true)
            msg.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
            nm.createNotificationChannel(msg)
            val call = NotificationChannel("calls", "المكالمات", NotificationManager.IMPORTANCE_HIGH)
            call.enableVibration(true)
            call.vibrationPattern = longArrayOf(0, 800, 600, 800, 600, 800)
            call.lockscreenVisibility = 1
            call.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build())
            nm.createNotificationChannel(call)
        }
    }
}
'''.replace('PKG_PLACEHOLDER', EXPECTED_PACKAGE))

# --- رفع compileSdk للإضافات القديمة (مثل agora_rtc_engine المبنية على android-31) ---
KTS_FIX = """
// HAIAPP_SDK_FIX
subprojects {
    val haiFix = Action<Project> {
        val ext = extensions.findByName("android")
        if (ext != null) {
            val cur = ext.javaClass.methods.firstOrNull { it.name == "getCompileSdk" && it.parameterCount == 0 }?.invoke(ext) as? Int
            if (cur != null && cur < 35) {
                val m = ext.javaClass.methods.firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
                if (m != null) {
                    m.invoke(ext, 35)
                } else {
                    ext.javaClass.methods.firstOrNull { it.name == "compileSdkVersion" && it.parameterCount == 1 && it.parameterTypes[0] == Int::class.javaPrimitiveType }?.invoke(ext, 35)
                }
            }
        }
    }
    if (state.executed) haiFix.execute(this) else afterEvaluate(haiFix)
}
"""
GROOVY_FIX = """
// HAIAPP_SDK_FIX
subprojects {
    def haiFix = { Project pr ->
        def ext = pr.extensions.findByName("android")
        if (ext != null) {
            def cur = null
            try { cur = ext.compileSdk } catch (Throwable ignored) {}
            if (cur != null && cur < 35) { ext.compileSdk = 35 }
        }
    }
    if (project.state.executed) { haiFix(project) } else { project.afterEvaluate { haiFix(it) } }
}
"""
for name, fix in (("build.gradle.kts", KTS_FIX), ("build.gradle", GROOVY_FIX)):
    p = android / name
    if p.exists():
        t = p.read_text()
        if "HAIAPP_SDK_FIX" not in t:
            p.write_text(t + fix)
        break

print("patch OK")
