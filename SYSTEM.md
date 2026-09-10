# aduck — systemkontrakt mellom prosjektene

Dette dokumentet er den **kanoniske** beskrivelsen av hvordan aduck-repoene
henger sammen: registrerings-, nøkkel-, kvote- og lead-flyten. Der en verdi eller
et navn finnes her og i et delprosjekts egen dokumentasjon, er **denne fila fasit**.

Skrevet 2026-08-29 (CRM-leg lagt til 2026-09-10). Delprosjektenes egne kontrakter
(spesielt `aduck/SALESFORCE.md`) er fortsatt autoritative for det de dekker
(malsyntaks, config-tre, feiltabell).

> **Status:** dette er et **målbilde**. Deler er implementert i dag, deler ikke.
> Se §9 for hva som mangler. Hver seksjon markerer `[FINNES]` / `[GAP]` der det er
> relevant.

---

## 1. Delene

| Mappe | Rolle | Remote | Deploy |
|---|---|---|---|
| `aduck/` | Rust-API. Fyller en Word-mal fra et datatre og returnerer ferdig `.docx`. Eier API-nøkler og kvote. | `github.com:FinnArild/aduck` | bygg → kopier binær til `aduck.heroku/` |
| `aduck.heroku/` | Deploy-artefakt: den kompilerte binæren + `allowed_cidrs.txt` + `dockerfile` + `heroku.yml`. Ingen kildekode. | egen (Heroku git) | `git push heroku main` |
| `aduck.sf/` | Salesforce-**pakke** (SFDX, umanagd) som *kundene* installerer i egne orger. Mapper SObject-data til mal-plassholdere og kaller Rust-API-et. | egen | `sf project deploy start` |
| `finnarild-django/` | Nettsidene. `aduck`-appen (registrering, hjelp, pris, konto) serveres på `aduck.no`. Eier brukere og betaling. Pusher Leads til CRM-orgen. | Heroku (`finnarild`) | `git push heroku master` |
| `sfdx/` | Finn Arilds **egen** Salesforce-org (Developer Edition) — CRM. Aduck-kunder havner her som **Leads** (§3.10). Har allerede Person Accounts + `BatchLeadConvert`. Ikke det samme som `aduck.sf`. | `github.com:FinnArild/sfdx` | GitHub Actions (JWT) / manuelt |

Modermappen `/home/finn/Documents/code/aduck/` er et tynt meta-repo som **bare**
sporer denne dokumentasjonen. Undermappene er egne git-repoer og er git-ignorert her.

### Kanoniske verdier

| Ting | Verdi | Kilde |
|---|---|---|
| Registreringsside | `https://aduck.no/` | `finnarild-django/finnarild/virtualhostmiddleware.py` (`aduck.no` → `aduck.urls`) |
| Prod-API base-URL | `https://api.aduck.no` (CNAME til Heroku-appen; `aduck-eeb24b32f565.herokuapp.com` svarer fortsatt) | `aduck.sf/.../remoteSiteSettings/Aduck_API.remoteSite-meta.xml` + Apex-tester, `finnarild-django/finnarild/settings.py` |
| Kjerne-endpoint | `POST {base}/api/generate` — header `X-API-Key`, body `{config, payload, salesforce_org_id?}` | `aduck/src/api.rs`, `aduck/SALESFORCE.md` |
| Liveness | `GET {base}/api/feck` (uautentisert) | `aduck/src/api.rs` |
| Swagger UI | `{base}/` | `aduck/src/main.rs` |
| CRM-org (Leads) | Salesforce Developer Edition, login `https://login.salesforce.com`, kilde i `sfdx/`. Django autentiserer med JWT bearer flow mot en connected app. | `sfdx/`, `finnarild-django/aduck/crm.py` `[GAP]` |

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
   `[FINNES]` — `RegistrationForm` = `UserCreationForm` + påkrevd e-post + navn;
   login/logout `[FINNES]`). Ved første gangs bruk opprettes `Account` med
   `registration_key`, kontonøkkelen vises, og en Lead pushes til CRM (§10). `[GAP]`

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

