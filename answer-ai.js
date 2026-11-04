/**
 * Gemini fallback for application-form questions the local answer bank cannot map.
 *
 * Node-side only: this is used by external-apply.js when it drives an employer's
 * form. The in-page Naukri/Wellfound scripts keep their own fetch because they run
 * inside the browser, but they use the same model and the same rules.
 *
 * Answers are requested in ONE batch per form pass: a 20-field ATS form at one call
 * per field would take minutes, while one JSON request answers all of them.
 * Results are cached per label — a form is filled in up to 3 passes.
 */
const MODELS = ['gemini-3.5-flash', 'gemini-flash-lite-latest', 'gemini-2.5-flash-lite'];
const cache = new Map();

const CONFIGS = [
  { maxOutputTokens: 700, temperature: 0.2, thinkingConfig: { thinkingBudget: 0 } },
  { maxOutputTokens: 700, temperature: 0.2 },
];

async function callGemini(key, prompt, { timeoutMs = 25000 } = {}) {
  for (const model of MODELS) {
    for (const generationConfig of CONFIGS) {
      const ac = new AbortController();
      const timer = setTimeout(() => ac.abort(), timeoutMs);
      try {
        const res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            signal: ac.signal,
            body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }], generationConfig }),
          },
        );
        // Not every model accepts thinkingConfig; retry that model without it.
        if (res.status === 400 && generationConfig.thinkingConfig) continue;
        if (!res.ok) continue;
        const data = await res.json();
        const text = (data?.candidates?.[0]?.content?.parts || [])
          .map((p) => p.text || '')
          .join(' ')
          .trim();
        if (text) return text;
      } catch (e) {
        // timeout / network — try the next model
      } finally {
        clearTimeout(timer);
      }
    }
  }
  return '';
}

// Field names that are identifiers, not questions ("applicant[lead_attributes", "menu-945").
const NOT_A_QUESTION = /[[\]{}]|^applicant|^(menu|field|input|select|item)[-_ ]?\d+$/i;
// Captchas are deliberate human checks; credentials and OTPs are never ours to answer.
const NEVER_ASK = /captcha|recaptcha|hcaptcha|password|passcode|one[- ]?time|otp\b/i;

function askable(label) {
  const q = String(label || '').replace(/\s+/g, ' ').trim();
  if (q.length < 3 || q.length > 300) return false;
  if (!/[a-z]/i.test(q)) return false;
  if (NOT_A_QUESTION.test(q) || NEVER_ASK.test(q)) return false;
  return true;
}

const cleanValue = (v) =>
  String(v == null ? '' : v)
    .replace(/^["'`\s]+|["'`\s]+$/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 200);

/**
 * Answer a batch of field labels in one request.
 * Returns a Map keyed by the lower-cased label; unanswered labels map to ''.
 */
async function aiAnswers(labels, CV, { key, timeoutMs = 25000 } = {}) {
  const out = new Map();
  if (!key) return out;

  const wanted = [];
  for (const label of labels || []) {
    const q = String(label || '').replace(/\s+/g, ' ').trim();
    if (!askable(q)) continue;
    const k = q.toLowerCase();
    if (cache.has(k)) out.set(k, cache.get(k));
    else if (!wanted.includes(q)) wanted.push(q);
  }
  if (!wanted.length) return out;

  const prompt = [
    'You are filling a job application form for this candidate.',
    'For each numbered field below, give the value to enter.',
    'Rules: values only, never the field name; yes/no fields => Yes or No; numbers => digits only;',
    'if the CV does not contain the answer, use "N/A".',
    'Reply with ONLY a JSON object keyed by field number, e.g. {"1":"India","2":"N/A"}. No markdown.',
    '',
    'CV: ' + JSON.stringify(CV),
    'Fields:',
    wanted.map((q, i) => `${i + 1}. ${q}`).join('\n'),
  ].join('\n');

  const raw = await callGemini(key, prompt, { timeoutMs });
  let parsed = {};
  try {
    const json = (raw.match(/\{[\s\S]*\}/) || [''])[0];
    if (json) parsed = JSON.parse(json);
  } catch (e) {
    // unparseable reply — leave the batch unanswered
  }

  wanted.forEach((q, i) => {
    let value = cleanValue(parsed[String(i + 1)] ?? parsed[i + 1]);
    if (/^n\/?a$/i.test(value) || /^not (available|applicable)$/i.test(value)) value = '';
    cache.set(q.toLowerCase(), value);
    out.set(q.toLowerCase(), value);
  });
  return out;
}

/** Single-label convenience wrapper (used by diagnostics/tests). */
async function aiAnswer(label, CV, opts) {
  const map = await aiAnswers([label], CV, opts);
  return map.get(String(label || '').replace(/\s+/g, ' ').trim().toLowerCase()) || '';
}

module.exports = { aiAnswer, aiAnswers, callGemini, askable, MODELS };
