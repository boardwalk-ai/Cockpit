# Plan: File upload၊ pgvector knowledge DB၊ account ဖျက်တာ

ရေးတဲ့နေ့: 2026-10-05 · အခြေအနေ: **ဆွေးနွေးပြီး၊ code မရေးရသေး**

## ဆုံးဖြတ်ပြီးသားတွေ

| # | ဆုံးဖြတ်ချက် |
|---|---|
| 1 | **Shared pool = public web source ပဲ။** User upload file တွေက private၊ ဘယ်တော့မှ မမျှဘူး |
| 2 | User data ကို **model training အတွက် မသုံးဘူး**။ Analytics: content မစုဘူး (အောက်က "Analytics" ကြည့်) |
| 3 | Account ဖျက်ရင် usage record တွေကို **anonymize** (user_id ဖယ်၊ စုစုပေါင်း signal ကျန်) |
| 4 | **သီးသန့် `knowledge` database** (pgvector)၊ GhostWriter၊ Study Studio အကုန်သုံး |
| 5 | Account ဖျက်တာကို **tombstone table** နဲ့ service တွေဆီ အသိပေး |
| 6 | အသက်ငယ်တဲ့ user ပါနိုင်တယ်လို့ ယူဆပြီး ဆောက်မယ် (အောက်က "အသက်" ကြည့်) |

---

## အဆင့် 1 — Account ဖျက်တာ (အရင်ဆုံး၊ အခုတောင် အပေါက်ရှိနေလို့)

**ပြဿနာ:** အခု account ဖျက်ရင် GhostWriter DB ထဲက project၊ essay၊ run၊ device တွေ ကျန်နေတယ် (DB မတူလို့ cascade မရ)။

1. **Shared DB:** `deleted_users (user_id uuid PRIMARY KEY, firebase_uid text, deleted_at timestamptz)`
   - `users` table ပေါ်က **DB trigger** က ဖြည့်မယ် (row ဖျက်တာ ဒါမှမဟုတ် "ဖျက်ပြီး" flag တင်တာ)။ Python API ကို မပြင်ရဘူး
   - Python API က user ကို တကယ်ဖျက်လား flag ပဲ တင်လား **deploy ခါနီး စစ်ရမယ်** (read-only)
2. **Service တိုင်း** (GhostWriter worker loop ထဲ၊ ၁၀ မိနစ်တိုင်း): မလုပ်ရသေးတဲ့ tombstone တွေကို ယူ၊ ကိုယ့် data ကို ဖျက်၊ လုပ်ပြီးကြောင်း ကိုယ့် DB ထဲ မှတ်
   - GhostWriter: active run တွေ ရပ် → project (document၊ version၊ run၊ event cascade)၊ folder၊ device ဖျက်
   - Knowledge DB: user file၊ chunk၊ embedding ဖျက်၊ `source_events.user_id` ကို NULL
   - ✅ **GhostWriter sweeper ပြီးပြီ** (10-06): shared trigger (`shared-sql/2026-10-06_accounts_and_app_status.sql`)၊ ၁၀ မိနစ်တိုင်း၊ tests `phase7_accounts`
3. **App ထဲ "Delete account" ခလုတ်** — **shell ရဲ့ Settings ထဲမှာ** (GhostWriter module ထဲ မဟုတ်)။ **Apple နဲ့ Google နှစ်ခုလုံး account ဆောက်လို့ရတဲ့ app မှာ app ထဲကနေ ဖျက်ခွင့်ပေးဖို့ မဖြစ်မနေ လိုတယ်**။ Release မတိုင်ခင် လိုတယ်
4. Backup: ဖျက်ပြီးသား data က backup ထဲကနေ ဘယ်နှစ်ရက်အတွင်း ပျောက်မလဲ privacy policy မှာ ရေး

## အဆင့် 2 — Knowledge DB + file upload (private)

- **DB:** `knowledge` (Postgres + pgvector)။ Production server မှာ pgvector ရှိလား deploy ခါနီး စစ် (OctoNotes က သုံးပြီးသား)
- **Upload:** composer ရဲ့ **+** → PDF / DOCX / TXT → GhostWriter API (အရွယ် ကန့်သတ်၊ ဥပမာ 20 MB) → server disk ပေါ် သိမ်း
- **Process (worker job):** စာထုတ် → chunk (~500 token၊ overlap နည်းနည်း) → embed → `user_chunks`
  - Scan လုပ်ထားတဲ့ PDF (ပုံ) ကို OCR လိုမယ်၊ နောက်မှ
  - Embedding model: OctoNotes က သုံးနေတဲ့ provider / dimension ကို ပြန်သုံး (တစ်မျိုးတည်း)၊ row တိုင်းမှာ model နာမည် မှတ်
- **Run ထဲမှာ:** upload file တွေက source ဖြစ်တယ်။ Paragraph တစ်ခုချင်းအတွက် ဆိုင်တဲ့ chunk top-k ကို writer ဆီ ပို့ (citation အတွက် file title / author ပါ)၊ source review မှာလည်း ပေါ်
- **ဖျက်:** file တစ်ခုချင်း ဖျက်လို့ရ၊ project / account ဖျက်ရင် cascade
- **ဆုံးဖြတ်ရန် (နောက်မှ):** upload ကို OctoCredits ဘယ်လိုဖြတ်မလဲ (page / chunk အလိုက်)

