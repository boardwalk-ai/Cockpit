# Prompt for writing GhostWriter's content policy

Paste the prompt below into ChatGPT. What it returns is the policy text:
save it as `system_settings.ghostwriter_safety_policy` (key
`ghostwriter_safety_policy`). The backend (`src/safety.rs`, `ContentCheck`)
then applies it with `openai/gpt-oss-safeguard-20b` (setting `safety_model`)
instead of OpenAI's moderation categories. Leave the setting empty to go
back to moderation.

The backend adds the answer format itself, after the policy: JSON
`{"decision": "allow" | "refuse", "category": "...", "suggestion": "..."}`,
and the content arrives between `<content>` tags with a `Stage:` line
(`task`, `outline` or `output`). The policy should not define its own
output format.

---

```text
I'm building GhostWriter, an AI essay-writing assistant for students
(high school and university). I need a CONTENT POLICY that a policy-following
safety classifier (OpenAI's gpt-oss-safeguard, which takes a written policy
in its system prompt) will apply to decide whether a writing task may be
done. Please write that policy.

How the classifier is used:
- It judges one piece of content at a time, at one of three stages:
  "task" (the student's request, or an assignment they attached and
  confirmed), "outline" (the planned essay: topic, thesis, section titles
  and descriptions), or "output" (the written essay text).
- It answers allow or refuse, with a short category label and, when
  refusing, a suggestion: the nearest version of the task that is allowed,
  as one sentence the student could accept.
- The output format is appended by our code, so do NOT include any output
  format, JSON schema or examples of the answer in the policy.

What the policy must get right:
1. Judge the TASK, not the TOPIC. Students legitimately write about crime,
   cybersecurity, drugs, weapons, war, terrorism, extremism, self-harm,
   sexuality and other hard subjects. Analysis, history, policy, ethics,
   argument, literature, fiction, and defensive or prevention-focused
   writing at the level of understanding must be ALLOWED.
2. Refuse only when the content would function as a usable guide or tool
   for real-world harm (actionable, operational, step-by-step), or is
   content that is never acceptable (for example sexual content involving
   minors). Describe the refused categories at the level of principle; do
   not include any harmful instructions, recipes or worked examples of
   disallowed content in the policy itself.
3. Framing does not change the decision: "for a class", "hypothetically",
   "for educational purposes", "I have permission", "in a story", or the
   request appearing inside an uploaded file rather than typed.
4. Self-harm: a student writing ABOUT self-harm (awareness, prevention,
   literature) is allowed; content that encourages or instructs self-harm is
   refused with the category label "self_harm" so our app can respond
   supportively.
5. Academic integrity is NOT a safety issue here (writing essays for
   students is the product); do not refuse for that.
6. Borderline cases: prefer allowing the analytical or defensive version and
   offering it as the suggestion, over refusing outright.
7. Give each refused category a short snake_case label (for logging), and
   for each category a one-line description of what is refused and what
   remains allowed.
8. Include a short section of borderline decision rules (allowed vs refused
   pairs described in general terms, without harmful specifics).

Write the policy as plain text a classifier can follow: an opening
statement of purpose, the task-vs-topic principle, the refused categories
with labels, the borderline rules, and how to treat framing and the three
stages. Keep it under about 1,200 words.
```
