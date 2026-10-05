# Conversion checklist — n8n workflow → app

> Deployed by the **n8n-to-app** skill. Each line below is **one agentic
> session**. It points to the skill file that drives that session. When the
> session is done: tick it, append `completed:DD/MM/YYYY` to the end of the
> line, and fill in the doc it produced. Example:
>
> `- [x] **Conversion research** — follow ... → output: docs/conversion-research.md  completed:09/06/2026`

**Workflow:** <name of the workflow being ported>
**Skill source:** `/root/.claude/skills/n8n-to-app` · https://github.com/calmmage/n8n-to-app-skill.git
**Started:** 05/10/2026

---

## Phases

- [x] **Scaffold repo** — run `scripts/scaffold.py` (skeleton: `AGENTS.md` stub, `make help` / `make run`, this checklist). Just run it.
      → output: repo skeleton  completed:05/10/2026
- [ ] **Conversion research** — follow `instructions/01-research.md` (one unified pass: what the workflow does, integrations, creds, triggers, data flow, n8n freebies)
      → output: `docs/conversion-research.md`
- [ ] **Port plan** — follow `instructions/02-plan.md` (migration mode: direct vs rework · node→code mapping · frontend choice)
      → output: `docs/port-plan.md`
- [ ] **Build** — follow `instructions/03-build.md`
      → output: working app + `make run` demo
  - [ ] Core logic — node→code per the plan
  - [ ] Production features *(Plan fills these in for this workflow — delete any that don't apply)*
    - [ ] Security — secrets/creds via env, dev vs prod isolation
    - [ ] Monitoring — failure notifications / healthcheck
    - [ ] Logs — run + error logging
    - [ ] Debug entry point — manual test / replay
  - [ ] Frontend *(only if chosen in the plan)*
- [ ] **Deploy & hand off** — follow `instructions/04-deploy.md` (pick target: manual / docker / cloud · finalize `AGENTS.md` + ongoing-work entry)
      → output: deployed app
- [ ] **Sanity check & review** — follow `instructions/05-review.md` (app-specific gaps · simplify/postpone to ship sooner · replace-with-agentic · clear `make help` entry point per direction)
      → output: `docs/review.md` + finalized `make help`
