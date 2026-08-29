# aduck — systemkontrakt mellom de fire prosjektene

Dette dokumentet er den **kanoniske** beskrivelsen av hvordan de fire aduck-repoene
henger sammen: registrerings-, nøkkel- og kvoteflyten. Der en verdi eller et navn
finnes her og i et delprosjekts egen dokumentasjon, er **denne fila fasit**.

Skrevet 2026-08-29. Delprosjektenes egne kontrakter (spesielt `aduck/SALESFORCE.md`)
er fortsatt autoritative for det de dekker (malsyntaks, config-tre, feiltabell).

> **Status:** dette er et **målbilde**. Deler er implementert i dag, deler ikke.
> Se §9 for hva som mangler. Hver seksjon markerer `[FINNES]` / `[GAP]` der det er
> relevant.

---

## 1. De fire delene

| Mappe | Rolle | Remote | Deploy |
|---|---|---|---|
| `aduck/` | Rust-API. Fyller en Word-mal fra et datatre og returnerer ferdig `.docx`. Eier API-nøkler og kvote. | `github.com:FinnArild/aduck` | bygg → kopier binær til `aduck.heroku/` |
| `aduck.heroku/` | Deploy-artefakt: den kompilerte binæren + `allowed_cidrs.txt` + `dockerfile` + `heroku.yml`. Ingen kildekode. | egen (Heroku git) | `git push heroku main` |
| `aduck.sf/` | Salesforce-pakke (SFDX, umanagd). Lar en admin mappe SObject-data til mal-plassholdere og kaller Rust-API-et. | egen | `sf project deploy start` |
| `finnarild-django/` | Nettsidene. `aduck`-appen (registrering, hjelp, pris, konto) serveres på `aduck.no`. Eier brukere og betaling. | Heroku (`finnarild`) | `git push heroku master` |

Modermappen `/home/finn/Documents/code/aduck/` er et tynt meta-repo som **bare**
sporer denne dokumentasjonen. De fire undermappene er egne git-repoer og er
git-ignorert her.

### Kanoniske verdier

| Ting | Verdi | Kilde |
|---|---|---|
| Registreringsside | `https://aduck.no/` | `finnarild-django/finnarild/virtualhostmiddleware.py` (`aduck.no` → `aduck.urls`) |
| Prod-API base-URL | `https://aduck-eeb24b32f565.herokuapp.com` | `aduck.sf/.../remoteSiteSettings/Aduck_API.remoteSite-meta.xml` + Apex-tester |
| Kjerne-endpoint | `POST {base}/api/generate` — header `X-API-Key`, body `{config, payload, salesforce_org_id?}` | `aduck/src/api.rs`, `aduck/SALESFORCE.md` |
| Liveness | `GET {base}/api/feck` (uautentisert) | `aduck/src/api.rs` |
| Swagger UI | `{base}/` | `aduck/src/main.rs` |

### Kjente utdaterte referanser (denne fila overstyrer)

- `aduck/SALESFORCE.md` §1 oppgir endpoint som `http://finnarild.duckdns.org:3000/api/generate`.
  Det var det gamle self-hostede oppsettet. Nå: `https://aduck-eeb24b32f565.herokuapp.com`
  (HTTPS, Heroku). `aduck.sf` er allerede migrert; `SALESFORCE.md` er ikke oppdatert.
- `finnarild-django/docs/aduck-ecosystem.md` beskriver økosystemet fra Django-appens
  ståsted, med utdaterte DuckDNS-notater og Windows-stier (`c:\Users\micro\...`).
  Den erstattes av denne fila som «oversikt over hvordan bitene henger sammen».
  Behold den bare hvis den fortsatt er nyttig som hjelpe-innhold-notat, og pek den hit.

---

## 2. To-nøkkel-modellen — kjernen i koblingen

Det finnes **to** slags nøkler. Å blande dem sammen er den vanligste feilkilden.

### Registreringsnøkkel (kontonøkkel) `[GAP]`

- Utstedes av **Django**, én per Django-konto (`auth.User`).
- Sendes **aldri** til Rust-API-et.
- Eneste bruk: på `aduck.no` for å autorisere at samme konto registrerer **flere
  Salesforce-orger** — inkludert sandboxer — uten å måtte gå gjennom betaling/oppsett
  på nytt.
- Lagres **hashet** i Django. Vises til brukeren **én gang** ved opprettelse.
- Format: anbefalt ugjennomsiktig tilfeldig streng, ≥ 32 bytes (`secrets.token_urlsafe(32)`).

### Per-org API-nøkkel `[DELVIS]`

