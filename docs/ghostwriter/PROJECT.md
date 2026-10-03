# GhostWriter Mobile — Project အခြေအနေ၊ Vision နဲ့ ဆုံးဖြတ်ချက်များ

နောက်ဆုံးပြင်ဆင်ချိန်: 2026-10-03

ဒီစာရွက်က GhostWriter mobile project အကြောင်း ဆွေးနွေးခဲ့သမျှ၊ ဆုံးဖြတ်ခဲ့သမျှ၊
ပြီးသွားတာ၊ ကျန်တာနဲ့ ဖိုင်တွေ ဘယ်မှာရှိလဲဆိုတာကို တစ်နေရာတည်းမှာ စုထားတာပါ။
API နဲ့ database အသေးစိတ်က [CONTRACT.md](CONTRACT.md) မှာ ရှိတယ်။

> ဒီ repo က public ဖြစ်လို့ password၊ key၊ server IP တွေကို ဒီစာရွက်ထဲ မထည့်ထားဘူး။
> Server အချက်အလက်က `H:\OctopilotWeb\VPS.md` (local only) မှာ ရှိတယ်။

---

## 1. တစ်ချက်ကြည့်ရုံနဲ့

| | |
|---|---|
| **ဘာဆောက်နေလဲ** | GhostWriter (AI essay ရေးပေးတဲ့ agent) ကို mobile app အဖြစ် ထုတ်ဖို့ |
| **ပထမ release** | GhostWriter တစ်ခုတည်း။ ပြီးရင် Study Studio၊ နောက်မှ OctoNotes |
| **Code နေရာ** | `H:\Cockpit-ghostwriter` (Cockpit monorepo၊ branch `feat/ghostwriter`) |
| **Backend** | Rust (`ghostwriter-api`)၊ Phase 1a–1d + revision (4a) + source review (4b) + humanizer (4c) + source evaluate / critique / Ask Octo (4d) + push (5a) + worker / resume (5b) ပြီး၊ test ၈၅ ခု pass |
| **Mobile UI** | Phone UI တစ်ခုလုံး Rust API နဲ့ ချိတ်ပြီး၊ Google sign-in (Phase 2)၊ ပြင်လို့ရတဲ့ mobile editor (Phase 3)။ Desktop UI (2c) နောက်မှ။ Test ၄၆ ခု pass |
| **အခု ပိတ်နေတာ** | Branch ကို GitHub မတင်ရသေးဘူး (git history ထဲမှာ DB password ပါနေလို့၊ အပိုင်း 8) |

---

## 2. Vision

### 2.1 Product

- Company က mobile app တစ်ခု ထုတ်မယ်။ App ထဲမှာ feature တွေက **module** အဖြစ် ရှိမယ်။
- **ပထမ release = GhostWriter**။ Study Studio က web ပဲ ရှိသေးပြီး backend ကို Rust နဲ့ ပြန်မရေးရသေးလို့
  GhostWriter ပြီးမှ သွားမယ်။ OctoNotes က web တောင် မပြီးသေးလို့ နောက်ဆုံးမှ။
- Feature အသစ်ကြီးတွေက အခုမှ development မှာ ရှိသေးတာမို့ လက်ရှိ app ကို အရင် release လုပ်ချင်တယ်။
- Backend အားလုံးကို company က Rust ကို ပြောင်းနေတယ်။ GhostWriter backend လည်း Rust အသစ်။

### 2.2 GhostWriter သုံးတဲ့အခါ ဖြစ်ရမယ့်ပုံ

1. User က landing မှာ brief ရိုက်ပြီး Start နှိပ်တယ်။
2. Agent က **တစ်ဆင့်ချင်း** လုပ်တယ်၊ လိုတာကို **မေးခွန်းမေး**တယ် (OctopilotWeb ရဲ့ agent loop အတိုင်း):
   plan → focus မေးခွန်း → outline → source ရှာ / ဖတ် / အနှစ်ချုပ် → word count → citation style →
   essay ရေး → title page အချက်အလက် → ပြီး။
3. Chat ထဲမှာ step တစ်ခုစီက card အဖြစ် ပေါ်တယ်။ မေးခွန်းတွေက chip / checkbox / text field နဲ့။
4. **Source step ပြီးရင်** ညာဘက်အပေါ်ထောင့်မှာ **Sources pill** (globe icon) ပေါ်တယ်။
5. **Agent စရေးရင်** အဲ့ဒီအောက်မှာ **Open Editor pill** က fade in နဲ့ ပေါ်တယ်။
6. Chat ထဲမှာ essay စာသား **မပြဘူး**။ `320 / 800 words` ဆိုတဲ့ animated progress bar လေးပဲ ပြတယ်။
   စာလုံးရေကို backend က ရေတွက်ပေးတယ်။ Target ကျော်လည်း ရတယ်။
7. Open Editor နှိပ်ရင် mobile editor ပွင့်တယ်။ Agent ရေးနေတုန်းဆို **read-only**၊ စာလုံးအလိုက် ပေါ်လာတယ်။
8. ပြီးသွားရင် editor က ပြင်လို့ရတယ်။ "Proceed to Editor" card ကလည်း chat ထဲမှာ ထပ်ပြတယ်။
9. User က "စာပိုဒ် ၃ ကို ပြင်ပေး" လို့ ခိုင်းရင် AI က essay တစ်ပုဒ်လုံး ပြန်ဖတ်ပြီး ပြင်တယ်။

### 2.3 Headless editor

- Document က **server မှာ** နေတယ်။ Agent ရော user ရော အဲ့ဒီ document တစ်ခုတည်းကို ရေးတယ်။
- Editor screen က user နှိပ်မှ ပေါ်တယ်။ မပေါ်ခင်လည်း agent က နောက်ကွယ်မှာ ရေးနေတယ်။
- Editor code က Doc Oct ရဲ့ editor ကို ယူသုံးမယ် (code တစ်နေရာတည်း)။ **Data ကတော့ Doc Oct နဲ့ လုံးဝ မချိတ်ဘူး။**

### 2.4 Design

- **ChatGPT လို clean, compact**၊ **Awwwards အဆင့် animation heavy**။
- Background `#222323` + အနီ fade + ရွေ့နေတဲ့ halftone dot (ထိရင် တုံ့ပြန်တယ်)။
- Font: Primary = Plus Jakarta Sans၊ Secondary = Poppins။
- Logo = `Ghost.png` (octopus + ghost line art)။
- ခလုတ်တိုင်းမှာ haptic။ Credits ကို **OctoCredits** လို့ ခေါ်တယ်။
- User တွေကို အတွေ့အကြုံမရှိသူလို့ ယူဆပြီး ဒီဇိုင်းဆွဲမယ် (ဥပမာ editor ကို pill ရော card ရော နှစ်ခါပြ)။

### 2.5 နောက်ပိုင်း

- Push notification (agent က မေးခွန်းမေးရင်)။
- iOS Live Activities / Android ongoing notification နဲ့ progress ပြတာ (user ခွင့်ပြုရင်)။
- Admin ဘက်ကနေ system တစ်ခုလုံးကို ထိန်းတာ (version စစ်၊ maintenance၊ module ဖွင့်ပိတ်)။

