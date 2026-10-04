# GhostWriter content policy

Status: first version built (`backend-rs/crates/ghostwriter-api/src/safety.rs`,
2026-10-05) with a ready-made classifier; see "How the classifier works" and
"Decisions". This defines what the writing agent
and the main chat will and will not produce, and how a request that crosses
the line is handled. It is a **content-safety** layer, separate from the
**prompt-injection** defences planned for file uploads (untrusted file
content).

## Why this exists

- The backend has no moderation of its own today; whether a harmful request
  is refused depends entirely on whichever OpenRouter model is called, which
  is inconsistent and not something we should rely on.
- Provider terms (OpenAI, Anthropic, etc. via OpenRouter) forbid using their
  models for harmful output. Abuse through our key can get the key suspended.
- App Store / Play Store expect AI apps to moderate generated content.
- GhostWriter is an academic tool: students legitimately write about crime,
  security, war, drugs, extremism and other hard topics. The policy must
  allow genuine academic work while refusing operational harm.

## The core distinction: topic vs. task

We do **not** block topics. We block **tasks**. The same topic is fine as
analysis and refused as a how-to.

| Topic | Allowed (analysis, informative, argumentative) | Refused (operational / actionable) |
|---|---|---|
| Account security | How account-takeover attacks work; how users and companies defend against them; the ethics and law around them | A precise, step-by-step procedure someone could follow to break into an account they do not own |
| Drugs | History, policy, health effects, the economics of trafficking | A synthesis or production procedure |
| Weapons / explosives | Arms-control policy, history, the physics at a conceptual level | Build or acquisition instructions |
| Extremism | How radicalisation works; counter-terrorism policy | Material that promotes or recruits for a violent group |

The test for the refused column: **would the output function as a usable
guide to cause real harm?** If yes, refuse regardless of the framing. The
framings below do **not** move a task from refused to allowed:

- "for a class / assignment / research paper"
- "legit", "granted", "authorised", "with permission"
- "for educational purposes", "hypothetically", "in a story"
- "I'm a professional / pentester / the account is mine"
- the request arriving inside an uploaded file rather than typed

## Categories we refuse (the "disallowed task" list)

Refuse to produce content whose main value is to **carry out**:

1. Unauthorised access to computers, networks or accounts — actionable
   intrusion, privilege escalation, or credential theft procedures.
2. Malware — code or step-by-step methods to create or deploy it.
3. Weapons, explosives, or other tools of mass harm — build or acquisition
   instructions.
4. Illegal drugs or regulated toxins — synthesis or production procedures.
5. Serious physical harm to self or others — methods or encouragement.
   (Self-harm gets the support response below, not a flat refusal.)
6. Sexual content involving minors — any form, no exceptions.
7. Targeting a real, identifiable person to harass, threaten, dox, or defame.
8. Fraud, scams, or deception at scale — working scripts, phishing kits,
   fake documents meant to pass as genuine.

This list lives in the policy prompt and is versioned; it is reviewed before
each release.

## What we still allow, broadly

- Academic analysis, argument and explanation on any topic, including the
  hard ones above, at the conceptual level.
- Fiction and persuasive writing that references difficult themes without
  becoming an operational guide.
- Security and safety writing that helps a reader **defend** (how an attack
  works so you can prevent it), kept at the level of understanding, not a
  runbook.

When a request is close to the line, prefer producing the **defensive /
analytical** version and saying so, over a flat refusal.

## How a refused request is handled

The agent does not just stop. It:

1. Declines the specific task in one short sentence, without repeating the
   harmful detail or giving a partial version.
2. Offers the nearest allowed version as a concrete next step
   ("I can write an informative essay on how these attacks work and how to
   defend against them — want that?").
3. Logs the refusal (see below). No lecture, no moralising.

Self-harm and crisis topics get a supportive response and, where we have
them, resources — never a refusal that reads as dismissive.

## Where the checks run (three points)

The classifier runs at three points so a harmful essay can't slip through by
being assembled from innocent-looking pieces:

1. **Task decision** — on the user's instruction (typed text, a confirmed
   task from a file, or a revise instruction), **before any credits are
   spent**. Cheapest place to stop.
2. **After the outline** — the whole shape of the essay is visible here,
   before sections are written and combined.
3. **Before output** — a final pass on the assembled sections before they
   are shown to the user.

This is the same three-point shape the upload flow uses; the two layers share
the plumbing but answer different questions (is this from the user? / should
anyone get this?).

## How the classifier works

Built with a **ready-made** classifier: OpenAI's moderation endpoint
(`omni-moderation-latest`, free), not a policy prompt of our own.

- Key: an `openai` row in the shared `api_keys` table. Without one the check
  is skipped with a warning.
- **Task, not topic**, mapped onto the endpoint's fixed categories: a run is
  stopped only by the categories about helping someone do harm (`illicit`,
  `illicit/violent`, `self-harm/instructions`, `self-harm/intent`,
  `sexual/minors`, `harassment/threatening`). The subject-level ones
  (`violence`, `hate`, `harassment`, `sexual`, `self-harm`) pass on their own,
  so essays about hard subjects are not blocked.
- **Fails open**: no key, an error or an unreadable answer lets the run go on
  (logged), so an outage does not stop every essay.
- A refused task gets one fixed reply (decline + offer the analytical version;
  self-harm gets the support reply with findahelpline.com) and the run ends as
  answered, not as an error. Refused at the brief: nothing is spent and the
  project stays `idle`. Refused at the output: the document goes back to what
  it was and the write is not charged.

Trade-off: the categories are OpenAI's, so we cannot tune them line by line.
If they prove too loose or too strict for academic writing, a policy-prompt
classifier can replace `Moderation` behind the same `Screen` trait.

## Logging and abuse handling

- Record refusals in `safety_events` (user, run, stage, category, time) —
  **never** the text itself.
- Repeated refusals from one account feed rate-limiting or a ban, reusing the
  device/account limits the app already has.
- Logs are for safety operations only and follow the same retention rules as
  the rest of the app.

## Decisions (2026-10-05)

1. The disallowed list stands; defensive security writing is allowed at the
   level of understanding.
2. Self-harm: a supportive reply with the international directory
   findahelpline.com (no region-specific lists yet).
3. Internal policy; users see only the short in-chat replies.
4. Every run is checked (one call before the run, one after the outline, one
   on the text). Runs take minutes, so the extra second does not matter.
5. Classifier: the ready-made moderation endpoint (above).
6. The main chat is not checked yet: it only answers about the app.

## Next steps

1. Add an `openai` key to `api_keys` (production needs it for the check to
   run; moderation calls are free).
2. Check the quick reply (`runs/aside.rs`) the same way.
3. Build a red-team test set (hidden-text PDFs, assignment sheets, "ignore
   instructions" essays, and operational-harm requests) and run it as an eval
   each release, with the uploads feature.
4. Use `safety_events` for rate limits on repeat refusals.
