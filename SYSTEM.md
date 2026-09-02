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
| Prod-API base-URL | `https://api.aduck.no` (CNAME til Heroku-appen; `aduck-eeb24b32f565.herokuapp.com` svarer fortsatt) | `aduck.sf/.../remoteSiteSettings/Aduck_API.remoteSite-meta.xml` + Apex-tester, `finnarild-django/finnarild/settings.py` |
| Kjerne-endpoint | `POST {base}/api/generate` — header `X-API-Key`, body `{config, payload, salesforce_org_id?}` | `aduck/src/api.rs`, `aduck/SALESFORCE.md` |
| Liveness | `GET {base}/api/feck` (uautentisert) | `aduck/src/api.rs` |
| Swagger UI | `{base}/` | `aduck/src/main.rs` |

### Kjente utdaterte referanser (denne fila overstyrer)

- `aduck/SALESFORCE.md` §1 er oppdatert til `https://api.aduck.no/api/generate` (HTTPS,
  custom domain på Heroku-appen). Det gamle self-hostede
  `http://finnarild.duckdns.org:3000` og Heroku-URL-en `aduck-eeb24b32f565.herokuapp.com`
  er historikk (sistnevnte svarer fortsatt).
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

2. **Admin sendes til registrering.** `Aduck Setup`-fanen (LWC `aduckSetup` +
   `AduckSetupController`) viser org-ID + sandbox-flagg og en knapp til:
   ```
   https://aduck.no/register/?org_id=<OrgId>[&sandbox=true]
   ```
   `<OrgId>` = `UserInfo.getOrganizationId()` (Apex) / `$Organization.Id` (Flow/LWC).
   `[IMPLEMENTERT — aduck.sf, uncommitted]` Django-ruten er nå `/register/` (§6), så
   lenken treffer. `[GAP]` LWC-en lenker ut, men limer ikke inn nøkkelen automatisk.

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

### Rust-siden `[IMPLEMENTERT — branch `feature/admin-key-api`]`

- `api_keys` har fått `quota_total INTEGER` — livstids antall transformeringer gitt
  (trial + alle kjøp), satt av Django. `None` = ingen kvote.
- `monthly_limit` beholdt som **valgfri** rate-limit (håndheves via
  `db::calls_this_month` i `check_api_key`, som før).
- Håndheving i `aduck/src/api.rs` `generate` (ikke `check_api_key`, se under): hvis
  `db::calls_total(key) >= quota_total` → `402`.
- **HTTP-status for oppbrukt kvote:** `402 Payment Required`, atskilt fra `401`
  (feil/manglende nøkkel) og `400` (org-mismatch). Håndhevet i handleren og ikke i
  `check_api_key`, nettopp fordi `SecurityScheme`-checkeren bare kan svare `401`.
  `aduck.sf/.../AduckTransformationService.cls` viser «kvoten er brukt opp, kjøp
  mer på aduck.no» på `402`.  `[IMPLEMENTERT — aduck.sf, uncommitted]`

### Django-siden `[GAP]`

- **Trial = 20, konfigurerbart** via Django-innstilling `ADUCK_TRIAL_TRANSFORMS = 20`
  (eller en `SiteConfig`-rad hvis det skal endres uten redeploy). **Aldri** hardkodet
  i Rust.
- Lisens → kvote: Django kjenner «lisens X = Y transformeringer», regner ut totalen og
  PATCH-er Rust. Rust vet ingenting om lisenser eller priser.

---

## 5. Rust admin-API `[IMPLEMENTERT — branch `feature/admin-key-api`]`

Alle krever `X-API-Key: <ADUCK_API_KEY>` (admin-nøkkelen). En vanlig kundenøkkel
avvises med `401`. Uten databasetilkobling svarer de `503`.

**Django lager selv nøkkelverdien** (som den lager kontonøkler) og sender den i
`api_key`-feltet. Rust genererer den ikke — den bare lagrer og håndhever.

| Metode & path | Body / query | Svar |
|---|---|---|
| `POST /api/keys` | `{api_key, salesforce_org_id?, label?, quota_total?, monthly_limit?}` | `200` `KeyInfo` |
| `GET /api/keys/{api_key}` | – | `200` `KeyInfo` / `404` |
| `PATCH /api/keys/{api_key}` | `{quota_total?, active?, label?}` (utelatt felt = uendret) | `200` `KeyInfo` / `404` |
| `GET /api/usage?key=<api_key>` | – | `200` `UsageSummary` / `404` |

- `KeyInfo` = `{api_key, salesforce_org_id, monthly_limit, quota_total, active, used_total, used_this_month}`
- `UsageSummary` = `{api_key, quota_total, used_total, used_this_month, events: [{salesforce_org_id, template_bytes, duration_ms, created_at}]}` (siste 100, nyeste først; `created_at` = unix-sekunder UTC)

Implementert i:
- `aduck/src/api.rs` — `KeyAdmin` `#[OpenApi]`-struct, registrert i `main.rs`
  ved siden av `Generate` og `Health`. Gjenbruker `ApiKeyAuth` + `require_admin`.
