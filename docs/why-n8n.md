# Why this workflow stays on n8n

**Decision (05/10/2026):** the *Bike Tours Vosges – Travel-File AI Agent* stays on n8n.
It is not being rewritten as a standalone app.

This document explains why. It uses the research in
[`conversion-research.md`](conversion-research.md): what the workflow actually does,
and what a standalone app would have to rebuild to do the same thing.

---

## The short version

Most of this workflow's logic (GPX parsing, shortcut detection, HTML rendering) is
already **plain JavaScript in Code nodes**. Porting that part would be easy. What is hard
to port is everything **around** the code: pausing a run for days while waiting for a
human, serving pages from inside that run, Google OAuth, hosting, retries, logs. n8n gives
all of that for free. A standalone app would have to build, host, secure and maintain it.

So n8n already gives the best of both: **real code where it's needed, a managed platform
for everything else.**

---

## Reasons, from strongest to weakest

### 1. The Wait node: a run that pauses for days and resumes where it left off
**In this workflow:** each day is emailed to Sofie. The run then **stops and waits**
(*Wait for Review Click*, *Wait for Review Page*) until she clicks *Approve* or sends the
review form. That can be hours or days, once per day of the trip, inside **one**
execution. When it resumes, every earlier node's data is still there (`$('Prepare Review
Email').item`, the HTML files, the review records collected so far).

**A standalone app would need:**
- a database to save the state of every trip in progress (current day, built HTML, review
  records), because a normal program forgets everything when it restarts;
- a **state machine** (started → waiting for day 3 → day 3 approved → …) and code that
  rebuilds the context after each click;
- secure, **signed** approve/review links that can't be guessed or reused (n8n adds the
  `signature` to `$execution.resumeUrl` automatically);
- handling for double clicks, old links and two reviewers clicking at once (in n8n this is
  the *Link For This Day?* / *Show 'Old Link' Page* logic, which only works because n8n
  owns the waiting).

This is the single biggest piece of work a rewrite would add, and the easiest place to
introduce bugs.

### 2. Serving web pages from inside the run (Respond to Webhook)
**In this workflow:** the review page with its form, the "approved", "noted" and "old link"
pages are all sent by *Respond to Webhook* nodes from **the paused run itself**.

**A standalone app would need:** a web server with routes for each page, templates, form
handling, and a link between "this HTTP request" and "this trip's state in the database".

### 3. Public HTTPS hosting, always on
**In this workflow:** the buttons in Sofie's email must reach the workflow from anywhere,
at any time, for days. n8n Cloud is always online at a public HTTPS address.

**A standalone app would need:** a server or cloud service running 24/7, a domain, a TLS
certificate, restarts after crashes, OS and security updates. Running it on a laptop
doesn't work: the links break when the laptop sleeps.

### 4. Google OAuth for Drive and Gmail, with automatic token refresh
**In this workflow:** 5 Drive downloads, 3 Drive uploads and 2 Gmail sends use n8n's
stored OAuth2 credentials. n8n refreshes the tokens on its own.

**A standalone app would need:** a Google Cloud project, an OAuth consent screen, storing
and refreshing tokens securely, and handling expired or revoked tokens. Gmail **sending**
is a sensitive Google scope, so an app outside n8n can hit extra Google verification
steps. With n8n this is a few clicks in *Credentials*.

### 5. The hosted form with password protection
**In this workflow:** *New Trip Confirmed (Form)* is a ready-made web form (Trip ID,
language, days to build) behind HTTP Basic Auth.

**A standalone app would need:** a small front end plus login handling, or a command-line
tool that Sofie wouldn't use.

### 6. Ready-made integration nodes
**In this workflow:** Google Drive, Gmail, Anthropic (Claude), Compression (unzip),
Extract From File (xlsx), HTTP Request (QuickChart). That's 6 integrations with no
libraries to install or keep up to date.

**A standalone app would need:** a library and glue code for each one, plus upgrades when
those libraries or APIs change.

### 7. Retries and "continue on error", per node, without code
**In this workflow:** the Drive uploads retry 3× with 2 s between tries. The QuickChart
calls are set to *continue on error*, so the email falls back to a lighter image instead of
failing.

**A standalone app would need:** retry and fallback code written and tested by hand.

### 8. Execution history: see exactly what happened on every run
**In this workflow:** when day 4 of a trip looks wrong, you can open that execution and see
the input and output of **every node** (the parsed tracks, the matched suppliers, the LLM
answer before and after parsing). This is the kind of view that exposes bugs like the v4
language bug (noted in *Target Language != FR?*).

**A standalone app would need:** logging written on purpose, somewhere to store the logs,
and a way to view them. Even then you would not see the data at every step unless you
built that too.

