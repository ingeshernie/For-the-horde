# Conversion research — Bike Tours Vosges · Travel-File AI Agent v5.7

Source: n8n export *"Bike Tours Vosges - Travel-File AI Agent v5.7 (password on
background start, 24 Sept)"* — 71 nodes (66 functional + 4 sticky notes + 1 no-op),
`executionOrder: v1`, `binaryMode: separate`, an external error workflow attached,
exported with `active: false`.

This document only describes what the workflow **does today**. Solutions belong in
Phase 2 (`docs/port-plan.md`).

---

## Overview

For one cycling trip (e.g. *"7 nuits Xonrupt"*), the workflow builds a printed
**day-by-day travel file** in the client's language (FR / NL / EN):

- a **full day guide** (A5 portrait HTML, may run over several pages) — all route
  variants for the day, each with its own km-ordered list of landmarks, shops,
  restaurants, e-bike charging points and Komoot waypoints, plus tonight's
  accommodation and a comparison table of the variants;
- a **compact day card**, recto + verso (120 × 210 mm HTML) — main route stats,
  SVG route map, elevation profile, one line per alternative (recto); tonight,
  shortcuts and the main-route listing with LLM-shortened text (verso).

Each day is emailed to the reviewers (Sofie + Inge) for **human approval**. The run
pauses until a reviewer clicks *Approve* or fills in a short *Needs changes* form.
Approved days are uploaded to a Google Drive folder. After the last day, one
**to-do email** lists every rejected day, where to fix it, and the `Days to build`
value to re-run with.

Inputs come from four pre-existing sources (the "v4 scope correction"):
1. GPX track bundles (3 zips: *long*, *standard*, *direct* variants)
2. sleep-place list (xlsx)
3. Sofie's regional supplier list (**hard-coded in a Code node**)
4. *le guide* landmark list, geocoded (xlsx, FR/NL/EN text)

Almost everything is deterministic code (~1,200 lines of JS across 23 Code nodes). The LLM
(Claude Haiku 4.5) is used in only two places: translating Sofie's French supplier
blurbs, and shortening card text to fit the space.

---

## Trigger & schedule

**On demand only — no schedule.** The workflow starts in two steps:

| Step | Node | What happens |
|---|---|---|
| 1 | **New Trip Confirmed (Form)** — n8n-hosted form, HTTP Basic Auth | Fields: `Trip ID` (required), `Client language` (French / Dutch / English, required), `Days to build` (optional: empty = all days, or e.g. `2` / `2,5`). |
| 2 | **Start Trip in Background** — HTTP POST | Re-posts the form answers to the workflow's **own** production webhook `…/webhook/btv-trip-start` (hard-coded `inge.app.n8n.cloud` URL), with an `x-btv-key` header whose value is **hard-coded in the node**. |
| 3 | **Trip Start (background)** — webhook, header auth | The real start of the run. **Confirm Trip Accepted** replies `{ok:true}` at once so the form doesn't wait. |

Why the detour (from the node notes): n8n doesn't allow the review-button
resume pages in a run started by a form, and *Execute Workflow + Wait* was unreliable.
The workflow must be **active** for step 2 to work.

**One run lasts as long as the review does.** It stays paused (n8n *Wait* nodes) until a
reviewer responds for each day, one day at a time. The Wait nodes have **no timeout**.

---

## Nodes

Grouped by stage, in execution order. "Code" = n8n Code node (JavaScript).

### A. Start
| Node | Type | Does | Porting notes |
|---|---|---|---|
| New Trip Confirmed (Form) | Form trigger, basic auth | 3-field form (see above) | Need an auth-protected start form or equivalent |
| Start Trip in Background | HTTP Request | POST form data to own webhook, header `x-btv-key`, 30 s timeout | Workaround for n8n limits; a hard-coded secret sits in the node |
| Trip Start (background) | Webhook (POST, header auth, `responseMode: responseNode`) | Path `btv-trip-start` | |
| Confirm Trip Accepted | Respond to Webhook | `{ok:true}` | |
| Refuse: Wrong Password | Respond to Webhook (403) | `{ok:false,error:'not allowed'}` | **Not connected to anything** — dead node (header auth on the webhook already rejects bad keys) |
| Set Trip Parameters | Set | `tripId`, `language` (French→`fr`, Dutch→`nl`, English→`en`), `daysToBuild`, and constants: `geoMatchRadiusM`=2000, `startToleranceM`=250, `supplierRadiusM`=500, `reviewerEmail` (2 addresses), `ebikeKmh`=18, `ebikeClimbMPerH`=800, `classicKmh`=15, `classicClimbMPerH`=400 | Reads `body` or the root, so it works for both start paths |