- `aduck/src/db.rs` — `create_key`, `update_key`, `calls_total`, `recent_usage`;
  `ApiKeyRecord` + `api_keys`-skjemaet fikk `quota_total` (med idempotent
  `ALTER TABLE` for eksisterende databaser).

---

## 6. Django-siden `[IMPLEMENTERT — branch `feature/aduck-accounts`]`

Modeller (`finnarild-django/aduck/models.py`):

- **`Account`** — `OneToOneField(User)`, `registration_key_hash` (Django `make_password`),
  `org_limit` (default `3`), `created_at`. `generate_registration_key()` gir rånøkkelen
  én gang; `verify_key(raw)` slår opp. **Merk:** `verify_key` scanner alle `Account` og
  kjører `check_password` per rad — O(n) med dyr hashing. Greit nå; bytt til et
  prefiks-/lookup-skjema om brukertallet vokser.
- **`OrgRegistration`** — `account` FK, `salesforce_org_id` (unik), `is_sandbox`,
  `api_key` (per-org-nøkkelen, lagret i **klartekst** — lav verdi, kan tilbakekalles via
  Rust admin-API; kommentert i koden), `label`, `created_at`.
- **`Purchase`** — `account` FK, `transforms`, `stripe_session_id`, `paid_at`, `created_at`.
  Stripe-webhook er en TODO-stub. `total_quota(account)` = `ADUCK_TRIAL_TRANSFORMS` +
  sum av betalte kjøp.
- **`AccessRequest`** — beholdt for «be om tilgang»-skjemaet på `pricing/`.

**Django lager per-org-nøkkelen selv** (`'aduck_' + secrets.token_urlsafe(32)`) og sender
den som `api_key` i `POST /api/keys`. Rust genererer den ikke.

Klient mot Rust admin-API: `finnarild-django/aduck/aduck_api.py`
(`create_key` / `update_key` / `get_usage`, `AduckApiError`). Forventer at
`GET /api/usage` gir feltene `used_total`, `used_this_month`, `quota_total`, `events`
(matcher `UsageSummary` i §5).

Views (`finnarild-django/aduck/views.py`):
- `register` — oppretter `User` + `Account`, logger inn, viser rånøkkelen én gang
  (`registered.html`); bærer `?org_id=` videre.
- `register_org` (login_required) — håndhever `org_limit`, avviser org registrert på
  annen konto, idempotent for samme konto, kaller `aduck_api.create_key(...)` med
  `quota_total = total_quota(account)`, viser Base URL + `Api_Key__c`.
- `account_dashboard` — henter forbruk per org via `aduck_api.get_usage`, hver i
  try/except så én feil ikke velter siden.

Ruting: `finnarild/urls.py` inkluderer **ikke** `aduck.urls` — `VirtualHostMiddleware`
setter `request.urlconf = 'aduck.urls'` for `aduck.no`. Ruter: `/register/` (var
`/accounts/register/`, flyttet for å matche §3.2) og `/register/org/`. `register`-viewet
sender allerede innloggede kontoer rett videre til `register_org` med query-strengen
intakt (sandbox-flyten, §3.6). Fikset samtidig: `LoginView` fikk `next_page` (kun gyldig
for `LogoutView`), som fikk hele `aduck.urls` til å feile ved import.

Innstillinger (`finnarild/settings.py`): `ADUCK_API_BASE_URL`, `ADUCK_ADMIN_API_KEY`,
`ADUCK_TRIAL_TRANSFORMS` (env-drevet). Migrasjon `0002` ikke kjørt.

**Gjenstår:** Sidemaler er norske, mens `base.html`-chrome er engelsk. Migrasjon `0002`
ikke kjørt, ikke deployet.

---

## 7. Salesforce-siden

- **`Aduck_Api_Setting__c`** (protected hierarchy custom setting) med `Base_URL__c` og
  `Api_Key__c`. Leses av `AduckTransformationService.generate()`. Settes **manuelt**
  i dag. Målbilde: registreringsflyten (§3.5) produserer akkurat dette paret; brukeren
  limer det inn.
- **`salesforce_org_id` i requesten:** `GenerateRequest` i `aduck/src/api.rs` tar et
  valgfritt `salesforce_org_id`. Når per-org-nøkkelen har en registrert org, avvises
  mismatch med `400 OrgMismatch`. `AduckTransformationService` sender nå
  `UserInfo.getOrganizationId()` i hver `/api/generate`-body.
  `[IMPLEMENTERT — aduck.sf, uncommitted]`