```
user_files  (id, user_id, project_id, name, mime, bytes, pages, status, created_at)
user_chunks (id, file_id → user_files ON DELETE CASCADE, user_id, idx, text, embedding vector(N), model)
```

## အဆင့် 3 — Shared web library (public)

- Scrape လုပ်တိုင်း URL ကို normalize လုပ်ပြီး `web_pages` မှာ ရှာ → **လတ်ဆတ်ရင် ပြန်သုံး** (ဥပမာ ၃၀ ရက်)၊ မဟုတ်ရင် scrape → သိမ်း → chunk → embed
- Source ရှာတဲ့အခါ: LLM search အပြင် `web_chunks` ကို vector နဲ့ပါ ရှာ (user နည်းတုန်း ဘာမှ မထွက်လည်း ရ)
- Writer ဆီ: ရွေးထားတဲ့ source တွေထဲက paragraph အလိုက် ဆိုင်တဲ့ chunk (အကျဉ်းချုပ်ပြင် ထပ်ပေါင်း)
- **Copyright ကာကွယ်ချက်:** user ကို excerpt တိုတိုပဲ ပြ၊ robots.txt / noindex ကို လေးစား၊ `blocked_sources` (domain / URL) နဲ့ ဖယ်ခိုင်းရင် ဖယ်
- **Lawyer နဲ့ တစ်ချက်စစ်** (public page စာအပြည့်ကို ကြာကြာသိမ်းတာ)

```
web_pages      (id, url UNIQUE, domain, title, author, published, content_hash, status, fetched_at)
web_chunks     (id, page_id, idx, text, embedding vector(N), model)
blocked_sources(pattern, reason, created_at)
```

## အဆင့် 4 — Quality signal (user များလေ ကောင်းလေ)

- **`source_events`** (user_id NULL ဖြစ်နိုင်၊ page_id, project_id, kind, at): `offered` · `kept` · `excluded` · `cited` (essay ပြီးတဲ့အထိ) · `scrape_failed` · `paywalled`
- **`source_signals`** (page / domain အလိုက် စုစုပေါင်း): ranking score
- **သတိထားရမှာ:**
  - **Diversity:** ကြိုက်များတဲ့ source ချည်းပဲ မပေးဘဲ source အသစ်ကို အမြဲ ရောပေး (essay တွေ ဆင်တူမလာစေဖို့)
  - **Freshness:** ဟောင်းရင် ပြန် scrape၊ ပျောက်ရင် ဖယ်
  - **Manipulation:** user တစ်ယောက်ရဲ့ signal ကို အကန့်အသတ်နဲ့ ချိန် (spam မဖြစ်စေဖို့)

---

## Analytics (ဆုံးဖြတ်ချက် 2)

**အကြံ:** user ရဲ့ content (essay၊ file၊ chat) ကို analytics အတွက် **မစုဘူး**။ လိုတာက **event ရေတွက်တာ** ပဲ၊ အများစုက `run_events` ထဲမှာ ရှိပြီးသား:

- **Funnel:** run စ → မေးခွန်းဖြေ → essay ပြီး → editor ဖွင့် → humanize (ဘယ်အဆင့်မှာ ထွက်သွားလဲ)
- **အရည်အသွေး:** step ကြာချိန်၊ error / interrupted ရာခိုင်နှုန်း၊ ပြန်ပြင်ခိုင်းတဲ့ အကြိမ်
- **စီးပွားရေး:** OctoCredits ကုန်တာ၊ model / personality ဘယ်ဟာ ကြိုက်လဲ၊ Pro ပြောင်းနှုန်း
- Dashboard ကို နောက်မှ (admin ဘက်)

ဒါဆို privacy policy မှာ "content ကို training နဲ့ analytics အတွက် မသုံး" လို့ ရှင်းရှင်း ရေးနိုင်တယ်။

## အသက် (ဆုံးဖြတ်ချက် 6) — legal advice မဟုတ်၊ lawyer နဲ့ အတည်ပြုရန်

- **အနိမ့်ဆုံး:** Terms မှာ **၁၃ နှစ်အထက်** လို့ သတ်မှတ်၊ sign-up မှာ အသက် အတည်ပြုခိုင်း၊ ၁၃ အောက်ကို ပိတ် (US COPPA)
- **EU / UK:** ၁၃–၁၆ ကြား ခွင့်ပြုချက်ဥပဒေ ပိုတင်းတယ်။ Content ကို training / ads အတွက် မသုံးတာက အထောက်အကူ ဖြစ်တယ်
- **Google Play:** target audience ကို "13+" ကြေညာ (ကလေးတွေကို ပစ်မှတ်ထားရင် Families policy လိုက်ရမယ်)
- Data minimization: လိုတာထက် ပိုမစု

---

## အစဉ်

1. **Account ဖျက်တာ** (tombstone + sweeper + app ခလုတ်) ← release မတိုင်ခင် လိုတယ်
2. Knowledge DB + **file upload** (private)
3. Shared **web library**
4. **Quality signal**

Deploy ခါနီး စစ်ရမှာ: Python API က user ကို ဘယ်လိုဖျက်လဲ၊ production မှာ pgvector ရှိလား၊ shared SQL (tombstone trigger) run ဖို့ ခွင့်ပြုချက်။