- Én per Salesforce-org (prod eller sandbox).
- Ligger i Rust `api_keys`-tabellen (`aduck/src/db.rs`), knyttet til `salesforce_org_id`.
- Limes inn i Salesforce: `Aduck_Api_Setting__c.Api_Key__c` (sammen med `Base_URL__c`).
- Opprettes ved at **Django** kaller Rust sitt admin-endpoint (§5) — brukeren lager
  den aldri selv.
- `[FINNES]` i dag: tabellen, oppslag (`db::lookup_key`), org-sjekk, aktiv/inaktiv,
  `monthly_limit`. `[GAP]`: endepunktet som oppretter dem.

### Hemmeligheten brukeren ikke har

= Rust **admin-nøkkelen** `ADUCK_API_KEY` (env-var i `aduck/`, obligatorisk — tjenesten
nekter å starte uten den). Kun **Django-serveren** holder den (som `ADUCK_ADMIN_API_KEY`).

Konsekvens: brukeren kan self-serve registrere orger på kontonøkkelen sin, men bare
Django (med admin-hemmeligheten) kan faktisk opprette nøkler eller endre kvote i Rust.
Kontonøkkelen alene gir ingen tilgang til transformerings-API-et.

```
Bruker  ──kontonøkkel──▶  Django (aduck.no)  ──ADUCK_ADMIN_API_KEY──▶  Rust /api/keys
                                │
Salesforce-org  ──per-org API-nøkkel──▶  Rust /api/generate
```

---

## 3. Ende-til-ende-flyt

1. **Admin installerer `aduck.sf`-pakken** i Salesforce-orgen sin
   (`sf project deploy start` → `sf org assign permset -n Aduck_User`).
   `[GAP]` én-klikks install: krever managed 2GP-pakke, se §7.

2. **Admin sendes til registrering.** Pakkens README, eller en setup-LWC, lenker til:
   ```
   https://aduck.no/register/?org_id=<OrgId>[&sandbox=true]
   ```
   `<OrgId>` = `UserInfo.getOrganizationId()` (Apex) / `$Organization.Id` (Flow/LWC).
   `[GAP]` denne lenken/LWC-en finnes ikke i pakken ennå.

3. **Django: konto.** Bruker registrerer seg eller logger inn (`views.register`
   `[FINNES]` — bruker `UserCreationForm`; login/logout `[FINNES]`). Ved første gangs
   bruk opprettes `Account` med `registration_key`, og kontonøkkelen vises. `[GAP]`

4. **Django kaller Rust** `POST /api/keys` med admin-hemmeligheten:
   `{salesforce_org_id: <OrgId>, label: "<konto> / <org>", quota_total: ADUCK_TRIAL_TRANSFORMS}`
   → får per-org API-nøkkelen tilbake. `[GAP]`

5. **Django viser admin** `Base URL` + `API Key` å lime inn i
   Setup → Custom Settings → `Aduck_Api_Setting__c` → Manage. `[GAP]` (siden finnes som
   tom `account_dashboard`).

6. **Sandbox:** admin er allerede innlogget, oppgir kontonøkkelen (eller er i samme
   nettleser-sesjon), går til `register/?org_id=<sandbox-org-id>&sandbox=true`.
   Django sjekker `Account.org_limit` og kaller Rust `POST /api/keys` på nytt →
   ny per-org-nøkkel på **samme** `Account`. `[GAP]`

7. **Bruk akkumuleres.** Hver vellykket `POST /api/generate` logges i Rust
   `usage_events` (`api_key`, `salesforce_org_id`, `template_bytes`, `duration_ms`,
   `created_at`). `[FINNES]` — `db::record_usage`.

8. **Dashboard.** `aduck.no/account/` kaller Rust `GET /api/usage` for hver av
   kontoens org-nøkler og viser brukt / gjenstående / historikk. `[GAP]`

9. **Kjøp mer.** Stripe checkout i Django (krever `auth.User`) → `Purchase` lagres →
   Django `PATCH /api/keys/<key>` setter ny `quota_total` = trial + sum av kjøp. `[GAP]`

---

## 4. Kvote og trial

**Rust håndhever. Django konfigurerer.**

### Rust-siden `[GAP: quota_total]`

- `api_keys` utvides med `quota_total INTEGER` — livstids antall transformeringer gitt
  (trial + alle kjøp), satt av Django.
- `monthly_limit` beholdes som **valgfri** rate-limit (finnes allerede, håndheves via
  `db::calls_this_month`).
