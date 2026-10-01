# aduck — betaling (plan)

Skrevet 2026-10-01. **Plan, ikke implementert.** Svarer på gap 10 i `SYSTEM.md` §9.
Kvoteflyten (`SYSTEM.md` §4) gjelder uendret: Rust håndhever, Django konfigurerer.

---

## 1. Avgjør først: pakker eller abonnement

- **Koden i dag** er bygd for forhåndsbetalte pakker: hvert betalte `Purchase` legges til
  `quota_total` (livstidsantall dokumenter), via `total_quota()` i
  `finnarild-django/aduck/models.py`.
- **Prissiden** (`templates/aduck/pricing.html`) snakker om «a monthly call allowance».
  Det stemmer ikke med modellen.

**Anbefaling: pakker** (f.eks. 100 / 500 / 2000 dokumenter).

- Én pakke = én engangsbetaling hos PayPal. Ingen fornyelser som kan feile.
- Forutsigbar kostnad for bedriftskunder.
- Abonnement kan komme senere. Rust har allerede `monthly_limit` (teller kalendermåned,
  ikke faktureringsperiode) som et abonnement kunne sette.

Når dette er bestemt, skal prissiden skrives om til å matche.

---

## 2. Felles kjerne (uavhengig av betalingsleverandør)

Bygges først, slik at PayPal, faktura og senere Stripe/Vipps alle går gjennom samme vei.

**`Purchase`-modellen** (migrasjon `0005`): erstatt `stripe_session_id` med

| Felt | Innhold |
|---|---|
| `provider` | `paypal` / `invoice` / `stripe` / `vipps` |
| `provider_order_id` | ordre-/sesjons-ID hos leverandøren |
| `provider_capture_id` | betalings-ID (brukes ved refusjon) |
| `amount`, `currency` | beløp og valuta som faktisk ble belastet |
| `refunded_at` | satt ved refusjon/tilbakeføring |

**Én funksjon, `apply_payment(purchase)`:**

1. Setter `paid_at` (gjør ingenting hvis den allerede er satt, så den tåler å bli kalt
   to ganger).
2. Regner ut `total_quota(account)` og kaller `aduck_api.update_key(api_key,
   quota_total=…)` for hver `OrgRegistration` på kontoen.

Alle leverandører, webhooks og en «Merk som betalt»-handling i Django admin kaller denne.

**Refusjon:** sett `refunded_at`. `total_quota()` teller ikke refunderte kjøp, og den nye
totalen synkes til Rust. Er kunden allerede over, svarer Rust `402`.

**Rust trenger ingen endringer** — `PATCH /api/keys/{key}` finnes (§5 i `SYSTEM.md`).

**Forutsetning:** ingenting av dette hjelper før registreringen virker i prod —
`ADUCK_ADMIN_API_KEY` er ikke satt på `finnarild`, og migrasjonene må kjøres
(«Neste» i `SYSTEM.md` §9). Det kommer først.

---

## 3. PayPal (Orders API v2, capture på serveren)

Finn Arild har PayPal-konto. Flyt for en pakke:

1. Innlogget bruker velger pakke på kontosiden. Django lager et `Purchase` uten `paid_at`.
2. Django kaller `POST /v2/checkout/orders`: intent `CAPTURE`, beløp i NOK, beskrivelse
   («500 aduck-dokumenter»), og `Purchase.pk` i `custom_id`. Lagrer ordre-ID-en.
3. PayPal sin JS-knapp på aduck.no åpner PayPal. Når kjøperen godkjenner, poster nettleseren
   til Django.
4. Django kaller `POST /v2/checkout/orders/{id}/capture`, sjekker at status er `COMPLETED`
   og at beløp, valuta og `custom_id` stemmer med kjøpet, og kaller `apply_payment()`.
5. **Webhook som reserve** (`/paypal/webhook/`), i tilfelle nettleseren lukkes midt i:
   - `PAYMENT.CAPTURE.COMPLETED` → `apply_payment()`
   - `PAYMENT.CAPTURE.REFUNDED`, `PAYMENT.CAPTURE.REVERSED` → merk som refundert
   - Hver hendelse verifiseres med `POST /v1/notifications/verify-webhook-signature`
     (headerne fra kallet + vår webhook-ID).

**Oppsett:**

- Ingen SDK — `requests` finnes i `requirements.txt`. OAuth-token via client credentials
  (`POST /v1/oauth2/token`), cachet til det utløper.
- Heroku-config på `finnarild`: `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`,
  `PAYPAL_WEBHOOK_ID`, `PAYPAL_ENV` (`sandbox` / `live`).
- Bygg og test alt i PayPal sandbox (testbedrift + testkjøper) før `live`.

