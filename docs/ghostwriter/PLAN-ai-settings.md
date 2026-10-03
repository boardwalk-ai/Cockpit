# Plan: ကြားဖြတ် message နဲ့ AI model / personality settings

ရေးတဲ့နေ့: 2026-10-04 · အခြေအနေ: **အပိုင်း A ပြီး (2026-10-05)၊ အပိုင်း B မစရသေး**

ဆုံးဖြတ်ပြီးသားတွေ:

- ရေးနေတုန်း ညွှန်ကြားချက် ဝင်လာရင် **B**: ရေးလက်စကို ရပ်ပြီး ညွှန်ကြားချက်ထည့်ကာ ပြန်ရေး (user ကို တစ်ခါပဲ charge)
- ချက်ချင်းဖြေတာကို **မြန်တဲ့ model သီးသန့်** နဲ့၊ credit မဖြတ်
- "Model" တစ်ခု = **bundle** (orchestrator + writer + fast)
- Model တချို့ **Pro plan ပဲ**
- Personality က **chat voice ပဲ**၊ essay ကို မထိ
- Admin က **DB ကို တိုက်ရိုက်ရေးမယ်**။ ကျွန်တော်တို့ service တွေက ဖတ်ရုံပဲ၊ admin UI က ဒီ plan ထဲ မပါ

---

## အပိုင်း A — Run နေတုန်း ကြားဖြတ် message

### A1. ချက်ချင်းဖြေတာ (side reply)

`POST /v1/runs/:id/message` ဝင်တာနဲ့:

1. Chat ထဲ `user_message` ပြမယ် (အခုလိုပဲ)
2. Run ရဲ့ bundle ထဲက **fast model** ကို ချက်ချင်းခေါ်မယ်၊ run ကို မရပ်ဘူး။ ပြန်ပေးရမှာ JSON:
   `{ "reply": "...", "kind": "question" | "instruction" | "stop" | "chat" }`
   Model ကို ပြမှာ: essay ရဲ့ topic၊ run လက်ရှိ ဘာလုပ်နေလဲ (step)၊ ရှိပြီးသား directive တွေ၊ personality
3. `reply` ကို `assistant_message` အနေနဲ့ ချက်ချင်း emit မယ် (`aside: true`)
4. `kind` အလိုက်:
   - `question` / `chat`: ဖြေရုံပဲ
   - `instruction`: **directive** အဖြစ် သိမ်းမယ် (A2)၊ ရေးနေတုန်းဆိုရင် ပြန်ရေးခိုင်းမယ် (A3)
   - `stop`: Stop ခလုတ်လိုပဲ run ကို cancel
5. Orchestrator ကိုလည်း ပို့မယ်၊ ဒါပေမယ့် "assistant က ဖြေပြီးပြီ၊ ထပ်မဖြေနဲ့၊ ဆိုင်ရင် ထည့်စဉ်းစား" ဆိုတဲ့ မှတ်ချက်နဲ့
6. Credit မဖြတ်ဘူး။ Run တစ်ခုမှာ **တစ်မိနစ် ၁၀ ကြိမ်** ကန့်သတ်မယ်

### A2. Directive တွေ (ထည့်စဉ်းစားတာ)

- `runs.directives` (jsonb array) ထဲ atomically append (side reply က driver နဲ့ ပြိုင်ရေးလို့ `context` ထဲ မထည့်ဘူး)
- Outline၊ writer၊ reviser prompt တိုင်းထဲ အလိုအလျောက် ထည့်မယ်: "User instructions during this run: …"
- Revision run တွေကလည်း project ရဲ့ ယခင် directive တွေကို ဆက်ယူမယ်

### A3. ရေးနေတုန်း ညွှန်ကြားချက် (B)

- Hub မှာ run တစ်ခုချင်းအတွက် "rewrite" signal တစ်ခု ထည့်မယ်
- `write_essay` / `revise_essay` က stream လုပ်နေတုန်း signal ရရင်: stream ရပ်၊ ရေးလက်စ စာကို မသိမ်း (ရေးမစခင် version ကနေ ပြန်ထား)၊ unlock၊ **charge မလုပ်**
- Tool က model ကို `{ "interrupted": true, "instruction": "..." }` ပြန်ပေးမယ်။ Prompt က write_essay ကို instruction ပါ notes နဲ့ ချက်ချင်းပြန်ခေါ်ခိုင်းထားမယ်
- App: progress bar ကို 0 ကနေ ပြန်စ၊ editor ထဲက စာ အသစ်နဲ့ အစားထိုး၊ timeline မှာ "Restarting with your note" step