- Håndheving i `aduck/src/api.rs` `check_api_key`: hvis
  `db::calls_total(key) >= quota_total` → avvis kallet.
- **HTTP-status for oppbrukt kvote:** bruk `402 Payment Required`, atskilt fra `401`
  (feil/manglende nøkkel) og `400` (org-mismatch). Da kan
  `aduck.sf/.../classes/AduckTransformationService.cls` vise «kvoten er brukt opp,
  kjøp mer på aduck.no» i stedet for en generisk feil.
  Beslutning: **402**. (Alternativ vurdert: 401 — forkastet, ikke skillbar fra feil nøkkel.)

### Django-siden `[GAP]`

- **Trial = 20, konfigurerbart** via Django-innstilling `ADUCK_TRIAL_TRANSFORMS = 20`
  (eller en `SiteConfig`-rad hvis det skal endres uten redeploy). **Aldri** hardkodet
  i Rust.
- Lisens → kvote: Django kjenner «lisens X = Y transformeringer», regner ut totalen og
  PATCH-er Rust. Rust vet ingenting om lisenser eller priser.

---

## 5. Rust admin-API (nytt) `[GAP]`

Alle krever `X-API-Key: <ADUCK_API_KEY>` (admin). Implementeres i:
- `aduck/src/api.rs` — ny `KeyAdmin` `#[OpenApi]`-struct, registreres i `main.rs`
  ved siden av `Generate` og `Health`.
- `aduck/src/db.rs` — nye funksjoner: `create_key`, `update_key`, `get_key`,
  `usage_summary`, `calls_total`.

| Metode & path | Body / query | Svar |
|---|---|---|
| `POST /api/keys` | `{salesforce_org_id, label, quota_total, monthly_limit?}` | `{api_key}` |
| `PATCH /api/keys/{api_key}` | `{quota_total?, active?, label?}` | oppdatert record |
| `GET /api/keys/{api_key}` | – | record + `{used}` |
| `GET /api/usage?key=<api_key>` | – | `{used, quota_total, monthly_used, events: [...]}` |

Gjenbruk:
- `constant_time_eq` + admin-grenen i `check_api_key` (`aduck/src/api.rs`) for auth.
- `db::connect`s `CREATE TABLE IF NOT EXISTS api_keys (...)` — legg til `quota_total`.
- `db::calls_this_month` som mal for `calls_total` (samme spørring uten
  `created_at >=`-filteret).

---

## 6. Django-modeller (nytt) `[GAP]`

I `finnarild-django/aduck/models.py` (i dag: kun `AccessRequest`):

- **`Account`** — `OneToOneField(User)`, `registration_key` (hashet),
  `org_limit` (default f.eks. `3`), `created_at`.
- **`OrgRegistration`** — `account` FK, `salesforce_org_id` (unik), `is_sandbox` (bool),
  `api_key` (per-org-nøkkelen fra Rust, eller bare en referanse hvis den ikke skal
  lagres i klartekst), `created_at`.
- **`Purchase`** — `account` FK, `transforms` (int), `stripe_session_id`, `paid_at`.
- **`AccessRequest`** — behold for «be om tilgang»-skjemaet på `pricing/`, eller
  pensjoner når self-serve er live.

Views (`finnarild-django/aduck/views.py`):
- `register` `[FINNES]` — utvid til å opprette `Account` + kontonøkkel.
- Ny `register_org` — tar `org_id` + `sandbox`, sjekker kontonøkkel/`org_limit`,
  kaller Rust `POST /api/keys`, viser Base URL + API-nøkkel.
- `account_dashboard` `[FINNES, tom]` — koble til Rust `GET /api/usage`.

Ruting: `finnarild-django/finnarild/urls.py` inkluderer **ikke** `aduck.urls`.
`VirtualHostMiddleware` setter `request.urlconf = 'aduck.urls'` for `aduck.no`.
Ny ruting legges derfor i `finnarild-django/aduck/urls.py`.

Innstillinger (`finnarild-django/finnarild/settings.py`):
`ADUCK_API_BASE_URL`, `ADUCK_ADMIN_API_KEY`, `ADUCK_TRIAL_TRANSFORMS`, Stripe-nøkler.

---

## 7. Salesforce-siden

- **`Aduck_Api_Setting__c`** (protected hierarchy custom setting) med `Base_URL__c` og
  `Api_Key__c`. Leses av `AduckTransformationService.generate()`. Settes **manuelt**
  i dag. Målbilde: registreringsflyten (§3.5) produserer akkurat dette paret; brukeren
  limer det inn.