---

## 3. ဆုံးဖြတ်ချက်များ

### 3.1 ဖွဲ့စည်းပုံ

| ခေါင်းစဉ် | ဆုံးဖြတ်ချက် | အကြောင်းရင်း |
|---|---|---|
| Repo | Cockpit monorepo ထဲမှာ ဆောက်မယ် | Editor (`doc_oct`)၊ login၊ Rust common code ကို တိုက်ရိုက်သုံးလို့ရ၊ Study Studio နဲ့ ပေါင်းရလွယ် |
| App ပုံစံ | App shell + module တွေ (`cockpit_module`) | Feature တစ်ခုချင်း ဖွင့်ပိတ်လို့ရ |
| Module ဖွင့်ပိတ် | မပြီးသေးတာ = **build flag** (app ထဲ မပါ)၊ ပြီးပြီးသား = **server flag** | Store review မှာ မပြီးသေးတဲ့ code မပါ၊ ပြီးသားကို update မတင်ဘဲ ပိတ်လို့ရ |
| Backend ဘာသာစကား | Rust (axum + sqlx + tokio) | Company က Rust ကို ပြောင်းနေ |
| Backend နေရာ | `backend-rs` workspace ထဲက crate | `octo-common` (auth, credits) ကို copy မကူးဘဲ မျှသုံး |
| Go + Python backend (PR #17/18) | **မသုံးတော့ဘူး** | Rust နဲ့ အစားထိုး |

### 3.2 Data

| ခေါင်းစဉ် | ဆုံးဖြတ်ချက် |
|---|---|
| Database | **Postgres တစ်ခုတည်း**၊ `ghostwriter` ဆိုတဲ့ database သီးသန့်။ Scylla မသုံးသေးဘူး (server တစ်လုံးတည်းမှာ အကျိုးမရှိ) |
| ဗဟို data | Users၊ OctoCredits၊ API key၊ model setting က ရှိပြီးသား `octopilot` DB ကနေ |
| "Mobile DB" | မခွဲဘူး။ ခွဲတာက **feature အလိုက်**၊ mobile / web အလိုက် မဟုတ် |
| Doc Oct နဲ့ | **Data လုံးဝ မချိတ်ဘူး**။ Editor code ပဲ ယူသုံးတယ် |
| Saving | Doc Oct ရဲ့ နည်းအတိုင်း: client က ID ကြိုရွေး၊ idempotent upsert၊ autosave |
| `run_events` table | သီးသန့်ခွဲထားတယ်၊ user အများကြီးဖြစ်လာရင် တခြား store ကို ရွှေ့လို့ရအောင် |

### 3.3 Agent နဲ့ document

| ခေါင်းစဉ် | ဆုံးဖြတ်ချက် |
|---|---|
| Agent loop | OctopilotWeb ရဲ့ loop ကို port (AI က tool ကို ကိုယ်တိုင်ရွေးခေါ်) |
| Document ရေးတာ | Backend မှာ၊ agent က ရေးတယ် |
| ရေးနေချိန် | Document ကို **lock**၊ editor က read-only။ Backend ကပါ ထိန်းတယ် |
| Agent မပြင်ခင် | **Version တစ်ခု အမြဲသိမ်း** (undo လုပ်လို့ရအောင်) |
| ပြင်ခိုင်းတာ | အခု: AI က တစ်ပုဒ်လုံး ပြန်ဖတ်ပြီး ပြင်။ နောက်မှ: စာပိုဒ်အလိုက် တိတိကျကျ |
| Format | Document က အဓိပ္ပါယ်ရှိတဲ့ field တွေ သိမ်းတယ်၊ Doc Oct ရဲ့ formatter တွေက စီပေးတယ် |
| စာလုံးအလိုက် stream | Editor ဖွင့်ထားတဲ့ client ကိုပဲ ပို့။ DB ထဲကို စာပိုဒ်ပြီးတိုင်း / ၂ စက္ကန့်တစ်ခါ save |
| Run | App ပိတ်လည်း ဆက်ပြေး။ Event တွေကို DB မှာ သိမ်း၊ ပြန်ချိတ်ရင် လွတ်တာ မရှိ |

### 3.4 Mobile UI

| ခေါင်းစဉ် | ဆုံးဖြတ်ချက် |
|---|---|
| Chat ထဲမှာ | Essay စာသား မပြ၊ word-count progress bar ပဲ |
| Pill တွေ | ညာအပေါ်ထောင့်: Sources (source ပြီးရင်)၊ Open Editor (စရေးရင်၊ fade in) |
| "Proceed to Editor" card | ဆက်ထား (pill ရှိလည်း ထပ်ပြ) |
| Mobile editor | **Toolbar + editor ပဲ**။ Doc Oct လို panel မပါ။ စာသားကို အပေါ်အောက် စီးပြ (စာမျက်နှာပုံစံ မဟုတ်) |
| `isMobilePlatform` | Android / iOS မှာ true။ Desktop မှာ စမ်းဖို့ `--dart-define=FORCE_MOBILE=true` |
| Chat design | **Cardless** (ChatGPT လို)။ Card ဆိုလို့ ဖြေဖို့စောင့်နေတဲ့ မေးခွန်း box တစ်ခုပဲ။ ဖြေပြီးရင် ရိုးရိုးစာ |
| Editor page | **နောက်ခံ အဖြူ** (စာရွက်လို) |
| Background | `#222323` + မီးခိုးရောင် dot။ **အနီ မသုံး**။ Dot တွေက hover (ဖုန်းမှာ လက်ဆွဲ) နဲ့ တုံ့ပြန်၊ click နဲ့ မဟုတ် |
| Sign-in | Google ပဲ။ Android / iOS မှာ native account picker၊ web မှာ popup။ Firebase session က app တစ်ခုလုံး မျှသုံး (study_studio ရဲ့ `AuthService`) |
| App ID | **`com.boardwalklabs.octopilot`** (Android + iOS)။ Firebase မှာ ဒီ ID နဲ့ register ပြီး |

### 3.5 Release နဲ့ update

| ခေါင်းစဉ် | ဆုံးဖြတ်ချက် |
|---|---|
| ပထမ release ထဲ မဖြစ်မနေပါရမယ့်ဟာ | App ဖွင့်တိုင်း version / maintenance စစ်တာ (မပါရင် နောက်မှ force update မလုပ်နိုင်) |
| Feature အသစ် | App ထဲ ပိတ်ထားပြီး ထည့်ပို့၊ flag နဲ့ ဖွင့် |
| Notification | Push + Live Activities ကို နောက်ဆုံး phase မှာ |

### 3.6 မဆုံးဖြတ်ရသေးတာ

- **Push ပြဿနာ** ကို ဘယ်လိုရှင်းမလဲ (အပိုင်း 8)။
- **OctoCredits ဝယ်တာ:** Store တွေက app ထဲမှာ Stripe နဲ့ digital ပစ္စည်းရောင်းခွင့် မပေးဘူး။
  In-app purchase သုံးမလား၊ app ထဲမှာ မရောင်းဘဲ ထားမလား။
- **Shorebird** (store မဖြတ်ဘဲ Dart code patch) သုံးမလား။ သုံးရင် ပထမ release ထဲ ထည့်မှရတယ်။
- **Platform:** Android အရင်လား၊ iOS ပါ တစ်ပြိုင်တည်းလား။ **App နာမည်** (အခု launcher နဲ့ Google picker မှာ "cockpit" လို့ ပေါ်နေ)။
- **API ရဲ့ public URL** (ဘယ် domain / path)။
- `H:\GhostWriter` (`ghostwriter-mobile` repo) ကို ဖျက်မလား၊ archive လုပ်မလား။

---

## 4. Project တွေရဲ့ နေရာ

### 4.1 Local folder တွေ

| Folder | ဘာလဲ | Branch | အခြေအနေ |
|---|---|---|---|
| **`H:\Cockpit-ghostwriter`** | **အဓိက အလုပ်လုပ်တဲ့နေရာ** | `feat/ghostwriter` | Local only, push မလုပ်ရသေး |
| `H:\Cockpit` | Cockpit ရဲ့ မူရင်း checkout (Doc Oct အလုပ်) | `feat/doc-oct-ui` | GitHub တင်ပြီး (`de63ab7`) |
| `H:\Cockpit-octonotes` | OctoNotes backend + Rust workspace မူရင်း | `feat/octonotes-backend` | Local only (password history ပါ) |
| `H:\Cockpit-backend-rs` | Rust backend အစောပိုင်း | `feat/backend-rust` | မထိထား |
| `H:\Cockpit-pr18` | PR #18 ကို ကြည့်ဖို့ ဆွဲထားတာ | `pr-18` | မလိုတော့ဘူး |
| `H:\GhostWriter` | အစောပိုင်း standalone copy | `feature/mobile-ui` | **Stale**၊ မသုံးတော့ဘူး |
| `H:\OctopilotWeb` | Web app (agent loop မူရင်း TypeScript) | `main` | ဖတ်ရုံပဲ |
| `H:\OctopilotWeb\Mobile` | အစဆုံး copy တွေ (PR-16/17/18 စသည်) | — | မလိုတော့ဘူး |

`feat/ghostwriter` = `feat/octonotes-backend` (Rust workspace) + `feat/doc-oct-ui` (Doc Oct editor) ကို ပေါင်းထားတာ။

### 4.2 `H:\Cockpit-ghostwriter` အထဲမှာ

```
backend-rs/
  crates/
    octo-common/              auth, credits, identity, OpenRouter client (service အားလုံး မျှသုံး)
    ghostwriter-api/          ★ GhostWriter backend
      src/
        main.rs  lib.rs  config.rs  ctx.rs
        routes/               system.rs  projects.rs  folders.rs  runs.rs  documents.rs
        runs/                 mod.rs (event log + live fan-out)   driver.rs (RunCtx + scripted driver)
        agent/                mod.rs (loop)  prompt.rs  context.rs  tools.rs
        llm.rs  scrape.rs  pricing.rs  documents.rs  live_docs.rs (editor stream)
      migrations/             20261002000001_core.sql
      tests/                  phase1a_projects.rs  phase1b_runs.rs  phase1c_agent.rs  phase1d_documents.rs  common/
      .env.example
    octopilot-rs/             Doc Oct backend (ကျွန်တော်တို့ မထိ)
    octonotes-api/            OctoNotes backend (ကျွန်တော်တို့ မထိ)
packages/
  ghostwriter/                ★ GhostWriter mobile UI (Flutter module)
    lib/ghostwriter.dart
    lib/src/
      ghostwriter_module.dart   ghostwriter_root.dart (phone / desktop / sign-in ရွေး)   platform.dart
      gw_auth.dart              (host app က ပေးတဲ့ sign-in interface)
      ghostwriter_page.dart     (desktop page အဟောင်း၊ 2c မှာ session ပေါ် ပြောင်းမယ်)
      ghostwriter_api.dart      (Go backend အဟောင်း — desktop page ပဲ သုံးနေ၊ 2c မှာ ဖျက်မယ်)
      data/  gw_api.dart (Rust API client)  sse.dart  ids.dart
      session/  gw_session.dart (controller)  timeline.dart (event → timeline)  doc_session.dart (editor ရဲ့ document)
      demo/demo_run.dart        (GW_DEMO sample essay)
      mobile/                   mobile_app (phone shell)  mobile_landing  mobile_top_bar  mobile_drawer
                                mobile_composer  mobile_chat  mobile_cards (step / မေးခွန်း / progress)
                                mobile_pills  mobile_editor (editor အဖြူ + toolbar + History)  mobile_sign_in
                                mobile_details_sheet  mobile_background  mobile_motion  mobile_theme
    assets/                   ghost.png, Poppins fonts
    test/                     test ၆၄ ခု (fake_server.dart နဲ့ API ကို အတု)
  doc_oct/                    Doc Oct (editor ကို ဒီကနေ ယူမယ်)
  cockpit_ui/ cockpit_core/ cockpit_module/ study_studio/ octo_notes/
apps/cockpit/
  lib/main_ghostwriter.dart   ★ GhostWriter တစ်ခုတည်းပါတဲ့ entry point (release app)
  lib/modules/module_auth.dart   app ရဲ့ Firebase sign-in ကို module တွေဆီ မျှပေး (GhostWriter ပါ)
  android/app/google-services.json, ios/Runner/GoogleService-Info.plist   (git ထဲ မပါ)
  lib/modules/registered_modules.dart   module စာရင်း + build flag
docs/ghostwriter/
  CONTRACT.md                 API + DB + event အသေးစိတ်
  PROJECT.md                  ဒီစာရွက်
```

### 4.3 GitHub

| Repo | အသုံး |
|---|---|
| `boardwalk-ai/Cockpit` (public) | အဓိက။ `feat/doc-oct-ui` တင်ပြီး၊ `feat/ghostwriter` မတင်ရသေး |
| `boardwalk-ai/ghostwriter-mobile` (public) | အစောပိုင်း copy။ `main`, `dev`, `feature/mobile-ui`။ Stale |

### 4.4 Server (VPS)

- ဝင်နည်း: `ssh octopilot-vps` (key = `~/.ssh/octopilot_vps`၊ 2026-10-02 မှာ install လုပ်ထား)။
- ခွင့်ပြုထားတာ: ဖတ်တာနဲ့ GhostWriter service **အသစ်** deploy လုပ်တာ။ ရှိပြီးသား service တွေကို မထိရ။
- Rust service တွေ run နေပုံ: `/opt/<name>` အောက်မှာ binary၊ systemd unit၊ ကိုယ်ပိုင် user၊ ကိုယ်ပိုင် Postgres container။
- လွတ်နေတဲ့ port: **8791** (GhostWriter အတွက်)။
- Model setting တွေ (`ghostwriter_orchestrator_model`, `ghostwriter_write_model` စသည်) က `system_settings` ထဲမှာ ရှိပြီးသား။
- GhostWriter ကို server ပေါ် **မတင်ရသေးဘူး**။

### 4.5 Local dev database

- Local Postgres 17 (Windows service) က `127.0.0.1:5432` မှာ run နေတယ်။
- `ghostwriter`: dev database။
- `octopilot_dev`: users / credits stand-in။ OpenRouter key တစ်ခုနဲ့ model နာမည်တွေ server ကနေ ကူးထားတယ်။
- Test တွေက `ghostwriter_test_<id>` ဆိုတဲ့ database ကို ဆောက်ပြီး ပြီးရင် ဖျက်တယ်။

---

## 5. Architecture

```
Mobile app (Flutter)
  packages/ghostwriter  ──HTTP + SSE──►  ghostwriter-api (Rust, :8791)
                                            │
                                            ├─► ghostwriter DB      projects, documents, versions, runs, run_events
                                            ├─► octopilot DB        users, OctoCredits, api_keys, system_settings
                                            ├─► OpenRouter          orchestrator / writer / secondary / search model
                                            └─► Scraper service     source စာသား ယူတာ
```

### Database (`ghostwriter`)

| Table | ဘာသိမ်းလဲ |
|---|---|
| `projects` | Essay တစ်ပုဒ်စီ: title၊ brief၊ status၊ target / word count |
| `folders` | Sidebar က folder တွေ |
| `documents` | Project တစ်ခုစီရဲ့ document: body၊ bibliography၊ style၊ fields၊ sources၊ `rev`၊ `locked_by_run` |
| `document_versions` | Agent မပြင်ခင် / user save တိုင်း snapshot |
| `runs` | Agent run တစ်ခုစီ: status၊ context၊ conversation၊ pending question |
| `run_events` | Event log (`run_id`, `seq`) |

### Event တွေ (app က timeline ဆောက်ဖို့)

`user_message` · `assistant_message` · `assistant_delta` (live only) · `step_start` · `step_progress` ·
`step_done` · `step_error` · `question` · `question_answered` · `awaiting_reply` · `context_update` ·
`sources_ready` · `writing_started` · `write_progress` · `document_updated` · `credits` ·
`done` · `fatal` · `cancelled`

### Agent ရဲ့ tool ၈ ခု

`plan_essay` · `ask_user` · `generate_outlines` · `search_sources` · `scrape_sources` ·
`compact_sources` · `write_essay` · `finalize_document`

### OctoCredits ဈေးနှုန်း

100 OC = $1။ စာလုံး ၃၀,၀၀၀ ရေးတာ၊ စာလုံး ၃,၀၀၀ humanize၊ source ၅၀ တစ်ခုစီ = $1။
Operation တစ်ခုကို 100 ပြည့်အောင် တိုးပြီး အနည်းဆုံး 100 OC ဖြတ်တယ်။ (Server ရဲ့ `pricing.py` အတိုင်း။)

---

## 6. ပြီးသွားတာ

### 6.1 Backend (`ghostwriter-api`)

| Phase | ဘာပါလဲ | Commit | Test |
|---|---|---|---|
| **1a** | Service အခြေခံ၊ migration၊ auth၊ `/v1/me`၊ projects၊ folders | `0450395` | 13 |
| **1b** | Run စတာ၊ DB မှာသိမ်းတဲ့ event log၊ ပြန်ချိတ်လို့ရတဲ့ SSE stream၊ answer၊ message၊ cancel၊ restart ပြီးရင် ပြန်ရှင်းတာ | `e6e9fc6` | 12 |
| **1c** | Agent loop၊ tool ၈ ခု၊ document lock / version / progress၊ OctoCredits၊ `GET document` | `323b216` | 12 + unit 5 |
| **1d** | Editor က save (`baseRev` စစ်၊ retry လုပ်လည်း ရ)၊ editor stream (စာလုံးအလိုက်၊ ရေးနေတုန်း ဖွင့်လည်း မလွတ်)၊ version စာရင်း + restore၊ scripted driver က document ထဲ စာတကယ်ရေး | `39f3058` | 8 + unit 3 |
| **4a** | Revision: essay ရေးပြီးသား project ပေါ် run အသစ် = ပြင်ခိုင်းတာ / မေးတာ၊ `revise_essay` tool၊ `runIds` | 4a + 4b commit | 3 |
| **4b** | Source review: ဖတ်ထားတဲ့ source တွေကို user က ဖယ် / focus note ရေး၊ ဖယ်ထားတာကို အနှစ်မချုပ် | 4a + 4b commit | 1 (+ app 7) |

- **Test ၈၅ ခုလုံး pass**၊ clippy သန့်တယ်။ Timing ပေါ်မူတည်တဲ့ test တွေကို ၁၀ ကြိမ် ထပ် run ပြီး တည်ငြိမ်တာ စစ်ထားတယ်။
- **AI အစစ်နဲ့ တစ်ကြိမ် စမ်းထားတယ်** (2026-10-02): ၁၀၉ စက္ကန့်အတွင်း source အစစ် ၄ ခု (IPCC, NASA, Miami-Dade, UN)
  နဲ့ APA citation ပါတဲ့ စာလုံး ၄၅၁ လုံး essay၊ title page field ၅ ခု၊ 200 OC ဖြတ်။

### 6.2 Mobile UI (`packages/ghostwriter`)

Phase 2 (2a, 2b, 2d) ပြီး (`28996aa`၊ backend `lastRunId` = `7fccc54`)။ Test ၃၅ ခု pass (session / SSE / timeline / chat / drawer / sign-in)။
Browser မှာ scripted backend နဲ့ အစအဆုံး စမ်းပြီး၊ Android emulator မှာ sign-in screen နဲ့ Google account picker ပေါ်တာ စမ်းပြီး။

| Screen | အခြေအနေ |
|---|---|
| **Landing** | ပြီး: ghost artwork (ပေါ်လော)၊ စကားလုံးအလိုက် greeting၊ suggestion chip၊ entry animation |
| **Header bar** | ပြီး: floating glass capsule၊ logo + wordmark၊ OctoCredits pill (ရေတွက်တက်၊ shine) |
| **Sidebar** | ပြီး: New chat၊ search၊ folders၊ threads (status dot)၊ account + credits၊ stagger animation |
| **Input box** | ပြီး: frosted glass၊ focus လုပ်ရင် လည်နေတဲ့ အနီရောင် border၊ Start ခလုတ် morph |
| **Background** | ပြီး: `#222323` + မီးခိုးရောင် halftone dot (ရွေ့၊ hover / လက်ဆွဲရင် တုံ့ပြန်) |
| **Haptics** | ပြီး: ခလုတ်တိုင်း |
| **Chat screen** | ပြန်ဆောက်ပြီး (2b)၊ cardless (မေးခွန်း box ပဲ card)၊ step / မေးခွန်း / progress bar / pill / viewer |
| **Details sheet** | Sources pill နှိပ်ရင် ပွင့် (sources + essay info) |
| **Editor** | Phase 3: နောက်ခံအဖြူ၊ serif (Doc Oct ရဲ့ Tinos)။ Agent ရေးနေတုန်း read-only + စာသား တိုက်ရိုက်ဆင်း၊ ပြီးရင် ပြင်လို့ရ၊ autosave၊ toolbar (undo / redo / B / I / U / heading / list / quote)၊ title page အချက်အလက်၊ references၊ History (version ပြန်ယူ) |
| **Sign-in** | Ghost + "Continue with Google"။ Drawer မှာ sign out။ Octopilot account မရှိရင် (`account_required`) ပြော |

### 6.3 တခြား

- `doc_oct` ရဲ့ commit မလုပ်ရသေးတာတွေကို commit ပြီး `feat/doc-oct-ui` ကို GitHub တင်ပြီး (`de63ab7`)။
- Cockpit app ထဲ GhostWriter module register လုပ်ပြီး (`GHOSTWRITER_ENABLED` build flag)။
- Release app entry point: `apps/cockpit/lib/main_ghostwriter.dart`။
- Server ကနေ ဈေးနှုန်းဇယား၊ DB schema၊ deploy ပုံစံ ဖတ်ပြီး။

---

## 7. ကျန်တာ

### Phase 1d — Document (backend) ✅
- [x] `PUT /v1/projects/:id/document`: editor က save (lock နဲ့ `baseRev` စစ်)
- [x] `GET /v1/projects/:id/document/stream`: read-only editor အတွက် စာလုံးအလိုက် stream
- [x] Version စာရင်းနဲ့ restore (undo)

### Phase 2 — Mobile chat (app)
- [x] **2a** API client အသစ် (Rust API၊ SSE ပြတ်ရင် `sinceSeq` နဲ့ ပြန်ချိတ်)၊ event → timeline reducer၊ `GwSession` controller (phone ရော desktop ရော မျှသုံးမယ်)
- [x] **2b** Phone chat ကို session ပေါ် ပြန်ဆောက်: step timeline၊ မေးခွန်း ၅ မျိုး၊ word-count bar၊ Sources / Open Editor pill၊ read-only viewer (အဖြူ)၊ sidebar မှာ projects / folders၊ app ပြန်ဖွင့်ရင် ပြန်ချိတ်
- [x] OctoCredits pill ကို `credits` event နဲ့ ချိတ်
- [ ] **2c Desktop UI ကို session ပေါ် ပြောင်း — နောက်မှ လုပ်မယ် (2026-10-03 ဆုံးဖြတ်)**
  - အခု desktop (`ghostwriter_page.dart`၊ ~1,700 ကြောင်း) က **Go API အဟောင်း** (`ghostwriter_api.dart`၊ `:8080`) နဲ့ `GW_DEMO` demo ကိုပဲ သုံးနေတုန်း။ Desktop မှာ ဖွင့်ရင် အလုပ်မလုပ်ဘူး။
  - လုပ်ရမှာ: `GhostWriterRoot` က desktop ကိုလည်း `GwSession` ပေးပြီး page ထဲက `_api` / `_handleAgentEvent` / `_threads` / `_saveCurrentThread` တွေကို session နဲ့ အစားထိုး။ Timeline card တွေ (`mobile_cards.dart`) ကို desktop layout နဲ့ ပြန်သုံးလို့ရ။
  - ပြီးရင် `ghostwriter_api.dart`၊ `demo/demo_run.dart` ကို ဖျက်။
  - Design rule တွေ (cardless၊ မေးခွန်းပဲ card) desktop မှာလည်း လိုက်နာ။
- [x] **2d** Firebase sign-in (Android / iOS / web) + App ID `com.boardwalklabs.octopilot`
  - `GwAuth` interface (ghostwriter) ← Cockpit app က study_studio ရဲ့ `AuthService` ကို ပေး (`module_auth.dart`)
  - Firebase ကို Android / iOS မှာ `google-services.json` / `GoogleService-Info.plist` ကနေ init (git ထဲ မထည့်)။ ဖိုင်မရှိရင် dev user နဲ့ run
  - Android: google-services plugin (ဖိုင်ရှိမှ apply)၊ INTERNET permission (အရင်က မရှိ!)၊ debug မှာပဲ `10.0.2.2` ကို http ခွင့်
  - Android build ပြင်ရတာ: `kotlin.incremental=false` (H: နဲ့ C: drive မတူလို့ cache error)၊ plugin တွေကို compileSdk 36 (file_picker 8 ကြောင့်)
  - iOS: plist ကို Xcode Resources ထဲ ထည့်၊ `REVERSED_CLIENT_ID` URL scheme ထည့်။ **Mac မရှိလို့ build မစမ်းရသေး**

### Phase 3 — Editor ✅ (`ce800f5`)
- [x] Doc Oct နဲ့ code မျှသုံး — **ဆုံးဖြတ်ချက်ပြောင်း (2026-10-03):** doc_oct ကို "core" package အဖြစ် **အခု မခွဲသေးဘူး**။
  Doc Oct ကို `feat/doc-oct-ui` (H:\Cockpit) မှာ တပြိုင်နက် ဆက်ရေးနေလို့ ဖိုင်ရွှေ့ရင် merge conflict ဖြစ်မယ်။
  အစား ghostwriter က `doc_oct` ကို dependency အဖြစ်ယူပြီး **quill foundation၊ field နာမည်တွေ (`DocFieldKind` နဲ့တူ)၊ Tinos font၊
  delta JSON ပုံစံ** တူတူသုံး → GhostWriter essay ကို နောက်မှ Doc Oct မှာ ဖွင့်ရင် ဘာမှ မပျောက်။ Doc Oct ငြိမ်သွားမှ core ခွဲမယ်။
- [x] Mobile editor (`mobile_editor.dart`): toolbar + editor၊ စာမျက်နှာမဟုတ်ဘဲ စီးဆင်းတဲ့စာသား၊ title / title page details / body / references
- [x] `GwDocumentSession` (`session/doc_session.dart`): document stream လိုက်၊ agent စာသားကို quill ထဲ တိုက်ရိုက်ထည့်၊ unlock ရင် ပြင်ခွင့်၊
  autosave (1.2s debounce၊ `baseRev`)၊ တခြားနေရာက ပြင်ထားရင် "Changed elsewhere → Load"၊ app ပိတ်ရင် ချက်ချင်း save
- [x] History sheet: version စာရင်း + restore (agent မရေးခင်၊ ကိုယ်မပြင်ခင်)
- [x] "Proceed to Editor" card နဲ့ Open Editor pill နှစ်ခုလုံး editor ကို ဖွင့်
- [ ] ကျန်: Doc Oct လို style အလိုက် title page layout (APA / MLA …)၊ PDF export (Doc Oct ရဲ့ exporter ကို ပြန်သုံးနိုင်)၊ style ပြောင်းတာ

### Phase 4 — ပြင်ခိုင်းတာနဲ့ ကျန်တဲ့ tool
- [x] **4a Revision mode** (web နဲ့ မတူ: web က run တစ်ခုတည်းကို ဖွင့်ထားတယ်၊ ဒီမှာ ပြင်ခိုင်းတိုင်း **run အသစ်** — restart ကျော်လည်း မပျက်)
  - Essay ရေးပြီးသား project ပေါ် run စရင် revision prompt + tool ၂ ခု (`revise_essay`, `ask_user`)
  - `revise_essay`: document ကို **အခုရှိတဲ့အတိုင်း** (user ပြင်ထားတာပါ) ဖတ်၊ lock ယူ၊ `agent_revise` version သိမ်း၊ essay တစ်ပုဒ်လုံး stream ပြန်ရေး၊ OctoCredits ဖြတ် ("Essay revision")
  - မေးတာပဲဆိုရင် chat မှာ ဖြေပြီး ပြီး (document မထိ)
  - App: essay ပြီးရင် chat box က "Ask for a change to your essay"၊ run တွေ အားလုံးကို conversation တစ်ခုတည်းအဖြစ် ပြ (`runIds` နဲ့ replay)၊ progress bar က "Revising your essay"
  - Scripted driver လည်း revise လုပ်တယ် (အဆုံးမှာ "Revision note" ထည့်)
  - Browser မှာ scripted နဲ့ အစအဆုံး စမ်းပြီး
- [x] **4b Source review** (source တစ်ခုချင်း note / exclude)
  - Source ဖတ်ပြီးရင် agent က "Review Sources" / "One Shot" မေးတယ်
  - Review ရွေးရင် ဖတ်ထားတဲ့ source တွေ မေးခွန်းနဲ့အတူ လာတယ်။ App မှာ source တစ်ခုစီကို ဖယ်လို့ရ၊ "focus note" ရေးလို့ရ
  - ဖယ်ထားတဲ့ source ကို အနှစ်မချုပ်၊ မကိုးကားဘူး။ Note က အဲ့ဒီ source ရဲ့ အနှစ်ချုပ်ကိုပဲ ဦးတည်ပေးတယ်
  - ဖြေပြီးရင် chat မှာ "4 sources kept · 1 left out · 1 with a note" လို့ အကျဉ်းပြတယ်
  - Scripted driver မှာလည်း ပါတယ်။ Browser မှာ scripted နဲ့ စမ်းပြီး (နှိပ်တာတွေကိုတော့ widget test နဲ့ စစ်ထား)
- [x] **4d Source evaluate + critique**
  - `evaluate_sources`: source တွေ အကျဉ်းချုပ်ပြီးတိုင်း essay အတွက် လုံလောက်လား စစ်တယ်။ မလုံလောက်ရင် **တစ်ကြိမ်ပဲ** ထပ်ရှာတယ် (search → scrape → compact)။ စစ်တဲ့ model fail ဖြစ်ရင် run မရပ်ဘူး
  - `critique_essay` (ပြင်ခိုင်းတဲ့ run): "review my essay" / "make it better" ဆို essay ကို စစ်ပြီး အားနည်းချက်တွေကို စာပိုဒ်နံပါတ်နဲ့ ပြောတယ်၊ "Fix them / Leave it" မေးတယ်။ Review က **အခမဲ့**၊ essay ကို မထိဘူး။ User က ပြင်ခိုင်းမှ `revise_essay` (credit ကုန်တာ ဒါပဲ)
  - Web က scrape ပြီးတိုင်း အသုံးမကျတဲ့ page တွေကို အလိုအလျောက် ဖယ်တာ (auto-exclude) ကို **မကူးထားဘူး**
- [x] **4c Humanizer** (StealthGPT / UndetectableAI) + paragraph split
  - Essay ပြီးရင် agent က "StealthGPT / UndetectableAI / Skip" မေးတယ်
  - `humanize_essay`: document ထဲက essay ကို **အခုရှိတဲ့အတိုင်း** (user ပြင်ထားတာပါ) provider ဆီပို့၊ lock ယူ၊ `humanize` version သိမ်း၊ ရလဒ်ကို document ထဲထည့်၊ OctoCredits ဖြတ် ("Humanizing")။ Bibliography ကို မထိဘူး
  - Provider က စာပိုဒ်တွေကို ပေါင်းပစ်ရင် agent က "Restore paragraphs?" မေးပြီး `split_paragraphs` နဲ့ ပြန်ခွဲတယ်။ **စကားလုံးတစ်လုံး ပြောင်းရင် အဲ့ဒီ split ကို ပယ်တယ်**
  - ပြင်ခိုင်းတဲ့ run မှာလည်း "humanize it" လို့ ခိုင်းလို့ရတယ်
  - Provider fail ဖြစ်ရင် / key မရှိရင် essay နဲ့ balance ကို မထိဘူး
  - Scripted driver မှာလည်း ပါတယ် (`SCRIPTED_HUMANIZER=false` နဲ့ ပိတ်လို့ရ)
  - **Provider အစစ်နဲ့ မစမ်းရသေးဘူး** (test တွေက humanizer အတုနဲ့)။ App မှာလည်း မကြည့်ရသေးဘူး၊ မေးခွန်းတွေက ရှိပြီးသား select card ကိုပဲ သုံးတယ်
- [x] **Ask Octo** — header မှာ Octo icon၊ နှိပ်ရင် bottom sheet။ App သုံးပုံအကြောင်း မေးခွန်းတစ်ခု၊ အဖြေတိုတစ်ခု (`POST /v1/octo/ask`)။ Essay အကြောင်း မဖြေဘူး၊ credit မဖြတ်ဘူး၊ မသိမ်းဘူး။ **Rate limit မထည့်ရသေးဘူး** (မေးခွန်း စာလုံး ၅၀၀ ကန့်သတ်ပဲ ရှိ)

### Phase 5 — Notification
- [x] **5a Push notification** (code ပြီး၊ **ဖုန်းအစစ်မှာ မစမ်းရသေး**)
  - Server: `devices` table၊ `PUT/DELETE /v1/devices/:id`၊ FCM HTTP v1 နဲ့ ပို့တယ်
  - ပို့တဲ့အချိန်: agent က မေးခွန်းမေးတဲ့အခါ၊ run ပြီးတဲ့အခါ၊ run fail တဲ့အခါ။ **အဲ့ဒီ run ကို ဘယ် app မှ ကြည့်မနေမှ** ပို့တယ် (event stream ချိတ်ထားသူ မရှိမှ)
  - App: နောက်ကွယ်ရောက်ရင် stream ပိတ်တယ် (server က notify လုပ်ဖို့)၊ ပြန်ဝင်ရင် ဆက်ချိတ်ပြီး လွတ်သွားတာတွေ ပြန်ယူတယ်
  - Permission ကို app ဖွင့်ဖွင့်ချင်း မတောင်းဘူး၊ **ပထမဆုံး run စတဲ့အခါမှ** တောင်းတယ်
  - Notification နှိပ်ရင် အဲ့ဒီ essay ပွင့်တယ်။ Sign out လုပ်ရင် အဲ့ဒီဖုန်းကို ဆက်မပို့တော့ဘူး
  - **လိုသေးတာ (user လုပ်ရမယ်):** Firebase service account key (server မှာ `FCM_SERVICE_ACCOUNT_FILE`)၊ iOS အတွက် APNs key ကို Firebase မှာ upload + Xcode မှာ Push Notifications capability
- [x] **5b Run တွေကို worker / queue အဖြစ် ပြောင်း၊ ရပ်ခဲ့တဲ့ step ကနေ ဆက်တာ**
  - Run စရင် `queued`၊ worker က DB ကနေ ယူပြီး lease နဲ့ ကိုင်ထားတယ်
  - **မေးခွန်းမေးတာနဲ့ ချက်ချင်း park လုပ်တယ်** (`PARK_AFTER_MS=0`၊ 10-04 ဆုံးဖြတ်) (fail မဖြစ်တော့ဘူး၊ memory မသုံးဘူး၊ သက်တမ်း မကုန်ဘူး)။ Past threads ကနေ ဖွင့်ပြီး ဘယ်တော့ဖြေဖြေ **ရပ်ခဲ့တဲ့ step ကနေ ဆက်တယ်**၊ ပြီးသားအဆင့်တွေ ပြန်မလုပ်ဘူး၊ ပိုက်ဆံ ထပ်မဖြတ်ဘူး
  - **Server restart / crash ဖြစ်ရင်** lease ကုန်တာနဲ့ (၃၀ စက္ကန့်) ပြန်ယူပြီး ဆက်လုပ်တယ်။ ကြားဖြတ်ခံရတဲ့ step ကို "Interrupted" ပြပြီး ပြန်လုပ်တယ်
  - Dev server မှာ ရေးနေတုန်း process ကို kill လုပ်ပြီး **တကယ်စမ်းပြီး**: ပြန်တက်လာတော့ essay အပြည့် ဆက်ရေးပြီး ပြီးသွားတယ်
  - **Concurrent:** user တစ်ယောက် essay အများကြီး တစ်ပြိုင်နက် run လို့ရတယ် (project တစ်ခုမှာ run တစ်ခုပဲ)။ မေးခွန်းစောင့်နေတဲ့ run က worker slot ကို ပြန်လွှတ်ပေးတယ်။ Drawer မှာ အဖြေစောင့်နေတဲ့ essay ကို **"Your turn"** လို့ပြတယ်
  - **Stop ခလုတ်** က ChatGPT လို composer ရဲ့ send နေရာမှာ (GhostWriter အလုပ်လုပ်နေပြီး ဘာမှ မရိုက်ထားရင်)။ စာရိုက်ရင် Send ပြန်ဖြစ်တယ် (run ကို လမ်းညွှန်ဖို့)
- [ ] iOS Live Activities၊ Android ongoing notification

### Release မတိုင်ခင်
- [ ] GhostWriter ကို server ပေါ် deploy (DB container၊ systemd၊ nginx၊ public URL)
- [ ] App ဖွင့်တိုင်း version / maintenance စစ်တဲ့ endpoint + screen
- [x] Firebase မှာ Android / iOS app register ပြီး (`com.boardwalklabs.octopilot`)၊ debug SHA-1 ထည့်ပြီး
- [ ] **Release SHA-1** ကို Firebase ထဲ ထည့် (Play Console → App integrity → App signing)
- [ ] OctoCredits ဝယ်တာ ဆုံးဖြတ် (in-app purchase / မရောင်း)
- [ ] App နာမည်၊ icon၊ store listing၊ privacy policy (bundle ID ပြီး)
- [ ] ဖုန်းအစစ်ပေါ်မှာ စမ်း (animation performance၊ haptics)
- [ ] Server နှစ်လုံးသုံးမယ်ဆို live event ကို Redis နဲ့ မျှ

---

## 8. အခု ပိတ်နေတာ: push မလုပ်နိုင်သေးတာ

- `feat/ghostwriter` ထဲမှာ GitHub မတင်ရသေးတဲ့ OctoNotes backend commit ၂၁ ခု ပါတယ်။
- အဲ့ဒီထဲက commit နှစ်ခုရဲ့ **history ထဲမှာ production database password ပါနေတယ်**
  (`bd129df` မှာ ထည့်၊ `beb9f14` မှာ ဖြုတ်)။ လက်ရှိ code ထဲမှာတော့ မရှိတော့ဘူး။
- Cockpit က public repo မို့ ဒီအတိုင်း push လုပ်ရင် password အများမြင်သွားမယ်။ အခုထိ GitHub ပေါ် မရောက်သေးဘူး။

ရွေးစရာ:

1. **History ထဲက password ကို ဖျက်ပြီးမှ push** (အကြံပေး)။ `feat/octonotes-backend` နဲ့ `feat/ghostwriter`
   နှစ်ခုလုံးရဲ့ history ကို ပြန်ရေးရမယ်။ Commit ID တွေ ပြောင်းမယ်။
2. **Server ပေါ်က DB password ကို အရင်ပြောင်း**၊ ပြီးမှ push။ Run နေတဲ့ service အားလုံးရဲ့ config ကို ပြင်ရမယ်။

---

## 9. သိထားရမယ့် အားနည်းချက်တွေ

- **Worker က API process ထဲမှာပဲ run တယ်။** Worker ကို process သီးသန့်ခွဲချင်ရင် answer / message တွေကို DB (LISTEN/NOTIFY) ကနေ ပို့တဲ့အပိုင်း ထပ်လိုမယ်။
- **AI အစစ်နဲ့ တစ်ကြိမ်ပဲ စမ်းထားတယ်။** ခေါင်းစဉ်၊ citation style၊ အရှည် အမျိုးမျိုးနဲ့ မစမ်းရသေး။
- **Web နဲ့ မတူတာ:** writer က JSON မဟုတ်ဘဲ စာသားအတိုင်း ပြန်ပေးတယ် (ရေးနေတုန်း စာလုံးရေတွက်ဖို့)။
- **Source link တချို့ ဖတ်မရဘူး** (၅ ခုမှာ ၁ ခုလောက်)။ Web မှာလည်း အတူတူပဲ။
- **ဖုန်းအစစ်ပေါ်မှာ မစမ်းရသေး။** Browser နဲ့ Android emulator မှာပဲ စမ်းထား။ Emulator (`Small_Phone`) က RAM 2 GB ပဲ ရှိလို့ app ကို Android က မကြာခဏ ပိတ်ပစ်တယ် → 4 GB လောက် တိုးသင့်။
- **Browser mobile emulation မှာ click တစ်ခါက နှစ်ခါ ရောက်တယ်** (စမ်းနေတုန်း project နှစ်ခု မတော်တဆ ဆောက်မိ)။ Start ကို နှစ်ခါ မြန်မြန်နှိပ်ရင် ဘာဖြစ်လဲ ဖုန်းအစစ်မှာ စစ်ရမယ်။
- **Google sign-in ကို account ရွေးတဲ့အထိပဲ စမ်းရသေး** (picker ပေါ်တာ = SHA-1 / client ID မှန်)။ Account ရွေးပြီး backend (Firebase auth ဖွင့်ထား) ထိ အစအဆုံး မစမ်းရသေး။
- **iOS build မစမ်းရသေး** (Mac လို)။
- **`study_studio` test တစ်ခု (`home_page_test: shows studio data`) fail နေတာ** GhostWriter မတိုင်ခင်ကတည်းက (overflow)။
- **`+`၊ Source၊ mic ခလုတ်တွေ** က ဘာမှ မလုပ်သေးဘူး (haptic ပဲ)။
- **Editor က style အလိုက် title page / PDF မထုတ်သေးဘူး** (Doc Oct မှာ ရှိတယ်)။ ဖုန်းမှာ စာသားကို စီးဆင်းပြတာပဲ။
- **Password** က history အပြင် `VPS.md` လို နေရာတွေမှာလည်း ရှိတယ်။ တစ်ချိန်ချိန် ပြောင်းသင့်တယ်။

---

## 10. Run / test နည်း

**Backend test**

```bash
cd H:/Cockpit-ghostwriter/backend-rs
CARGO_TARGET_DIR=/h/Cockpit-ghostwriter/backend-rs/target cargo test -p ghostwriter-api
```

Local Postgres (`postgres://postgres:postgres@127.0.0.1:5432`) run နေရမယ်။

**Backend ကို local မှာ run** (port 8791၊ auth ပိတ်၊ `X-User-Id: dev-user`)

```bash
cd H:/Cockpit-ghostwriter/backend-rs
FIREBASE_PROJECT_ID= BIND=127.0.0.1 PORT=8791 \
OCTOPILOT_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/octopilot_dev \
cargo run -p ghostwriter-api
```

- AI မသုံးဘဲ script နဲ့ run ချင်ရင် `GHOSTWRITER_DRIVER=scripted` ထည့်။
- AI အစစ်နဲ့ run ရင် OpenRouter ခနဲ့ dev OC 200 ကုန်တယ်။

**Mobile app (browser မှာ phone UI နဲ့)** — backend (`GHOSTWRITER_DRIVER=scripted`) run ထားရမယ်

```bash
cd H:/Cockpit-ghostwriter/apps/cockpit
flutter run -t lib/main_ghostwriter.dart -d web-server --web-port 5300 --dart-define=FORCE_MOBILE=true
```

**Android (emulator)** — `google-services.json` ကို `apps/cockpit/android/app/` ထဲ ထားရမယ်

```bash
cd H:/Cockpit-ghostwriter/apps/cockpit
flutter build apk --debug -t lib/main_ghostwriter.dart
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Emulator ကနေ local backend ကို `http://10.0.2.2:8791` နဲ့ ခေါ်တယ်။

**Mobile UI test**

```bash
cd H:/Cockpit-ghostwriter/packages/ghostwriter
flutter test
```

Dev server config `ghostwriter-api` (scripted၊ :8791) နဲ့ `ghostwriter-app` (:5300) က ဒီ repo ရဲ့ `.claude/launch.json` ထဲမှာ ရှိတယ်။

---

## 11. ဖြစ်စဉ် အကျဉ်း

| ရက် | ဘာဖြစ်ခဲ့လဲ |
|---|---|
| 09-27 | `Mobile` folder ဆောက်၊ Cockpit PR 16/17/18 ကို ဆွဲယူ၊ GhostWriter ကို standalone app အဖြစ် ခွဲထုတ်၊ `ghostwriter-mobile` repo ဆောက်ပြီး push |
| 10-02 | Mobile UI: landing → touch up (ChatGPT style၊ animation၊ haptics၊ OctoCredits pill) → ghost artwork၊ dot background၊ font → header / input / sidebar redesign → chat screen |
| 10-02 | OctopilotWeb ရဲ့ agent loop ကို ဖတ်၊ chat screen က flow နဲ့ မကိုက်တာ သိ။ Headless editor၊ backend မှာရေးတာ၊ pill တွေ၊ progress bar ကို ဆွေးနွေးဆုံးဖြတ် |
| 10-02 | Backend ကို Rust နဲ့ ရေးဖို့၊ Postgres သုံးဖို့ ဆုံးဖြတ်။ Contract ရေး |
| 10-02 | App က GhostWriter + Study Studio ပေါင်းထုတ်မှာဆိုတာ သိ → Cockpit monorepo ကို ပြန်ရွှေ့၊ module + flag ပုံစံ |
| 10-02 | Phase 1a၊ 1b၊ 1c ပြီး။ AI အစစ်နဲ့ essay တစ်ပုဒ် ရေးနိုင် |
| 10-02 | Push မလုပ်ခင် secret စစ်တာမှာ history ထဲက DB password တွေ့၊ push ရပ်ထား |
| 10-03 | Phase 1d ပြီး: editor save၊ document stream၊ version / restore (`39f3058`) |
| 10-03 | Phase 2a / 2b: Rust API client၊ timeline၊ phone chat အသစ်၊ read-only viewer။ Browser မှာ အစအဆုံး စမ်း |
| 10-03 | Design ပြင်: cardless chat (မေးခွန်းပဲ card)၊ editor အဖြူ၊ background `#222323` မီးခိုး dot + hover |
| 10-03 | 2c (desktop) ကို နောက်မှ လုပ်ဖို့ ဆုံးဖြတ် |
| 10-03 | Phase 2d: Google sign-in (Android / iOS / web)၊ App ID `com.boardwalklabs.octopilot`၊ Android build ပြင်၊ emulator မှာ picker ပေါ် |
| 10-03 | Phase 2 commit (`7fccc54`, `28996aa`) |
| 10-03 | Phase 3: mobile editor (ပြင်လို့ရ၊ autosave၊ History)။ doc_oct core မခွဲဘဲ dependency နဲ့ မျှသုံးဖို့ ဆုံးဖြတ်။ Browser မှာ ပြင်ပြီး save ဖြစ်တာ စမ်းပြီး (`ce800f5`) |
| 10-03 | Phase 4a: revision (ပြင်ခိုင်းတိုင်း run အသစ်)၊ `revise_essay`၊ app မှာ run အားလုံး conversation တစ်ခု |
| 10-03 | Phase 4b: source review (ဖယ်တာ / focus note)၊ backend + app |
| 10-03 | Phase 4c: humanizer (StealthGPT / UndetectableAI) + paragraph split၊ backend |
| 10-03 | Phase 4d: source evaluate၊ critique၊ Ask Octo (header icon)။ Phase 4 ပြီး |
| 10-03 | Phase 5a: push notification (server + app)။ ဖုန်းအစစ်မှာ မစမ်းရသေး |
| 10-04 | Phase 5b: run queue + worker (lease)၊ park / resume၊ restart ကျော်ပြီး ဆက်ရေးတာ |
| 10-04 | Stop ခလုတ်ကို composer ထဲ၊ concurrent run ("Your turn")၊ park ချက်ချင်း (`0`) |
| 10-05 | ကြားဖြတ် message: ချက်ချင်းဖြေ၊ directive၊ ရေးနေတုန်း ပြန်ရေး၊ မေးခွန်းစောင့်နေတုန်း ပြန်မေး (PLAN-ai-settings.md အပိုင်း A) |