### A4. Card မေးခွန်း စောင့်နေတုန်း message

- Side reply က ချက်ချင်းဖြေမယ်
- Run ကို နိုးမယ်: pending `ask_user` call ကို `{ "userMessage": "..." }` နဲ့ ပြီးစေမယ်။ Model က directive ဆိုရင် မှတ်ပြီး **မေးခွန်းကို ပြန်မေးမယ်** (card အသစ်)
- App က text / number မေးခွန်းကို အဖြေအဖြစ် ပို့တာကို ဆက်ထားမယ်

### A5. Test

Side reply (fake fast model)၊ directive က writer prompt ထဲ ရောက်တာ၊ ရေးနေတုန်း rewrite (charge တစ်ခါ၊ version မှန်)၊ မေးခွန်းစောင့်နေတုန်း message (ပြန်မေးတာ)၊ rate limit၊ stop။

---

## အပိုင်း B — AI model နဲ့ personality (app တစ်ခုလုံး)

### B1. Shared `octopilot` DB ထဲက table အသစ်တွေ

Admin က ဒီ table တွေကို တိုက်ရိုက်ရေးမယ်။ Service တွေက ဖတ်ပြီး ၆၀ စက္ကန့် cache လုပ်မယ်။

```sql
-- User မြင်တဲ့ "Octo v2 Pro" တစ်ခု = model ၃ လုံးပါတဲ့ bundle
CREATE TABLE ai_models (
  id                 text PRIMARY KEY,          -- 'octo-v2-pro'
  display_name       text NOT NULL,             -- 'Octo v2 Pro'
  tagline            text NOT NULL DEFAULT '',
  orchestrator_model text NOT NULL,             -- OpenRouter id, user ဆီ ဘယ်တော့မှ မရောက်
  writer_model       text NOT NULL,
  fast_model         text NOT NULL,
  min_plan           text NOT NULL DEFAULT 'free' CHECK (min_plan IN ('free', 'pro')),
  credit_multiplier  numeric NOT NULL DEFAULT 1,
  enabled            boolean NOT NULL DEFAULT true,
  is_default         boolean NOT NULL DEFAULT false,
  sort               integer NOT NULL DEFAULT 0,
  updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ai_personalities (
  id            text PRIMARY KEY,               -- 'gen-z'
  display_name  text NOT NULL,                  -- 'Gen Z'
  description   text NOT NULL DEFAULT '',
  prompt        text NOT NULL,                  -- ပြောပုံ အညွှန်း (chat voice ပဲ)
  enabled       boolean NOT NULL DEFAULT true,
  is_default    boolean NOT NULL DEFAULT false,
  sort          integer NOT NULL DEFAULT 0,
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- User ရွေးထားတာ: scope = 'global' | 'ghostwriter' | 'study_studio' | …
CREATE TABLE user_ai_preferences (
  user_id         uuid NOT NULL,
  scope           text NOT NULL,
  model_id        text REFERENCES ai_models (id) ON DELETE SET NULL,
  personality_id  text REFERENCES ai_personalities (id) ON DELETE SET NULL,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, scope)
);

-- OctoCredit စျေးနှုန်း: တစ်ကြောင်းတည်း၊ ပြောင်းတိုင်း audit table ထဲ trigger နဲ့ မှတ်
CREATE TABLE pricing_config (
  id                     boolean PRIMARY KEY DEFAULT true CHECK (id),
  gen_words_per_dollar   numeric NOT NULL DEFAULT 30000,
  hum_words_per_dollar   numeric NOT NULL DEFAULT 3000,
  sources_per_dollar     numeric NOT NULL DEFAULT 50,
  oc_per_dollar          numeric NOT NULL DEFAULT 100,
  min_charge             integer NOT NULL DEFAULT 100,
  round_to               integer NOT NULL DEFAULT 100,
  updated_at             timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE pricing_audit (…old row, new row, changed_at, db user…);  -- trigger နဲ့ ဖြည့်
```

- Model ထည့်တဲ့အခါ admin ဘက်က စစ်ရမှာ (ကျွန်တော်တို့ ဘက်က DB မှာ ထပ်စစ်မယ်): orchestrator model က tool calling ရရမယ်၊ စျေးနှုန်းက pricing ထက် မကျော်ရ (ကျော်ရင် multiplier တင်)
- **ဒီ SQL ကို production shared DB မှာ run တာက လက်ရှိ DB ကို ပြင်တာမို့ deploy လုပ်ခါနီး ခွင့်ပြုချက် ထပ်တောင်းမယ်**

