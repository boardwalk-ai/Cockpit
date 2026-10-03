# Plan: Octopilot app shell

ရေးတဲ့နေ့: 2026-10-06 · အခြေအနေ: **design အတည်ပြုပြီး၊ UI အရင်ဆောက်**

## Design (အတည်ပြုပြီး)

- App = **Octopilot** super app။ Mode ၃ မျိုး: **Create** (GhostWriter)၊ **Learn** (Study Studio)၊ **Organize** (OctoNotes)
- **Home** = ChatGPT လို main chat။ စကားမပြောရသေးရင် အလယ်မှာ Create / Learn / Organize ကတ် ၃ ကတ်
- ကတ်နှိပ် → အဲ့ mode ရဲ့ **Library** page → module card တွေ (မပြီးသေးရင် "Soon") → နှိပ်ရင် module ပွင့်
- **☰ drawer** = main chat ရဲ့ history သီးသန့် (module တွေရဲ့ chat history နဲ့ မရော)
- **Settings** (shell ပိုင်): account၊ AI model / voice၊ notifications၊ appearance (Dark / Light / System)၊ OctoCredits၊ about / legal၊ sign out၊ **delete account**
- GhostWriter ကတော့ ပထမ release မှာ dark အမြဲ (light theme နောက်မှ)

## Main chat (ဆုံးဖြတ်ပြီး)

| | |
|---|---|
| Backend | **Service အသစ်** (`app-api`၊ ကိုယ်ပိုင် DB)။ နောက်မှ `/v1/ai/*`၊ app status၊ devices ကို ဒီကို ရွှေ့ |
| OctoCredits | **အလကား**။ Device အလိုက် rate limit + တစ်ရက် free message limit (admin ပြင်လို့ရ) |
| Web search | မထည့်သေး |
| ဖြေတဲ့ အကြောင်းအရာ | **App နဲ့ ဆိုင်တာပဲ** |
| Module ဆီ လွှဲတာ | မထည့်သေး၊ နောက်မှ |
| Ask Octo | Module ထဲမှာပဲ (main shell မှာ main chat ရှိလို့ မလို) |
| **Voice first** (CEO) | Home ရဲ့ အဓိကခလုတ် = voice orb၊ typing က ဘေးက keyboard ခလုတ်။ Voice turn တွေ chat history ထဲ ဝင် |

## Code

- `packages/octopilot_shell` — shell UI (Home၊ drawer၊ mode Library၊ Settings)။ Module တွေကို import မလုပ်ဘူး၊ host app က entry list နဲ့ callback တွေ ပေးတယ်
- `MainChat` interface: backend မရှိခင် `DemoMainChat` (local) နဲ့ run
- `apps/cockpit/lib/main_octopilot.dart` — release app entry (shell + modules)

## အစဉ်

1. ✅ Shell UI (demo chat) + animation (aurora၊ hero၊ stagger) + voice mode UI (demo engine)
2. `app-api` service + main chat backend (thread၊ stream၊ limit)
3. Settings ကို တကယ်ချိတ် (AI settings sheet ရွှေ့၊ delete account endpoint၊ notifications)
4. Version / maintenance gate (`/v1/app/status`)
5. Module ဆီ လွှဲတာ၊ calendar (နောက်မှ)
