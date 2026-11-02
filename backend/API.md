# Waj API

Base URL أثناء التطوير: `http://127.0.0.1:8000`

الراوتات المحمية تحتاج الترويسة التالية بعد تسجيل الدخول:

```text
Authorization: Bearer <access_token>
```


## المصادقة

### `POST /auth/register`

```json
{
  "full_name": "Student Name",
  "phone_number": "07XXXXXXXXX",
  "password": "at-least-8-characters",
  "role": "student"
}
```

`role` يقبل `student` أو `cafeteria_owner`، والقيمة الافتراضية `student`. تسجيل صاحب الكفتريا ينشئ طلب موافقة ولا يرجع رمز دخول حتى يوافق الأدمن. تسجيل الطالب يرجع `access_token`. رقم الهاتف يجب أن يكون عراقياً، والتحقق عبر SMS غير مفعّل حالياً.

### `POST /auth/login`

```json
{
  "phone_number": "+9647XXXXXXXXX",
  "password": "at-least-8-characters"
}
```

### `GET /auth/me`

يرجع بيانات الحساب الحالي، ويتطلب Bearer token.

## الكفتريات والأصناف

| Method | Path | الصلاحية |
| --- | --- | --- |
| GET | `/cafeterias` | عام |
| POST | `/cafeterias` | صاحب كفتريا مسجّل دخوله |
| GET | `/cafeterias/{cafeteria_id}` | عام، ويرجع الأصناف المتاحة |
| GET | `/cafeterias/{cafeteria_id}/items` | عام |
| POST | `/cafeterias/{cafeteria_id}/items` | مالك الكفتريا |
| PATCH | `/cafeterias/{cafeteria_id}/items/{item_id}` | مالك الكفتريا |
| DELETE | `/cafeterias/{cafeteria_id}/items/{item_id}` | مالك الكفتريا؛ يخفي الصنف ولا يحذفه |

مثال إضافة صنف:

```json
{
  "name": "Tea",
  "description": "Iraqi tea",
  "price": 500
}
```

## الطلبات

### `POST /orders`

طالب مسجّل دخوله ينشئ طلباً من كفتريا واحدة. الأسعار والمجموع يحسبها السيرفر من المنيو.

```json
{
  "cafeteria_id": 1,
  "items": [
    {"item_id": 3, "quantity": 2},
    {"item_id": 7, "quantity": 1}
  ]
}
```

الاستجابة تتضمن `qr_token` و`qr_image_data_url` بصيغة PNG data URL. الباك إند يولّد الصورة، والواجهة تعرضها مباشرة. الحد الافتراضي 10 طلبات لكل طالب خلال 15 دقيقة؛ يتغير عبر `MAX_ORDERS_PER_STUDENT_PER_15_MINUTES`.

### استعراض الطلبات

| Method | Path | الصلاحية |
| --- | --- | --- |
| GET | `/orders/mine` | الطالب، مع رمز QR لطلباته |
| GET | `/orders/{order_id}` | صاحب الطلب أو صاحب الكفتريا؛ الرمز يظهر لصاحب الطلب فقط |
| GET | `/cafeterias/{cafeteria_id}/orders` | مالك الكفتريا |

### تحديث حالة الطلب

`PATCH /orders/{order_id}/status`، لصاحب الكفتريا فقط:

```json
{"status": "preparing"}
```

الانتقالات المسموحة بهذا المسار: `new` إلى `preparing` ثم `ready`. الاستلام يتم بمسار QR.

### تأكيد الاستلام عبر QR

`POST /orders/{order_id}/receive`، لصاحب الكفتريا، بعد أن يمسح QR الطالب:

```json
{"qr_token": "token-read-from-the-qr"}
```

لازم تكون حالة الطلب `ready` والرمز صحيحاً؛ بعدها تصبح الحالة `received` ويسجل وقت الاستلام.

## التقييمات

- `POST /orders/{order_id}/rating`: صاحب الطلب يقيّم بعد الاستلام. الجسم: `{"stars": 5, "comment": "Good"}`. تقييم واحد لكل طلب.
- `GET /cafeterias/{cafeteria_id}/ratings`: قائمة التقييمات.
- `GET /cafeterias/{cafeteria_id}/rating-summary`: عدد التقييمات ومتوسط النجوم.

## التحديث اللحظي

WebSocket: `/ws/cafeterias/{cafeteria_id}/orders`. بعد الاتصال، أرسل أول رسالة JSON خلال 10 ثوانٍ:

```json
{"token": "<access_token>"}
```

يسمح الاتصال فقط لمالك الكفتريا. الأحداث الواردة تتضمن `order.created` و`order.status_changed` مع معرّف الطلب والحالة.

## صلاحيات الأدمن

لا يمكن إنشاء حساب أدمن من التسجيل العام. لإنشاء أول أدمن، سجّل حساباً عادياً ثم شغّل الأمر التالي من مجلد `Waj-BE`: `uv run python scripts/promote_admin.py`. أدخل رقم الحساب بصيغة `+964` وأكّد بكتابة `yes`. سجّل الدخول مجدداً للحصول على رمز دخول بصلاحية الأدمن.

يستطيع الأدمن مراجعة طلبات أصحاب الكفتريات:

| Method | Path | الصلاحية |
| --- | --- | --- |
| GET | `/admin/owner-applications/pending` | أدمن |
| PATCH | `/admin/owner-applications/{application_id}/approve` | أدمن؛ يفعّل صلاحية صاحب الكفتريا |
| PATCH | `/admin/owner-applications/{application_id}/reject` | أدمن؛ يرفض الطلب ويعطّل الحساب |

صاحب الكفتريا لا يستطيع تسجيل الدخول أو إدارة كفتريته قبل الموافقة.
