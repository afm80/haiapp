# HaiApp — المرحلة 1

## المميزات الحالية
- تسجيل دخول وإنشاء حساب بالإيميل (مجاني)
- قائمة محادثات مرتبة بآخر رسالة
- رسائل لحظية
- الرد على رسالة (مثل تلجرام)
- تعديل وحذف رسائلك (اضغط مطولاً على الرسالة)
- إرسال الصور من المعرض أو الكاميرا (مجاني، تُخزَّن مضغوطة داخل Firestore)
- حالة القراءة: ✓ مرسلة، ✓✓ مقروءة (زرقاء)
- نسخ الرسالة
- واجهة عربية RTL + وضع داكن

## خطوات التشغيل
1. أنشئ مشروع Flutter فارغ ثم انسخ هذه الملفات فوقه:
   `flutter create haiapp`
   (انسخ `pubspec.yaml` ومجلدي `lib/` و`assets/` فوق الموجودين)
2. أنشئ مشروع في https://console.firebase.google.com (الخطة المجانية Spark)
   - فعّل Authentication ← Email/Password
   - فعّل Firestore Database
   - الصق محتوى `firestore.rules` في تبويب Rules
3. اربط المشروع:
   ```
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   هذا ينشئ `lib/firebase_options.dart` تلقائياً.
4. ولّد أيقونة التطبيق:
   ```
   flutter pub get
   dart run flutter_launcher_icons
   ```
5. اسم التطبيق تحت الأيقونة: في `android/app/src/main/AndroidManifest.xml`
   غيّر `android:label` إلى `HaiApp`، وفي iOS غيّر `CFBundleDisplayName` في `ios/Runner/Info.plist`.
6. شغّل:
   ```
   flutter run
   ```

## صلاحيات الصور
- iOS: أضف في `ios/Runner/Info.plist`:
  ```
  <key>NSPhotoLibraryUsageDescription</key><string>لإرسال الصور</string>
  <key>NSCameraUsageDescription</key><string>لالتقاط الصور</string>
  ```
- أندرويد: ما يحتاج شيء للمعرض. للكاميرا أضف في `AndroidManifest.xml`:
  `<uses-permission android:name="android.permission.CAMERA"/>`

## ملاحظة عن الصور والتخزين
Firebase Storage صار يتطلب خطة مدفوعة (Blaze) للمشاريع الجديدة، لذلك الصور هنا
تُضغط (حد أقصى 1024px) وتُحفظ داخل Firestore. تكفي للصور العادية، لكن للفيديو
والملفات الكبيرة لاحقاً نستخدم Supabase Storage أو Cloudinary (فيهم طبقات مجانية).

## المرحلة التالية
- المجموعات والقنوات
- الإشعارات (FCM)