**Avgifter og risiko** (sjekk PayPals norske avgiftsside før lansering):

- Fast 3,90 NOK per transaksjon pluss en prosentsats. Tvist: 140 NOK.
- PayPal holder av og til tilbake penger for nye forhandlerkontoer.
- Finn ut tidlig om kjøpere uten PayPal-konto kan betale med kort gjennom PayPal.

---

## 4. Faktura, MVA og EHF

PayPal gir kjøperen en kvittering, ikke en faktura.

- **MVA:** norske bedriftskunder trenger faktura med 25 % MVA når aduck er
  MVA-registrert (plikt over 50 000 NOK omsetning på 12 måneder).
- **EHF fra 1. januar 2027:** B2B-fakturaer må sendes som EHF/Peppol når mottakeren kan
  ta imot dem. PDF-faktura holder ikke lenger.
- **Utenlandske bedriftskunder:** tjenester til utenlandske bedrifter er normalt uten
  norsk MVA. Bekreft med regnskapsfører.
- **Løsning:** et regnskapssystem med API (Fiken, Tripletex o.l.) som sender EHF-faktura
  merket som betalt når `apply_payment()` kjører.
- **Organisasjonsnummer:** samle det inn ved kjøp. `Account.company` finnes; legg
  org.nr. ved siden av.

---

## 5. Andre betalingsmåter

| Alternativ | Passer fordi | Pass på | Innsats |
|---|---|---|---|
| **Faktura / bankoverføring** | Bedrifter foretrekker det ofte. EHF trengs uansett fra 2027. | Du må følge opp sene betalinger. Kjente kunder kan få kvoten når fakturaen sendes. | Liten: «Betal med faktura»-skjema + «Merk som betalt» i admin, senere automatisk fra regnskapssystemet |
| **Stripe Checkout** | Datamodellen var tenkt for Stripe. Beste utvikleropplevelse: hostet betalingsside, fakturaer, MVA-håndtering, abonnement, kundeportal, Apple/Google Pay. | Vipps via Stripe er fortsatt i lukket forhåndsvisning. | Middels |
| **Vipps MobilePay** | Den vanligste betalingsmåten i Norge. ePayment-API: videresending til Vipps, bekreftelse via webhook. | Krever forhandleravtale og org.nr. Mindre vanlig for bedriftskjøp. | Middels |
| **AppExchange Checkout** | Salesforce-kunder kjøper gjennom egen innkjøpsprosess, lisenser via Salesforce. Henger sammen med én-klikks install (gap 9). | Salesforce tar 15 % + $0,30 per kortbetaling. Krever managed 2GP-pakke og $999 sikkerhetsgjennomgang. | Stor, langsiktig |
| **Paddle / Lemon Squeezy** | Blir selger overfor kunden og håndterer internasjonal MVA. | Høyere avgifter. Fakturaen utstedes i deres navn — passer kanskje dårlig med norsk EHF. | Middels |

---

## 6. Anbefalt rekkefølge

1. Felles kjerne (§2) og at registreringen virker i prod.
2. PayPal-pakker + «betal med faktura» via admin-handlingen. Dekker både kortkjøpere og
   bedrifter som vil ha faktura.
3. Regnskapssystem med EHF før 2027.
4. Stripe hvis kortvolumet vokser eller abonnement blir aktuelt.
5. Vipps hvis norske småbedrifter spør etter det.
6. AppExchange når managed-pakken finnes.

---

## 7. Beslutninger som mangler

- Pakker eller abonnement.
- Pakkestørrelser og priser.
- Valuta: bare NOK, eller NOK og EUR.
- Er aduck (Finn Arild) MVA-registrert?
- Regnskapssystem for EHF.

---

## Kilder

- PayPal Orders API: https://developer.paypal.com/api/rest/integration/orders-api/
- PayPal webhook-hendelser: https://developer.paypal.com/api/rest/webhooks/event-names
- Verifisering av webhook: https://docs.paypal.ai/reference/api/rest/verify-webhook-signature/verify-webhook-signature
- PayPal-avgifter: https://www.paypal.com/us/business/paypal-business-fees
- Stripe i Norge: https://stripe.com/resources/more/payments-in-norway
- Vipps MobilePay ePayment: https://developer.vippsmobilepay.com/docs/APIs/epayment-api/quick-start/
- EHF/B2B e-faktura 2027: https://sovos.com/regulatory-updates/company/norway-2027-b2b-e-invoicing-proposal/
- AppExchange Checkout revenue share: https://developer.salesforce.com/docs/atlas.en-us.packagingGuide.meta/packagingGuide/appexchange_checkout_rev_share.htm