10. **CRM-lead.** Rett etter at `Account` opprettes (steg 3) pusher Django en **Lead**
    til CRM-orgen (`sfdx/`) via Salesforce REST — best-effort, blokkerer aldri
    registrering. Idempotent på ekstern ID `aduck_Account_Id__c`. Django lagrer
    `Account.crm_lead_id`. Etterslep tas av en management command. `[GAP]` — se §10.

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
  `company`, `org_limit` (default `3`), `created_at`, `crm_lead_id` / `crm_synced_at`
  (§10). `generate_registration_key()` gir rånøkkelen
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
`ADUCK_TRIAL_TRANSFORMS`, `SF_CRM_*` (§8, §10) — alt env-drevet.

**Gjenstår:** Sidemaler er norske, mens `base.html`-chrome er engelsk. Migrasjonene
(`0002`–`0004`) ikke kjørt, ikke deployet.

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

CRM (§10): `SF_CRM_LOGIN_URL` (`https://login.salesforce.com`), `SF_CRM_CLIENT_ID`
(connected app consumer key), `SF_CRM_USERNAME` (integrasjonsbruker), og RSA-nøkkelen
som **enten** `SF_CRM_JWT_KEY` (PEM som config var) **eller** `SF_CRM_JWT_KEY_ENC` +
`SF_CRM_JWT_KEY_PASSPHRASE` (openssl `-aes-256-cbc -pbkdf2`, base64). Aldri committet.
Uten disse virker registrering som før, bare uten lead-push.

### `sfdx/` (CRM-org)

Ingen kjøretids-config her — deploy-hemmeligheter (`server.key`, consumer key,
`DECRYPT_KEY`) ligger som GitHub Actions secrets. Merk: `server.key` er i dag
committet i klartekst — bør roteres.

### Databaser / datalagre

Tre separate lagre: Rust-DB (`api_keys`, `usage_events`), Django-DB (`Account`,
`OrgRegistration`, `Purchase`), CRM-orgen (`Lead`/`Account` i Salesforce). Eneste
koblinger: Django → Rust admin-HTTP-API (§5), og Django → CRM Salesforce REST (§10).
Ingen delt skjema, ingen delt tilkobling.

---

## 9. Åpne spørsmål / gap

> **Status 2026-09-10:** steg 1–3 + CRM-lead-flyten (§10) implementert og pushet.
> Rust-API-et er **deployet** (Heroku-app `aduck`, release v17) på `https://api.aduck.no`
> (§1); IP-allowlisten av (§8). CRM-metadata er deployet til `finnarild-dev-ed`;
> Django-koden er verifisert ende-til-ende mot den orgen men **ikke deployet**.
> Gjenstår før noe virker i prod: `finnarild` mangler alle config-varene
> (`ADUCK_ADMIN_API_KEY`, `SF_CRM_*`), Django er ikke deployet, migrasjonene `0002`–`0004` ikke kjørt, `aduck.sf` ikke deployet til en org. Se «Neste» nederst.

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
| 11 | ~~CRM/lead-flyt (`sfdx/`)~~ **bygd + verifisert**, ikke deployet (§10). `sfdx` `5087a40`, `finnarild-django` `a418b2c`. Gjenstår: Django-connected-app + `SF_CRM_*` + deploy. | Kundeoppfølging / salg. |
| 12 | `sfdx/server.key` er en committet privat nøkkel (JWT). **Ikke brukt** — Django/CLI bruker en fersk nøkkel (`~/.config/sf-jwt/` på janeway). Bør fortsatt fjernes + `.gitignore`. | Sikkerhet. |
| 13 | ~~Registreringsskjemaet samler ikke e-post/firma~~ **gjort** — `RegistrationForm` (`finnarild-django` `7f16aab`, `b8ece55`): e-post (påkrevd, unik) + firma (påkrevd, `Account.company`, migrasjon `0004`) + navn (valgfritt). | – |

