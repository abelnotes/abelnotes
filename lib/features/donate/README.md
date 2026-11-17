# Donating handwriting

contribute.abelnotes.app is a web page where volunteers write prompted
formulas and circuit symbols, check them, and send them to train the
on-device recognition. It is the only way to donate: the notes app has no
donation screen and sends nothing. The page is a separate Flutter web entry
point, `lib/main_contribute.dart`, and nothing in the notes app imports this
folder.

## Why it works this way

- **A page of its own, not a screen in the app.** Donating is a separate,
  deliberate act (as on Common Voice): the notes app keeps saying that notes
  never leave the device or the person's own server, and the store privacy
  labels stay as they are. A link can be shared in a post and used without
  installing anything.
- **Built from the app's code.** The page reuses the app's pen handling (and
  the Safari stylus fix in `web/index.html`), the formula typesetting, the
  circuit symbols as the tidy-up draws them (`symbolDrawing()` in
  `circuit_graph.dart`) and the translations. Being AGPL code served to
  visitors, its source is this folder.
- **Served by the receiver.** The donate Worker in the site repo serves the
  page and the API from one origin, so there is no CORS and no third party
  (fonts included: the build ships the app's fallback fonts).
- **Labelled by the prompt.** Writing to a prompt and pressing Next is the
  review; the queue still shows every sample to fix or discard before Send.
  A guided circuit's part is the box round all its ink, so the prompt asks
  for the symbol with short leads.
- **Nothing leaves before Send.** Samples stay in the browser (IndexedDB,
  per origin); the first Send asks for consent.

## Pieces

- `guided/guided_page.dart`: the prompt, the pad, Skip/Next and the queue
  button. `guided/writing_pad.dart` maps the pad width to 512 sample units
  (`kPadUnits`), the same frame on a phone and a desktop; once a pen has
  written, finger touches are taken for a resting palm.
- `guided/guided_prompts.dart`: formula templates that vary letters, case,
  digits, scripts, fractions and matrices (each checked to typeset), and the
  circuit classes in turn, all but `junction`, whose box ink alone cannot give.
- `donation_sample.dart`: one sample, and `toWire()`, exactly what the
  receiver accepts: strokes (x, y, ms from the first point, pressure) and
  the final label.
- `donation_store.dart`: the queue (one file per sample plus `state.json`
  with the consent and the receipts) on the browser's IndexedDB through
  `WebFs`. At most 200 samples; a full queue refuses new ones rather than
  dropping confirmed ones.
- `donation_client.dart`: the API. The page sends to its own origin;
  `--dart-define=ABEL_DONATE_URL=` points other builds elsewhere.
- `donation_screen.dart`: the queue, the consent, the receipts.
  `donation_review_page.dart` fixes a circuit sample (tap a part to change
  or remove it, drag to add one, two fingers or the wheel to zoom),
  `donation_formula_page.dart` a formula (LaTeX beside its preview, Reset to
  the prompt; only printable ASCII that typesets can be marked right).

## Consent and receipts

The first send asks for training consent and age 16 or over (and the
consent age where the donor lives), plus a separate, unticked box for
publishing in a dataset. Each send returns a receipt code, kept in the
browser: it is the only way to check or delete a donation, since the
receiver stores nothing that links it to a person. Withdrawing deletes
every donation whose receipt is kept here (one DELETE each; a failed one
stays listed with its own button) and asks again before the next send.
Keep the consent version in step with `CONSENT_VERSIONS` in the Worker and
with the privacy page.

## Limits

The receiver takes 50 samples and 2 MiB per send; the queue sends in
batches under both.

## Building

`donate/build_page.sh <app checkout>` in the site repo runs
`flutter build web -t lib/main_contribute.dart` and copies the result where
the Worker serves it.
