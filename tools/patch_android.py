"""يعدّل مشروع أندرويد المولَّد تلقائياً: Firebase + minSdk + الصلاحيات + اسم التطبيق"""
import json, re, shutil, sys
from pathlib import Path

EXPECTED_PACKAGE = "app.haiapp.com"
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

# --- AndroidManifest: الاسم + الصلاحيات ---
mf = android / "app" / "src" / "main" / "AndroidManifest.xml"
s = mf.read_text()
s = re.sub(r'android:label="[^"]*"', 'android:label="HaiApp"', s, count=1)
perms = ('    <uses-permission android:name="android.permission.INTERNET"/>\n'
         '    <uses-permission android:name="android.permission.CAMERA"/>\n'
         '    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n'
         '    <uses-permission android:name="android.permission.READ_CONTACTS"/>\n')
if "android.permission.INTERNET" not in s.split("<application")[0]:
    s = s.replace("<application", perms + "    <application", 1)
mf.write_text(s)
print("patch OK")
