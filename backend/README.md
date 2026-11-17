# Wajbati API (FastAPI)

سيرفر تطبيق وجباتي: حسابات الطلاب، الكافيتريات وقوائمها، الطلبات بحالاتها الأربع،
أوقات الاستلام، التقييم، المفضلة، الإشعارات، ولوحة تحكم الكافيتريا.

## التشغيل

```bash
cd backend
uv sync
uv run uvicorn project.main:app --host 0.0.0.0 --port 8001
```

- التوثيق التفاعلي لكل الواجهات: http://localhost:8001/docs
- عند أول تشغيل تُنشأ قاعدة البيانات `wajbati.db` وتُضاف الكافيتريات الخمس
  (بنفس الرموز السرية) وقائمة أولية وحساب طالب تجريبي: `07700000000` / `123456`.

## الإعدادات (متغيرات البيئة أو ملف `.env`)

| المتغير | الافتراضي | الوصف |
|---|---|---|
| `DATABASE_URL` | `sqlite:///./wajbati.db` | قاعدة البيانات. يقبل `postgres://...` من Render مباشرة |
| `WAJBATI_SECRET` | مفتاح تطوير | مفتاح توقيع JWT. **إجباري على Render** (السيرفر يرفض التشغيل بدونه) |
| `WAJBATI_TZ` | `Asia/Baghdad` | توقيت الجامعة (سيرفرات الاستضافة تعمل بتوقيت UTC) |
| `FCM_SERVICE_ACCOUNT_JSON` | — | (اختياري) محتوى ملف حساب خدمة Firebase لتفعيل إشعارات Push |
| `FCM_SERVICE_ACCOUNT_FILE` | — | (اختياري) أو مسار ذلك الملف |

عند التشغيل يُحدَّث شكل قاعدة البيانات تلقائياً (جداول وأعمدة جديدة) دون حذف البيانات.

## النشر على Render

1. ارفع المشروع إلى GitHub.
2. في Render: **New ← Blueprint** ← اختر المستودع. ملف `render.yaml` في جذر المشروع
   ينشئ السيرفر `wajbati-api` وقاعدة بيانات PostgreSQL ويولّد `WAJBATI_SECRET`.
3. انتظر حتى ينجح فحص `/health`، ثم استخدم الرابط في التطبيق (زر "السيرفر" أو `--dart-define=API_URL=`).

ملاحظة: قاعدة PostgreSQL المجانية في Render تنتهي بعد مدة؛ للاستخدام الطويل استخدم خطة مدفوعة
أو قاعدة خارجية (مثل Neon) وضع رابطها في `DATABASE_URL`.

## إشعارات Push (Firebase Cloud Messaging)