### 9. Error workflow: alerts when something fails
**In this workflow:** an error workflow is attached in the settings, so every failed run
starts it automatically (that's where alerts go).

**A standalone app would need:** monitoring and alerting set up separately.

### 10. The canvas is the documentation, and non-developers can follow it
**In this workflow:** the flow (sources → per-day loop → review → upload → to-do list) is
visible on one screen. Sticky notes record the decisions (*v5 route variants*, *LLM
boundaries*). Node names are written for people ("Send Guide + Card to Sofie for Review").
The to-do email even refers to nodes by name (*"Parse Curated Supplier List node"*), so
Sofie knows where a fix goes.

**A standalone app:** the same knowledge would live in source files and a README, readable
only by a developer.

### 11. Fast changes when the rules change
**In this workflow:** the rules changed within days: the v4 scope correction (20 Sept), then
v5 with three route variants (24 Sept). Each change was made by editing a few nodes
and running again.

**A standalone app:** every change means edit, test, commit, deploy.

### 12. Code nodes remove n8n's usual weakness
A common argument against low-code tools is that they can't handle complex logic. This
workflow shows the opposite: about **1,200 lines of JavaScript in 23 Code nodes** do the
heavy parts (shortcut detection with a grid index, elevation gain with 3 m hysteresis,
SVG maps, multilingual HTML). n8n doesn't limit the logic. It just stops you from having to
write the plumbing.

### 13. Maintainability: the right tool for the person maintaining it
The person maintaining this workflow learned n8n in class. A standalone app in Python or
Node.js would need someone who can maintain a web server, a database, OAuth and
deployments. Picking the platform the maintainer knows lowers the risk that nobody can fix
it later.

### 14. Small scale, so platform costs stay low
This is a tool for one small tour company: a trip at a time, a handful of emails per day.
That fits comfortably within n8n Cloud. A standalone app would still need its own
always-on hosting, database and monitoring, which cost money and time even when idle.

---

## In one table

| Needed by this workflow | n8n | Standalone app |
|---|---|---|
| Pause for days per day, resume with all data | Wait node | Database + state machine + resume logic |
| Signed approve/review links | `$execution.resumeUrl` | Token signing + validation |
| Review pages + form | Respond to Webhook | Web server, routes, templates |
| Public, always-on HTTPS | n8n Cloud | Server/hosting, domain, TLS, updates |
| Drive + Gmail OAuth | Credentials (auto refresh) | Google Cloud project, token storage/refresh, verification |
| Start form with password | Form Trigger + Basic Auth | Front end + auth |
| Unzip, xlsx, Drive, Gmail, Claude, QuickChart | Built-in nodes | Libraries + glue code |
| Retries / fallback | Node settings | Hand-written code |
| See every run's data per step | Execution history | Logging + log storage + viewer |
| Failure alerts | Error workflow | Monitoring/alerting setup |
| Docs readable by non-developers | Canvas + sticky notes | README + code |

---

## What n8n costs you (the honest side)

Staying on n8n is the right call here, but it has trade-offs:

- **Workarounds for platform limits.** The form can't host the review pages directly, so
  the workflow posts to **its own webhook** to start a background run. The Code-node
  sandbox has no xlsx library, so *Extract From File* nodes read the sheets.
- **Copy-pasted code.** The label tables and SVG map/profile code are duplicated in the
  three *Build … HTML* nodes. The review texts are duplicated in three more nodes. A fix
  must be made in every copy.
- **No automated tests** for the Code nodes; testing means running the workflow.
- **Version control is weak.** The workflow is one large JSON file, which is hard to compare
  between versions (keep regular exports).
- **Tied to the platform.** If n8n's pricing or features change, moving away later is the
  big job described in [`conversion-research.md`](conversion-research.md).

---

## Worth fixing while staying on n8n

These came up during the research. None of them requires leaving n8n:

1. **Hard-coded secret.** The `x-btv-key` value is typed in plain text in *Start Trip in
   Background*. Select the existing *Header Auth* credential in that HTTP Request node
   instead, and **rotate the key** (it appears in every export).
2. **Waits never time out.** Set a wait limit on both Wait nodes, or send a reminder, so a
   forgotten review doesn't leave the run open forever.
3. **Silent translation failure.** *Parse Translate Response* sets `translationFailed` but
   nothing reads it. Add it to the day's warnings so it shows in the review email.
4. **Duplicate files in Drive on re-runs.** Uploads always create new files. Search for the
   existing file first and update it instead.
5. **Dead nodes.** *Refuse: Wrong Password* isn't connected. *Attach Curated Supplier
   Entries For This Day* only passes data through. Both can be removed.
6. **Supplier list in code.** Moving it to a sheet (like the other three sources) lets Sofie
   edit it without opening the workflow.
7. **Out-of-date sticky notes.** *Card map gap* (the recto already draws a map from the GPX)
   and *LLM boundaries* (the arrival note is no longer translated).