### B. Load sources (6 parallel branches from Set Trip Parameters)
| Node | Type | Does |
|---|---|---|
| Download GPX - Long / Standard / Direct | Google Drive download | 3 fixed Drive files: `GPX-7-nuits-xonrupt-long.zip`, `gpx-7-nuits-xonrupt.zip`, `GPX-7-nuits-xonrupt-direct.zip` |
| Unzip GPX - ×3 | Compression | Unzip to binary files |
| Tag as long / standard / direct | Code | Adds `variant` to each item (filenames can't tell long from standard) |
| Merge 3 GPX Bundles | Merge (append, 3 inputs) | |
| Download Sleep-Place List | Google Drive download | `sleep_place_list.xlsx` (a Google Sheet downloaded as xlsx) |
| Extract XLSX - Overnight Stops | Extract From File | Sheet `Overnight Stops` (the Code-node sandbox has no xlsx library) |
| Parse Sleep-Place List | Code | Rows → `{day, route, statedKm, statedElevM, placeName, address, hostName, phone, checkIn, dinner, sourceNote, lat?, lon?}` |
| Parse Curated Supplier List | Code | **Hard-coded array of 33 suppliers** (name, category, French blurb, lat/lon, optional phone/hours). Categories: bakery, food, cafe, bikeshop, charging, shop, water, toilet. A spreadsheet review copy is mentioned (`supplier-list-regional.xlsx`) but not read |
| Download le guide (geocoded) | Google Drive download | `le_guide_rebuilt_chatgpt.xlsx` |
| Extract XLSX - Entries | Extract From File | First tab (`Entries`) |
| Build le guide Lookup Table | Code | Drops placeholder IDs `1.8`, `1.9`. Flags IDs `2.2, 2.4, 2.6, 4.7, 4.10` as *needs verification*. Output `{id, region, title, lat, lon, confidence, needsVerification, text:{fr,nl,en}}` |
| Merge Sleep-Place + Supplier List → Merge In le guide Lookup | Merge (combine all) | Combines the three small sources into one item |

### C. Route analysis
| Node | Type | Does |
|---|---|---|
| Parse + Group Variants By Day | Code (~170 lines, core of v5) | See *Data flow §2* — parses every GPX, groups by day, picks the main route, finds shortcuts, computes riding times and start/finish warnings, applies the `Days to build` filter |
| Gate Days On All Sources Loaded | Merge (combine all) | Barrier: N day items × 1 sources item → N day items, each carrying all sources |
| Loop Over Day | Split In Batches (size 1) | Sequential per-day loop; the *done* output goes to the to-do list |

### D. Per-day enrichment (inside the loop)
| Node | Type | Does |
|---|---|---|
| Attach Sleep-Place To Day | Code | Tonight's place + last night's place; start/finish vs hotel check (only if the sheet has lat/lon); **numeric drift check** (GPX km/climb vs sheet values, >10 % → warning); builds the `arrival` sentence in the trip language from fixed templates |
| Geo-Match le guide To Each Variant (R26) | Code | For **each variant**: le guide entries within 2000 m of the track, suppliers within 500 m (or their own `radiusM`), the track's own named waypoints. Nearest track point gives the km mark + distance off route (brute-force loop over all points) |
| Attach Curated Supplier Entries For This Day | Code | **No-op pass-through** (kept "so the canvas layout stays the same") |
| Enrich Listings Per Variant | Code | Builds one km-ordered listing per variant (📖 le guide in the trip language, 📍 waypoint, category icon for suppliers), numbers the markers, thins the track to ~300 points `[lat,lon,ele,km]`, drops raw points and sources, builds the translation payload (supplier blurbs only) |
| Target Language != FR? | IF | Not FR → translate; FR → skip |
| Translate Sofie's Own Text (R05, narrowed) | Anthropic (Claude Haiku 4.5, 2048 max tokens) | Translate the `{entries:[{key,text}]}` JSON from French to NL/EN, keeping names, phones and times |
| Parse Translate Response | Code | Strips code fences, maps by key. **On parse failure: sets `translationFailed: true` and keeps the French text — nothing reads that flag** |

### E. Rendering (inside the loop)
| Node | Type | Does |
|---|---|---|
| Build Full Guide HTML (all variants) | Code (~240 lines) | A5 guide HTML: header, SVG map (all variants, km marks every 10 km, numbered places, north arrow, scale bar), SVG elevation profile (main route, shortcut markers, highest point), comparison table, tonight, a section per variant with shortcut sentences placed at their split km, emergency numbers + weather footer. Also builds **Chart.js configs** (full + a lighter "lite" version) for the email images |
| QuickChart: Map / QuickChart: Profile | HTTP POST `quickchart.io/chart/create` | Renders the map and profile as PNG for the email (email clients strip SVG). `continueRegularOutput` on error, 20 s timeout. Only coordinates and place numbers are sent |
| Attach Chart Images | Code | Uses the QuickChart URLs, or falls back to a GET URL built from the lite configs |
| Prepare Card Payload | Code | Text payload for trimming: `arrival` + main-route listing texts |
| Trim Card Text To Space Budget (LLM, bounded) | Anthropic (Claude Haiku 4.5) | Shorten to ≤140 chars (arrival ≤220), same language, keep names and numbers |
| Parse Trim Response | Code | Maps by key, then **hard-truncates** at 150 / 240 chars at a word boundary + `…`. Falls back to the original text |
| Build Recto HTML (compact) | Code | 120×210 mm: header with km / climb / e-bike time, SVG map, profile, one line per alternative |
| Build Verso HTML (compact) | Code | 120×210 mm: tonight (trimmed), shortcut one-liners, main-route listing (trimmed text, phone), emergency footer. `overflow:hidden` — content that doesn't fit is cut off silently |
| Merge Guide + Card HTML | Merge (append, 3 inputs) | recto + verso + guide |

The label tables, helpers, SVG map and SVG profile code are **copy-pasted** in all three
Build nodes (and the review UI strings in three other nodes).

### F. Human review (inside the loop)
| Node | Type | Does |
|---|---|---|
| Prepare Review Email | Code (~150 lines) | Review email HTML in the trip language: warnings box (route flags + drift), the guide/recto/verso embedded with **scoped CSS** (SVGs swapped for QuickChart PNGs), *✓ Approve* + *Review* buttons linking to `$execution.resumeUrl?d=approve|review&day=N` (keeps n8n's `signature` query param). Also pre-renders 4 HTML pages: review form, approved, noted, stale link. Subject gets a ⚠ prefix when there are warnings |
| Send Guide + Card to Sofie for Review (R07) | Gmail send | To `reviewerEmail` (2 addresses) |
| Wait for Review Click | Wait (webhook resume, respond via node) | Pauses the run |
| Link For This Day? | IF | `query.day` matches this day and `d` ∈ {approve, review}; otherwise → **Show 'Old Link' Page** → back to waiting |
| Approve Clicked? | IF | approve → **Show 'Approved' Page**; review → **Show Review Page** |
| Show Review Page → Wait for Review Page | Respond + Wait | Page = same preview + GET form (decision approve/change, category from 7 options, note). Submits to the resume URL with hidden fields |
| Answer From Review Page? | IF | `d=form` and the day matches; otherwise → **Show 'Old Link' Page (2)** → back to waiting |
| Read Review Page | Code | → `{approved, reviewRecord:{day, decision, catIndex, remark, flags}}` |
| Show 'Thank You' Page | Respond | Approved page, or "noted" page |
| Approved on Review Page? | IF | yes → same save path as one-click approve; no → reviewRecord straight back to Loop Over Day |
| Restore Binary After Approval | Code | Restores the 3 HTML binaries from Prepare Review Email |
| Upload Recto / Verso / Guide HTML | Google Drive upload, **retry 3× / 2 s** | Folder *"bike tours vosges final flash cards"*, names `{tripId}-day{N}-{recto|verso|guide}.html` |
| Record Approval | Code | After the **guide** upload only → `reviewRecord{decision:'Approve'}` → back to the loop |

### G. Wrap-up (after the last day)
| Node | Type | Does |
|---|---|---|
| Build To-Do List | Code | Collects all `reviewRecord`s → HTML email: approved days, to-do table (category → *where to fix it*, e.g. "Komoot: correct the track…"), automatic warnings, the re-run hint `Days to build = 2,5` |
| Send To-Do List to Sofie | Gmail send | Same recipients |
| All Days Rendered - Ready for Sofie to Send | No-op | End marker |

### Sticky notes (design decisions recorded on the canvas)
- **v5 route variants (24 Sept):** LONG = main route; standard/direct = alternatives. Every variant gets its own listing. All variants must start/finish at the hotel — **flagged, never edited**. Shortcuts are computed in code, worded from templates, no LLM. <70 % overlap → "alternative route", not a shortcut.
- **v4 scope correction (20 Sept):** the four sources above.
- **Card map gap (open):** "Komoot export is landscape, card is portrait… later render from GPX". *The recto already renders an SVG map from the GPX, so this note looks out of date.*
- **LLM boundaries:** translate only Sofie's own text; trim only card text; everything numeric is code. *Says the arrival note is translated, but the code no longer sends it.*

---

## Integrations & credentials

| Service | Used by | Credential in n8n | Data sent |
|---|---|---|---|
| **n8n Form** (hosted) | Start form | HTTP Basic Auth | — |
| **n8n Webhook** (own) | Background start | Header auth (`x-btv-key`) — **the same key is also in plain text in the HTTP Request node** | Form answers |
| **Google Drive** | 5 downloads, 3 uploads | Google Drive OAuth2 | Reads 5 fixed file IDs; writes into 1 fixed folder ID |
| **Gmail** | Review email per day, to-do email | Gmail OAuth2 | HTML emails to 2 fixed addresses |
| **Anthropic API** | Translate, Trim | Anthropic API key | Model `claude-haiku-4-5-20251001`; supplier blurbs and card text only, no track points |
| **QuickChart.io** | Map + profile PNG | none (public) | Route coordinates + place numbers, no names |
| meteofrance.com | — | — | Text link printed in the footer only |
| n8n error workflow `s8D9kJMLJCBJ8T8a` | On failure | — | Contents unknown (not in the export) |

Hard-coded configuration that will need to become settings: the 5 Drive file IDs and
1 folder ID, the reviewer addresses, the n8n webhook URL, the radii/speeds in *Set Trip
Parameters*, the le guide verify/placeholder ID lists, the supplier list, and the
emergency numbers.

---

## Data flow

1. **Start.** Form → `{tripId, language, daysToBuild}` + constants.

2. **GPX → days** (*Parse + Group Variants By Day*):
   - Every `.gpx` in the 3 zips (skips `._` macOS files). The day number comes from the leading
     digits of the filename. The variant comes from the bundle tag, or `direct` if the
     filename contains it. Sofie's stated km/elevation is read from `…-NNkm-NNNm` in the
     filename.
   - Regex XML parsing → points `{lat,lon,ele,cumKm}` (haversine), `<wpt>` waypoints.
     Distance to 0.1 km. Climb uses **3 m hysteresis**.
   - Per day: sort long → standard → direct (then longest). The first one is the **main** route
     (warning if it isn't a long track). IDs: `main`, `standard`, `direct`, `standard-2`…
   - Riding time = km / speed + climb / climb-rate, rounded to 15 min (e-bike 18 km/h + 800 m/h;
     classic 15 km/h + 400 m/h).
   - **Shortcut detection** for each alternative vs main: grid hash (~0.005° cells).
     A main-route point is "shared" if an alternative point is within **60 m**. Off-route
     runs ≥ **500 m** are divergences. If ≥ **70 %** of the main route is off the alternative →
     *alternative route*. Otherwise each divergence is a shortcut if the alternative
     rejoins later and saves ≥ **1 km**: `{splitKm, rejoinKm|toFinish, savedKm,
     savedGainM, savedMinEbike}`. Shared %.
   - Warnings: alternative start/end > **250 m** from the main route's; main start >250 m
     from the previous day's main finish; skipped files (on the first day only).
   - Then filter by `Days to build` (all days are parsed first, so the day-to-day check
     still works).

3. **Per day:** + sleep place (hotel distance warnings, drift >10 % warning,
   arrival sentence) → + geo-matched le guide / suppliers / waypoints **per variant** →
   listings with markers 1..n → slim track (~300 pts) → [translate supplier blurbs if
   not FR] → guide HTML + chart configs → QuickChart PNGs; in parallel: trim → recto +
   verso HTML.

4. **Review:** email with embedded preview → wait → approve (one click or via
   form) ⇒ upload 3 HTML files to Drive, record *Approve*; needs changes ⇒ record
   `{catIndex, remark}`, nothing uploaded. Stale or other-day links show a "stale" page and
   the run keeps waiting.

5. **End:** all records → to-do email → done. Re-running with `Days to build`
   rebuilds only those days.

**Outputs:** per approved day, 3 HTML files in Drive (`{trip}-dayN-guide|recto|verso.html`),
plus emails. No PDF — printing seems to happen by hand from the HTML.

---

## n8n freebies to rebuild

| What n8n gives | Where it's used | A standalone app needs |
|---|---|---|
| **Durable paused executions** with resume URLs (signed) | One run waits hours or days per day for a click; resumes in the same state | Persisted job state (DB/files) + signed approve/review links + a resume handler |
| Hosted **form** with basic auth | Starting a trip | A small auth-protected web form (or CLI) |
| **Webhook** endpoints + "respond to webhook" HTML pages | Start, approve, review form, thank-you/stale pages | An HTTP server with these routes |
| **Credential vault + OAuth refresh** | Drive, Gmail, Anthropic | Env/secret management; Google OAuth or a service account |
| **Sequential loop** (Split In Batches) with the done branch | One day at a time, to-do after the last | Explicit state machine: current day, records |
| **Merge barrier** | Wait for all sources | Just load sources before the loop |
| **Retries** (3× / 2 s on uploads) | Drive uploads | Retry wrapper |
| **Continue on error** | QuickChart → lighter fallback URL | try/except + fallback |
| **Error workflow** | Any failure | Failure alert (email) |
| **Execution history / logs** | Debugging past runs | Run log + stored artifacts per run |
| **XLSX extract, unzip, binary store** | Sources | Libraries (e.g. `openpyxl`, `zipfile`) |
| **Hosting + HTTPS** (n8n cloud) | Public resume links | A deployed HTTPS host — needed because email links must reach the app |

---

## Open questions

1. **Test data.** For parity tests, can we get copies of the 3 GPX zips, `sleep_place_list.xlsx`
   and `le_guide_rebuilt_chatgpt.xlsx` (or anonymised samples), plus one or two real
   review emails / output HTML from n8n to compare against?
2. **Exported JSON contains secrets/PII.** The `x-btv-key` value is in plain text and the
   reviewer email addresses are in the export. Should a cleaned copy go in the repo (I
   haven't committed the raw file)? The key should probably be rotated either way.
3. **Who starts trips, and how often?** Sofie, Inge, or both? Roughly how many trips per
   month/season? (This decides hosting and how much UI is needed.)
4. **Review flow.** Keep the one-day-at-a-time email review, or would one email / one page
   with all days (approve each) be acceptable? Should waits time out or send reminders?
5. **Drive re-uploads** currently add duplicate files with the same name on re-runs. Should they
   overwrite instead?
6. **Final output format.** HTML only today. Is PDF (print-ready A5 guide + 120×210 card)
   wanted? Who prints, and how?
7. **Supplier list.** Keep it in code, or move it to a sheet next to the others
   (`supplier-list-regional.xlsx` already exists as a review copy)?
8. **Silent fallbacks.** A failed translation keeps French text with no warning, and the verso
   cuts off overflowing text silently. Should both raise a review warning?
9. **Arrival text** is worded in code, but values from the sheet (e.g. the dinner note) stay
   in whatever language they were written in. Intended?
10. **Stale notes:** the "card map gap" sticky and the "LLM boundaries" mention of the arrival
    note — confirm both are out of date.
11. **Error workflow** `s8D9kJMLJCBJ8T8a` — what does it do (who gets alerted)?
12. **Dead nodes** (`Refuse: Wrong Password`, the pass-through *Attach Curated Supplier
    Entries*) — fine to drop?
13. **Fixed trip.** Drive file IDs point at one tour (*7 nuits Xonrupt*). Will other tours
    need different GPX zips / sleep lists per trip — i.e. should Trip ID choose the sources?