### Anbefalt rekkefølge for implementasjon

1. ~~Rust: `quota_total` + admin-API~~ — **gjort + deployet** (release v17).
2. ~~Django: `Account` + kontonøkkel + `register_org` + `account_dashboard`~~ — **gjort**, på `master`. Gjenstår: se «Neste».
3. ~~`aduck.sf`: registreringslenke + `salesforce_org_id` i body + 402-håndtering; foren Django-ruten; prod-API på `api.aduck.no`~~ — **gjort**, på `main`. Gjenstår: `sf project deploy start` mot en org + Apex-testkjøring.
4. Django: Stripe + `Purchase.paid_at` + webhook som kaller `PATCH /api/keys` (§3.9).
5. `aduck.sf`: managed 2GP-pakke for install-lenke (§7).

### Neste (plukk opp her)

1. **`finnarild` config-varer:** `heroku config:set ADUCK_ADMIN_API_KEY=<`aduck`-appens `ADUCK_API_KEY`> -a finnarild`. `ADUCK_API_BASE_URL` faller tilbake til `https://api.aduck.no` i koden, men kan settes eksplisitt.
2. **Deploy Django:** `git push heroku master` fra `finnarild-django/`, så `heroku run python manage.py migrate -a finnarild` (migrasjonene `0002`–`0004`).
3. **Verifiser** konto-dashbordet mot `api.aduck.no` (`/api/keys`, `/api/usage`) — skal ikke lenger gi 403 (allowlist av).
4. **`aduck.sf` → org:** `sf project deploy start` + `sf apex run test`, sett `Aduck_Api_Setting__c.Base_URL__c = https://api.aduck.no` i orgen.
5. **CRM-lead (§10):** Django-connected-app i `sfdx`-orgen + integrasjonsbruker, `SF_CRM_*` på `finnarild`, deploy Django + migrasjonene.
6. Deretter gap 5 (kontonøkkel-lagring), gap 10 (Stripe), gap 13 (e-post/firma i registreringsskjemaet).

---

## 10. CRM / lead-flyt `[IMPLEMENTERT — ikke deployet]`

Når noen registrerer seg på `aduck.no` blir de også en **Lead** i Finn Arilds egen
Salesforce-org (`sfdx/`), for oppfølging og salg. Django er den eneste som snakker
med CRM-orgen. Rust og `aduck.sf` er ikke involvert.

**Status 2026-09-10:** kode + Salesforce-metadata bygd og verifisert ende-til-ende
mot `finnarild-dev-ed` (JWT-mint, create+update-upsert idempotent, `sync_missing_leads`,
kryptert-nøkkel-varianten). Gjenstår: connected app for Django (helst egen
integrasjonsbruker), `SF_CRM_*` på `finnarild`, deploy Django + migrasjonene.

### Prinsipper

- **Best-effort.** `crm.CrmError` logges og svelges i `register()` — registrering
  fullfører alltid.
- **Idempotent.** Ekstern ID `aduck_Account_Id__c` på `Lead` = Django `Account.pk`.
  `PATCH /sobjects/Lead/aduck_Account_Id__c/<pk>` (upsert) — ekstern ID ligger i
  URL-en, **ikke** i body (Salesforce avviser det ellers).
- **Etterslep.** `Account.crm_lead_id` + `crm_synced_at`; `python manage.py
  sync_missing_leads` (cron/Heroku Scheduler) tar de som feilet. `--all` re-synker alle.
- **Ingen nøkkel i repo.** `SF_CRM_JWT_KEY` (PEM som Heroku config var) **eller**
  `SF_CRM_JWT_KEY_ENC` + `SF_CRM_JWT_KEY_PASSPHRASE` (openssl `-aes-256-cbc -pbkdf2`,
  base64 — samme format som `aduck.sf` CI sin `server.key.enc`; `crm.py` dekrypterer
  i minne).

