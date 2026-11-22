# توقيع نسخة ShamFlix Release

لا تستخدم نسخة Debug للنشر. المشروع الآن ينتج APK غير موقّع إذا لم يجد مفتاح إصدار خاصاً.

## إنشاء مفتاح الإصدار (مرة واحدة)

من مجلد `android/app` شغّل:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias shamflix
```

احتفظ بنسخة احتياطية آمنة من `upload-keystore.jks` وكلمات المرور. لا يمكن إصدار تحديث للتطبيق بنفس هوية التوقيع إذا ضاع المفتاح.

## إعداد Gradle

1. انسخ `android/key.properties.example` إلى `android/key.properties`.
2. ضع كلمات المرور التي اخترتها واسم alias.
3. اترك `storeFile=app/upload-keystore.jks` إذا أنشأت المفتاح داخل `android/app`.
4. تأكد أن `android/key.properties` وملف JKS لا يظهران ضمن ملفات Git.

بعد ذلك ينشئ `flutter build apk --release` نسخة Release موقّعة بالمفتاح الخاص. إذا لم يوجد الملف، يكون الناتج غير موقّع ومخصصاً للاختبار فقط.

## GitHub Actions

البناء التلقائي الحالي يفحص Dart ويبني APK غير موقّع عند عدم إعداد أسرار التوقيع. لم نضع أي كلمة مرور أو مفتاح خاص في المستودع.
