# Instruksjoner for Claude — aduck meta-repo

Denne mappen samler fire **uavhengige** git-repoer. Meta-repoet her sporer kun
dokumentasjonen som binder dem sammen (`SYSTEM.md`).

## De fire repoene

| Mappe | Hva | Remote | Deploy |
|---|---|---|---|
| `aduck/` | Rust-API (`poem`/`poem-openapi`). Eier `api_keys` + `usage_events`. | `github.com:FinnArild/aduck` | bygg → kopier binær til `aduck.heroku/aduck` → push |
| `aduck.heroku/` | Kun deploy-artefakt (binær + `allowed_cidrs.txt` + `dockerfile` + `heroku.yml`). | Heroku git | `git push heroku main` |
| `aduck.sf/` | Salesforce SFDX-pakke, umanagd. | egen | `sf project deploy start` |
| `finnarild-django/` | Django-sider. `aduck`-appen på `aduck.no` (via `finnarild/virtualhostmiddleware.py`). | Heroku (`finnarild`, branch `master`) | `git push heroku master` |

## Regler

1. **`SYSTEM.md` er fasit** for endpoints, URL-er, nøkkelmodell og kvoteflyt. Oppdater
   den når kontrakten mellom prosjektene endres.
2. **Pull alle fire** før kryssrepo-arbeid: `scripts/pull-all.sh`.
3. **Hvert repo committes for seg** til sitt eget remote. Ikke lag commits på tvers.
   Meta-repoet committes bare når dokumentasjonen her endres.
4. Når du jobber **inne i `aduck/`**: `aduck/claude.md` gjelder (minimal diff, ikke
   refaktorer uoppfordret, ikke legg til features/tester/dokumentasjon uten å bli bedt).
5. **Rust-API-et eier nøkler og kvote.** Django er bruker-/betalingslag som kaller Rust
   via admin-HTTP-API-et. Ingen delt database.
6. Rust-release bygges for `x86_64-unknown-linux-musl` med
   `--no-default-features --features postgres` (ikke `sqlite` — krever C-kompilator).

## Kanoniske verdier (se SYSTEM.md §1 for full liste)

- Registreringsside: `https://aduck.no/`
- Prod-API: `https://aduck-eeb24b32f565.herokuapp.com`
- Kjerne-endpoint: `POST {base}/api/generate`, header `X-API-Key`
