import 'summary_formatter.dart'
    show kSummaryLengthDetailed, kSummaryLengthShort;

/// The one place the summariser's instructions are written.
///
/// This used to live in `GeminiNanoPlugin.kt`, which was fine while Nano was
/// the only path. It stopped being fine the moment a second path existed: the
/// cloud fallback is a plain HTTP call made entirely from Dart, so a Kotlin
/// prompt would have meant two copies of the same rules, drifting apart with
/// every edit. This project has already paid for that shape of bug twice —
/// two timeouts racing each other, and two different bullet-count limits — so
/// the prompt is assembled here and handed to whichever backend runs it.
///
/// Kotlin now receives a finished string and does nothing to it.

/// What each summary-length tier asks the model for.
///
/// The reader picks the tier in Quick Settings; the model is told the numbers
/// rather than left to judge how long an article "deserves" to be, which is
/// what it used to do and the least predictable part of this whole feature.
///
/// [bulletCap] is one below [kSummaryTierLimits]'s backstop for the same tier,
/// deliberately — see the note there. Change these and change those.
class SummaryTierPrompt {
  final String target;
  final int ceiling;
  final int bulletCap;

  const SummaryTierPrompt({
    required this.target,
    required this.ceiling,
    required this.bulletCap,
  });
}

const SummaryTierPrompt _short =
    SummaryTierPrompt(target: '40-50', ceiling: 100, bulletCap: 3);
const SummaryTierPrompt _standard =
    SummaryTierPrompt(target: '75-100', ceiling: 250, bulletCap: 5);
const SummaryTierPrompt _detailed =
    SummaryTierPrompt(target: '150-200', ceiling: 350, bulletCap: 8);

SummaryTierPrompt summaryTierPromptFor(String name) => switch (name) {
      kSummaryLengthShort => _short,
      kSummaryLengthDetailed => _detailed,
      _ => _standard,
    };

/// How much of the article body reaches the model.
///
/// 2500 characters covers the lede and substantive middle of a news article —
/// where list-type payloads live — and cuts time-to-first-token materially
/// versus sending the whole body. Applied here rather than per-backend so
/// both get the same article, and so a difference in output is never quietly
/// a difference in input.
const int kSummarySourceCharLimit = 2500;

String summaryLangInstructionFor(String locale) => switch (locale) {
      'es' => 'Write the summary in Spanish.',
      'fr' => 'Write the summary in French.',
      'de' => 'Write the summary in German.',
      'it' => 'Write the summary in Italian.',
      _ => 'Write the summary in English.',
    };

/// The complete prompt, ready to send to any backend.
///
/// [content] is the raw article text; the trim and the `Content:` label are
/// applied here so callers cannot each do it differently.
String buildSummaryPrompt({
  required String title,
  required String content,
  required String langInstruction,
  required String lengthTier,
}) {
  final tier = summaryTierPromptFor(lengthTier);
  final source = 'Content: ${content.length > kSummarySourceCharLimit ? content.substring(0, kSummarySourceCharLimit) : content}';

  return '''
You are a ruthless news summariser. Report only what the article text states.

$langInstruction

RULES
1. Write toward approximately ${tier.target} words — but never pad if the
   article genuinely has less to say than that. If the real content
   supports less, write less; do not stretch with filler or repetition to
   reach the target. The target is a ceiling to aim under, not a floor to
   hit no matter what.
2. If the headline promises something specific — a number of items ("5
   reasons", "3 hidden skills"), a withheld name, or poses a direct
   question — the summary must resolve it explicitly, at every length
   tier. At the shortest tier, do this as tersely as the budget allows
   (name the items plainly rather than giving each a full descriptive
   clause) — but never leave the tease unresolved just because the tier is
   short.
3. Facts only: names, numbers, dates, prices, versions, outcomes, who did
   what. Every sentence must contain at least one concrete fact.
4. Never write filler such as "aims to", "is expected to", "will likely",
   "is set to", "generating excitement", "fans are eager", "remains to be
   seen", or "details are scarce". If a thing is not stated, leave it out
   entirely.
5. Do not restate the headline as a sentence. Do not describe what the
   article is about in the abstract ("this article discusses..."). Report
   what it actually says.
6. Never infer, guess, or fill gaps with general knowledge.
7. ${tier.ceiling} words is the hard ceiling across the whole response
   (paragraph plus any bullets).
8. No preamble, no sign-off, no headers, no markdown bold.

FORMAT
A paragraph in plain readable prose — complete sentences, not fragments —
capturing the real substance, sized to the target in rule 1. Then, only if
the headline promises a specific list/count of things OR the article has
genuinely distinct, separately-listable points, add up to ${tier.bulletCap}
bullets below the paragraph, each naming the actual specific thing. If
nothing earns a bullet, the paragraph alone is complete.

Bullets, when used, each start with "- " on their own line, after a blank
line following the paragraph.

Examples of resolving a headline's tease correctly (illustrative, not
literal templates):
- Headline promises "5 reasons X will happen" → each of the 5 reasons is
  named specifically, not "the author gives several reasons why."
- Headline references "hidden skills" in a game → the summary names the
  actual skills (e.g. "blocking, sneak attacks, and archery bonuses"), not
  "the game has some secret skills."
- Headline says a company "warns against" something without naming it →
  the summary names the actual thing and the actual stated reason, not
  "Apple issued a warning about a product."

IF THE TEXT IS THIN
If the text below is only a teaser and lacks the detail the headline
promises, write as full a response as the available material genuinely
supports — even a single short sentence — rather than padding with filler
or inventing detail to reach the tier's target.

ARTICLE
Title: $title

$source

Summary:''';
}
