# aduck (meta)

Modermappe for de fem aduck-prosjektene. Dette repoet sporer **bare**
koblingsdokumentasjonen — undermappene er egne git-repoer (git-ignorert her).

| Mappe | Rolle | Remote |
|---|---|---|
| [`aduck/`](aduck/) | Rust-API: fyller en Word-mal fra et datatre, returnerer ferdig `.docx`. Eier API-nøkler og kvote. | `github.com:FinnArild/aduck` |
| [`aduck.heroku/`](aduck.heroku/) | Deploy-artefakt: kompilert binær + `allowed_cidrs.txt` + `dockerfile`. | Heroku git |
| [`aduck.sf/`](aduck.sf/) | Salesforce-**pakke** (SFDX, umanagd) som *kundene* installerer i egne orger. | egen |
| [`finnarild-django/`](finnarild-django/) | Nettsidene. `aduck`-appen (registrering, konto, hjelp) på `aduck.no`. Eier brukere og betaling. | Heroku (`finnarild`) |
| [`sfdx/`](sfdx/) | Finn Arilds **egen** Salesforce-org (CRM). Kunder havner her som Leads via Django. | `github.com:FinnArild/sfdx` |

## Logisk flyt

Bruker installerer `aduck.sf` → sendes til `aduck.no` for registrering → Django
oppretter konto **og en Lead i CRM-orgen (`sfdx/`)** → bruker får en per-org
API-nøkkel knyttet til Salesforce-org-id-en → trial gir 20 gratis transformeringer
(konfigurerbart) → bruker ser forbruk på `aduck.no` og kjøper mer → Rust-API-et
teller hvert kall.

**Full kontrakt: [`SYSTEM.md`](SYSTEM.md).**

## Jobbe på tvers

```
scripts/pull-all.sh      # git pull i alle delrepoene
```

Hvert delprosjekt har sin egen `README` / `claude.md` / `SALESFORCE.md`. Når du jobber
inne i `aduck/`, gjelder `aduck/claude.md` (minimal-inngripen-reglene).
