# aduck (meta)

Modermappe for de fire aduck-prosjektene. Dette repoet sporer **bare**
koblingsdokumentasjonen — de fire undermappene er egne git-repoer (git-ignorert her).

| Mappe | Rolle | Remote |
|---|---|---|
| [`aduck/`](aduck/) | Rust-API: fyller en Word-mal fra et datatre, returnerer ferdig `.docx`. Eier API-nøkler og kvote. | `github.com:FinnArild/aduck` |
| [`aduck.heroku/`](aduck.heroku/) | Deploy-artefakt: kompilert binær + `allowed_cidrs.txt` + `dockerfile`. | Heroku git |
| [`aduck.sf/`](aduck.sf/) | Salesforce-pakke (SFDX, umanagd) som kaller API-et. | egen |
| [`finnarild-django/`](finnarild-django/) | Nettsidene. `aduck`-appen (registrering, konto, hjelp) på `aduck.no`. Eier brukere og betaling. | Heroku (`finnarild`) |

## Logisk flyt

Bruker installerer `aduck.sf` → sendes til `aduck.no` for registrering → får en
per-org API-nøkkel knyttet til Salesforce-org-id-en → trial gir 20 gratis
transformeringer (konfigurerbart) → bruker ser forbruk på `aduck.no` og kjøper mer →
Rust-API-et teller hvert kall.

**Full kontrakt: [`SYSTEM.md`](SYSTEM.md).**

## Jobbe på tvers

```
scripts/pull-all.sh      # git pull i alle fire
```

Hvert delprosjekt har sin egen `README` / `claude.md` / `SALESFORCE.md`. Når du jobber
inne i `aduck/`, gjelder `aduck/claude.md` (minimal-inngripen-reglene).