جانب السيرفر جاهز: يسجّل أجهزة الطلاب (`POST /devices`) ويرسل إشعاراً لكل تغيير في حالة الطلب.
للتفعيل:
1. أنشئ مشروعاً في [Firebase Console](https://console.firebase.google.com).
2. Project settings ← Service accounts ← **Generate new private key**، وضع محتوى الملف في `FCM_SERVICE_ACCOUNT_JSON`.
3. ربط `firebase_messaging` موجود في التطبيق ومعطل افتراضيًا. اتبع [دليل إعداد Firebase](../docs/UPDATES.md) لملء إعدادات البناء وتفعيله؛ لا حاجة لإضافة المكتبة مرة أخرى.

`GET /push/status` يوضح هل الإرسال مفعّل.

## الاختبارات

```bash
uv run pytest
```

## الواجهات الرئيسية

| الطالب | |
|---|---|
| `POST /auth/register`، `POST /auth/login` | إنشاء حساب / دخول (يرجع JWT) |
| `GET /cafeterias` | الكافيتريات مع حالتها (open / busy / closed) |
| `GET /cafeterias/{id}/menu` | قائمة الكافيتريا |
| `GET /cafeterias/{id}/slots?prep_minutes=` | أوقات الاستلام المتاحة |
| `POST /orders`، `GET /orders/mine` | إنشاء طلب / طلباتي |
| `POST /orders/{id}/arrived`، `POST /orders/{id}/rating` | "وصلت" / التقييم |
| `GET/PUT/DELETE /favorites` | المفضلة |
| `GET /notifications?after_id=` | الإشعارات |
| `POST /devices`، `POST /devices/unregister` | تسجيل/إلغاء جهاز لإشعارات Push |
| `GET /menu/{id}/image` | صورة الصنف |

| مسؤول الكافيتريا (`/admin`) | |
|---|---|
| `POST /admin/login` | دخول بالرمز السري |
| `GET /admin/orders`، `PATCH /admin/orders/{id}/status` | الطلبات وتغيير الحالة |
| `POST /admin/scan` | ماسح QR (محتوى الرمز = رقم الطلب) |
| `POST/PATCH/DELETE /admin/menu` | إدارة القائمة |
| `POST /admin/menu/with-image` | إضافة طبق وصورته معًا عبر multipart: `name` و`price` و`prep_minutes` و`file`؛ الصورة غير الصالحة لا تنشئ طبقًا ناقصًا |
| `POST/DELETE /admin/menu/{id}/image` | رفع/حذف صورة الصنف (JPG/PNG/WEBP/GIF حتى 2MB، تُحفظ في قاعدة البيانات) |
| `PUT /admin/status` | فرض حالة الكافيتريا |
| `GET /admin/revenue?days=7` | الدخل |
| `GET /admin/reports?period=week` | تقرير المبيعات بتاريخ التسليم، مع سلسلة يومية والأطباق الأكثر طلبًا؛ الفترات: `today` و`week` و`month` و`custom` |

حالات الطلب: `received` ← `preparing` ← `ready` ← `delivered` (للأمام فقط).

التحديث الحالي يفرض الانتقال خطوة واحدة في كل مرة، ولا يسمح بمسح QR قبل `ready`.
الطالب يستطيع `POST /orders/{id}/cancel`، والكافيتريا تستطيع `POST /admin/orders/{id}/reject`
مع `{"reason": "سبب الرفض"}` قبل بدء التحضير فقط. الحالتان `cancelled` و`rejected` نهائيتان.

يرسل التطبيق `request_key` اختياريًا مع `POST /orders`؛ إعادة نفس المفتاح والمحتوى تعيد الطلب الموجود.
فحص سعة الاستلام والحجز محميان بقفل قاعدة البيانات داخل معاملة واحدة.

واجهات إضافية: `POST /auth/password`، `POST /admin/password`، `GET /admin/summary`،
و`GET /admin/orders/{id}/events`. ترحيل الأعمدة مسجل في `schema_migrations`.
راجع [دليل التشغيل والأمان والنسخ الاحتياطي](../docs/UPDATES.md) قبل النشر.

مثال فترة مخصصة: `/admin/reports?period=custom&start_date=2026-11-01&end_date=2026-11-10`.
تاريخ النهاية مشمول، وأقصى فترة 366 يومًا، والتوقيت `Asia/Baghdad`. الفترة `week` تعني آخر 7 أيام شاملة اليوم.
تسجّل حالة التسليم `delivered_at`، ويستعيد الترحيل رقم 3 الوقت من `order_events` للطلبات السابقة متى توفر.
الطلبات القديمة دون وقت تسليم أو سجل تُحسب بتاريخ إنشائها مع إظهار عددها في `estimated_orders`.


## مسؤول المنصة

إنشاء الحساب الأول يتم بواسطة مشغّل الخادم: `uv run python -m project.manage create-admin admin`. كلمة المرور تُطلب تفاعليًا ويجب أن تتكون من 12 حرفًا على الأقل وحتى 72 بايت. لا تُستبدل كلمة مرور حساب موجود، ولا توجد بيانات دخول افتراضية في الكود. الاستعادة اليدوية: `uv run python -m project.manage reset-password platform admin`.

واجهات الدور المستقل: `POST /platform/login` و`GET /platform/me` و`GET /platform/cafeterias` و`POST /platform/cafeterias` و`POST /platform/password`. لا يستطيع الطالب أو صاحب الكافيتريا إضافة كافيتريات. إنشاء الكافيتريا يتطلب الاسم والموقع وساعات متسلسلة ورمزًا من 12 إلى 72 رمز ASCII دون مسافات؛ يُحفظ الرمز مجزأً ولا يُعاد ضمن بيانات القائمة. كلمة المرور الجديدة تنهي جلسات المسؤول القديمة.