- **402-håndtering:** `AduckTransformationService` har en egen gren for `402` med en
  brukervendt «kvote oppbrukt, kjøp mer på aduck.no»-melding.
  `[IMPLEMENTERT — aduck.sf, uncommitted]`
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
| `ADUCK_PUBLIC_URL` | nei | OpenAPI/Swagger `server`-URL. Satt til `https://api.aduck.no/api` i prod. Uten den: `http://{bind}/api` (kun nyttig lokalt). |
| `ADUCK_ALLOWED_CIDR_FILE` | nei | IPv4 CIDR-allowlist (`aduck.heroku/allowed_cidrs.txt`). **Ikke satt i prod nå** — slått av så Django (dynamiske Heroku-dyno-IP-er) når admin-API-et; auth er da kun API-nøklene. Hvis den slås på igjen: siste ledd i `X-Forwarded-For` sjekkes, så ingen proxy/CDN kan stå foran `api.aduck.no`. |

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

> **Status 2026-09-02:** steg 1–3 implementert og pushet på hvert repos `main`/`master`.
> Rust-API-et er **deployet** (Heroku-app `aduck`, release v17) og svarer på
> `https://api.aduck.no` (§1). IP-allowlisten er slått av (§8). Gjenstår før
> konto-/kvoteflyten virker ende-til-ende: `finnarild` mangler config-varene, Django
> er ikke deployet, migrasjon `0002` ikke kjørt, `aduck.sf` ikke deployet til en org.
> Se «Neste» nederst.

| # | Gap | Blokkerer |
|---|---|---|
| 1 | ~~Rust provisjonerings-endpoint~~ **gjort + deployet** — merget til `aduck` `main` (`d150acb`), bygd `x86_64-unknown-linux-musl --no-default-features --features postgres` på maskinen, release v15. | – |
| 2 | ~~`quota_total` i `api_keys`~~ **gjort + deployet** — samme (§4). Skjemaendring kjøres ved oppstart; ren oppstart i loggen v15. | – |
| 3 | ~~Django `Account` / `OrgRegistration` / `Purchase` + views + dashboard~~ **gjort**, merget til `master` (`9dff702`, `49fc685`). Migrasjon `0002` ikke kjørt; ikke deployet; config-varene ikke satt på `finnarild`. | Konto-/kvoteflyt |
| 4 | ~~Ingen registreringslenke/LWC i `aduck.sf`; Django-rute-mismatch~~ **gjort** — `Aduck Setup`-fane/LWC (`aduck.sf` `c2d8a4a`), Django-rute `/register/` (§3.2, §6). | – |
| 5 | Kontonøkkel-format og -lagring ikke bestemt. Anbefaling: `secrets.token_urlsafe(32)`, lagret hashet, vist én gang. | §6. |
| 6 | ~~402 for oppbrukt kvote~~ **gjort** — Rust (deployet) + `aduck.sf` `AduckTransformationService` (`c2d8a4a`, ikke deployet til org ennå). | – |
| 7 | Auth mellom Django og Rust er kun den delte admin-nøkkelen (`ADUCK_API_KEY`). IP-allowlisten er av (§8). Godtatt for nå. | – |
| 8 | ~~`aduck/SALESFORCE.md` §1 utdatert URL~~ **gjort** (`92806c2`). `finnarild-django/docs/aduck-ecosystem.md` har fortsatt Windows-stier og gammel struktur, men endpoint-notatene er rettet. | Dokumentasjonssamsvar. |
| 9 | `aduck.sf` er umanagd — ingen én-klikks install-lenke (§7). | AppExchange / enkel install. |
| 10 | Betaling: Stripe-integrasjon i Django ikke påbegynt. | Kjøp av flere transformeringer. |

### Anbefalt rekkefølge for implementasjon

1. ~~Rust: `quota_total` + admin-API~~ — **gjort + deployet** (release v17).
2. ~~Django: `Account` + kontonøkkel + `register_org` + `account_dashboard`~~ — **gjort**, på `master`. Gjenstår: se «Neste».
3. ~~`aduck.sf`: registreringslenke + `salesforce_org_id` i body + 402-håndtering; foren Django-ruten; prod-API på `api.aduck.no`~~ — **gjort**, på `main`. Gjenstår: `sf project deploy start` mot en org + Apex-testkjøring.
4. Django: Stripe + `Purchase.paid_at` + webhook som kaller `PATCH /api/keys` (§3.9).
5. `aduck.sf`: managed 2GP-pakke for install-lenke (§7).

### Neste (plukk opp her)

1. **`finnarild` config-varer:** `heroku config:set ADUCK_ADMIN_API_KEY=<`aduck`-appens `ADUCK_API_KEY`> -a finnarild`. `ADUCK_API_BASE_URL` faller tilbake til `https://api.aduck.no` i koden, men kan settes eksplisitt.
2. **Deploy Django:** `git push heroku master` fra `finnarild-django/`, så `heroku run python manage.py migrate -a finnarild` (migrasjon `0002`).
3. **Verifiser** konto-dashbordet mot `api.aduck.no` (`/api/keys`, `/api/usage`) — skal ikke lenger gi 403 (allowlist av).
4. **`aduck.sf` → org:** `sf project deploy start` + `sf apex run test`, sett `Aduck_Api_Setting__c.Base_URL__c = https://api.aduck.no` i orgen.
5. Deretter gap 5 (kontonøkkel-lagring) og gap 10 (Stripe).