### Auth: JWT bearer flow (`aduck/crm.py`)

1. Connected app i `sfdx`-orgen: «Use digital signatures» (cert), scopes `api` +
   `refresh_token`, «Admin approved users are pre-authorized».
   `[GAP]` — CLI-en bruker i dag appen **«aduck JWT»** (auth som `finnarild@`);
   Django bør få en **egen** connected app + integrasjonsbruker med bare
   permission set `Aduck_Integration`, så en lekket nøkkel bare kan røre Leads.
2. `crm._mint_token()` bygger RS256-JWT (`iss`=consumer key, `sub`=`SF_CRM_USERNAME`,
   `aud`=`SF_CRM_LOGIN_URL`) → `POST /services/oauth2/token`
   (`grant_type=…jwt-bearer`). Token caches i prosess (~50 min, re-mint ved 401).

### Bygd i `sfdx/` (deployet til `finnarild-dev-ed`)

- `Lead.aduck_Account_Id__c` — Text(64), **External ID**, Unique.
- `Lead.aduck_Trial_Transforms__c` — Number(9,0).
- `Lead.Salesforce_Org_Ids__c` — LongTextArea (org-id-ene; §3.6-flyten fyller den `[GAP]`).
- `LeadSource` picklist-verdi `aduck.no`.
- Permission set **`Aduck_Integration`** (Lead CRUD + FLS på feltene). **Må tildeles**
  brukeren Django auth-er som — nye felt er ellers usynlige (SOQL: «No such column»).
  Tildelt `finnarild@` nå.

### Bygd i `finnarild-django/` (branch `master`, `a418b2c` / `7f16aab` / `b8ece55`)

- `aduck/crm.py` — `is_configured()`, `upsert_lead(*, external_id, last_name, company,
  email, first_name, trial_transforms)`, `sync_account(account)`. `CrmError` ikke-fatal.
- `Account.crm_lead_id` + `crm_synced_at` (migrasjon `0003`), `Account.company` (`0004`).
- `aduck/forms.py` `RegistrationForm` — e-post (påkrevd, unik) + firma (påkrevd) + navn.
- `register()`-hook (best-effort), `sync_missing_leads` management command.
- `settings.py`: `SF_CRM_LOGIN_URL` / `SF_CRM_CLIENT_ID` / `SF_CRM_USERNAME` /
  `SF_CRM_JWT_KEY`(`_ENC`/`_PASSPHRASE`) (§8). `PyJWT[crypto]` i `requirements.txt`.

### Lead-felt som sendes

| Lead-felt | Verdi |
|---|---|
| `LastName` | `User.last_name`, ellers `User.username` |
| `Company` | `Account.company` (påkrevd i `RegistrationForm`); `"(ukjent)"` for eldre kontoer |
| `Email` | `User.email` (påkrevd i `RegistrationForm`) |
| `FirstName` | `User.first_name` hvis satt |
| `LeadSource` | `"aduck.no"` |
| `aduck_Trial_Transforms__c` | `ADUCK_TRIAL_TRANSFORMS` |

### Gjenstår

1. `sfdx/`: lag Django sin connected app (+ integrasjonsbruker + `Aduck_Integration`),
   noter consumer key. Dokumentér i `sfdx/README.md`.
2. `finnarild`: `heroku config:set SF_CRM_CLIENT_ID=… SF_CRM_USERNAME=…
   SF_CRM_JWT_KEY="$(cat key.pem)"` (eller `_ENC`/`_PASSPHRASE`).
3. `git push heroku master` + `heroku run python manage.py migrate`.
4. Verifiser: registrer testkonto på `aduck.no` → Lead med `LeadSource=aduck.no`.
5. Senere: e-post/firma i skjemaet; `Salesforce_Org_Ids__c` i §3.6; Lead-konvertering
   ved første betaling (gap 10 / Stripe).