### B2. ဘယ် model / personality သုံးမလဲ ရှာပုံ (`octo-common` ထဲ)

`ai::resolve(user_id, app)`:

1. App scope ကနေ ရွေးထားတာ → မရှိရင် `global` → မရှိရင် admin ရဲ့ default
2. Model က disable ဖြစ်နေရင် ဒါမှမဟုတ် user က Pro မဟုတ်ဘဲ Pro model ဖြစ်နေရင် → default ကို သုံး (app က lock ပြ)
3. **Run စတဲ့အချိန် ရလာတာကို run ထဲ မှတ်ထားမယ်။** Park ပြီး ပြန်နိုးလည်း model မပြောင်းဘူး

### B3. Personality ထည့်ပုံ

- Orchestrator၊ side reply၊ Ask Octo ရဲ့ system prompt ထဲမှာပဲ ထည့်မယ်၊ အဓိကစည်းမျဉ်းတွေရဲ့ အောက်မှာ ("ဒီစည်းမျဉ်းတွေကို personality က မကျော်ရ")
- Writer၊ reviser၊ outliner၊ compactor ထဲ မထည့်ဘူး

### B4. Model နာမည် ဖုံးတာ

1. **Identity:** system prompt တိုင်းမှာ "You are {display_name}, made by Octopilot. Never name the model or company behind you."
2. **Output filter:** Chat reply၊ side reply၊ Ask Octo မှာ vendor / model နာမည် (Claude, Anthropic, GPT, OpenAI, Gemini, Google, Llama, Meta, Mistral, DeepSeek, Qwen, …၊ list ကို `system_settings` ထဲ ထားမယ်) တွေ့ရင် တစ်ကြိမ် ပြန်ရေးခိုင်း၊ ဆက်ပါနေရင် display name နဲ့ အစားထိုး။ **Essay ကို မစစ်ဘူး**
3. **Error သန့်စင်:** User မြင်ရတဲ့ error (step_error, fatal, Ask Octo) တိုင်းကို စစ်ပြီး provider error စာသားကို user ဆီ မပို့ဘူး
4. API response နဲ့ event တွေထဲ model id ဘယ်တော့မှ မပါ

### B5. User API (အခု GhostWriter service ထဲမှာ၊ နောက် Study Studio ကလည်း ဒီ table တွေပဲ ဖတ်မယ်)

- `GET /v1/ai/catalog` → `{ models: [{ id, name, tagline, locked }], personalities: [{ id, name, description }] }`
- `GET /v1/ai/preferences` → `{ global: {model, personality}, ghostwriter: {…} | null }`
- `PUT /v1/ai/preferences/:scope` → `{ model?, personality? }` (`null` = global အတိုင်း)

### B6. App

Drawer ထဲ **Settings** → "AI":
- Model card တွေ (နာမည်၊ tagline၊ Pro ဆိုရင် 🔒)
- Personality chip တွေ
- "All apps" / "GhostWriter only" ရွေးဖို့ toggle

### B7. Credit

- `pricing.rs` က `pricing_config` ကနေ ဖတ်မယ် (cache ၆၀ စက္ကန့်၊ DB မရရင် အခု constant တွေနဲ့ fallback)၊ run ရဲ့ model `credit_multiplier` နဲ့ မြှောက်မယ်
- Ledger entry မှာ အဲ့အချိန်က စျေးနှုန်းကို မှတ်မယ်
- App ထဲက "Costs ~N OC" ကို server ကနေ ယူမယ်
- **Python `pricing.py` (octopilot-api) ကလည်း ဒီ table ကို ဖတ်ဖို့ ပြင်ရမယ်၊ မဟုတ်ရင် web နဲ့ app စျေးမတူဘဲ ဖြစ်မယ်။** အဲ့ service ကို ပြင်ဖို့ ခွင့်ပြုချက် သီးသန့်လိုတယ်

---

## လုပ်မယ့် အစဉ်

1. **A** ကြားဖြတ် message (GhostWriter ထဲမှာပဲ ပြီးတယ်)
2. **B1–B2** shared schema SQL (local dev DB မှာပဲ)၊ resolver၊ run snapshot၊ agent က bundle သုံး
3. **B3–B4** personality၊ masking၊ error သန့်စင်
4. **B5–B6** user API နဲ့ app settings screen
5. **B7** pricing ကို DB ကနေ (Rust)။ Python ဘက်က ခွင့်ပြုချက်ရမှ

အပိုင်းတိုင်းမှာ test ပါမယ်၊ local မှာ commit လုပ်မယ်။