- **`salesforce_org_id` i requesten:** `GenerateRequest` i `aduck/src/api.rs` tar et
  valgfritt `salesforce_org_id`. Når per-org-nøkkelen har en registrert org, avvises
  mismatch med `400 OrgMismatch`. `aduck.sf` bør sende `UserInfo.getOrganizationId()`
  i hver `/api/generate`-body.  `[GAP i aduck.sf]`
- **402-håndtering:** `AduckTransformationService` kaster i dag `AduckTransformationException`
  på alt som ikke er `200 + status:"Ok"`. Legg til en egen gren for `402` med en
  brukervendt «kvote oppbrukt»-melding.  `[GAP]`
- **Én-klikks install:** pakken er `"namespace": ""`, umanagd, ingen install-lenke.
  Krever namespace-registrering + 2GP-pakkeversjon. Eget spor, ute av scope her.

---

## 8. Konfigurasjon per tjeneste

### `aduck/` (Rust-API)

| Env-var | Påkrevd | Betydning |
|---|---|---|
| `ADUCK_API_KEY` | ja | Admin-/fallback-nøkkel. Tjenesten starter ikke uten. |
| `DATABASE_URL` | nei | Postgres (Heroku). Faller tilbake til `sqlite://aduck.db?mode=rwc`. DB er ikke-fatal: uten den godtas kun `ADUCK_API_KEY`. |
| `PORT` / `ADUCK_BIND` | nei | `PORT` → `0.0.0.0:$PORT` (Heroku-stil). Ellers `ADUCK_BIND` (default `127.0.0.1:3000`). |
| `ADUCK_ALLOWED_CIDR_FILE` | nei | IPv4 CIDR-allowlist (Salesforce-IP-ranges). `aduck.heroku/allowed_cidrs.txt`. |

Bygg for release/Heroku: `x86_64-unknown-linux-musl`,
`cargo build --release --no-default-features --features postgres` (ren Rust
Postgres-driver; `sqlite`-feature krever C-kompilator og er dev-only på Windows/MSVC).

### `finnarild-django/`

`ADUCK_API_BASE_URL`, `ADUCK_ADMIN_API_KEY`, `ADUCK_TRIAL_TRANSFORMS`,
Stripe-nøkler (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, …).

### Databaser

Rust-DB og Django-DB er **separate**. Eneste kobling mellom dem er admin-HTTP-API-et
(§5). Ingen delt skjema, ingen delt tilkobling.

---

## 9. Åpne spørsmål / gap

| # | Gap | Blokkerer |
|---|---|---|
| 1 | Rust har ingen provisjonerings-endpoint (§5 er ubygd). | Hele self-serve-flyten. |
| 2 | `quota_total` finnes ikke i `api_keys` (§4). | Trial og kjøp. |
| 3 | Django `Account` / `OrgRegistration` / `Purchase` finnes ikke (§6). | Kontonøkkel, sandbox-registrering, dashboard. |
| 4 | Ingen registreringslenke/LWC i `aduck.sf` (§3.2). | Onboarding-flyt. |
| 5 | Kontonøkkel-format og -lagring ikke bestemt. Anbefaling: `secrets.token_urlsafe(32)`, lagret hashet, vist én gang. | §6. |
| 6 | 402 vs 401 for oppbrukt kvote — **besluttet: 402** (§4). `aduck.sf` må håndtere den (§7). | Feilmelding til sluttbruker. |
| 7 | Ingen auth mellom Django og Rust utover delt admin-nøkkel. Godtatt for nå. | – |
| 8 | `aduck/SALESFORCE.md` og `finnarild-django/docs/aduck-ecosystem.md` har utdaterte URL-er / stier (§1). | Dokumentasjonssamsvar. |
| 9 | `aduck.sf` er umanagd — ingen én-klikks install-lenke (§7). | AppExchange / enkel install. |
| 10 | Betaling: Stripe-integrasjon i Django ikke påbegynt. | Kjøp av flere transformeringer. |

### Anbefalt rekkefølge for implementasjon (egne planer)

1. Rust: `quota_total` + admin-API (§5, §4). Uten dette kan ingenting annet testes ende-til-ende.
2. Django: `Account` + kontonøkkel + `register_org`-view som kaller Rust (§6, §3.3–3.5).
3. Django: `account_dashboard` mot `GET /api/usage` (§3.8).
4. `aduck.sf`: registreringslenke + `salesforce_org_id` i body + 402-håndtering (§7).
5. Django: Stripe + `Purchase` + `PATCH /api/keys` (§3.9).
6. `aduck.sf`: managed 2GP-pakke for install-lenke (§7).
