# API design: Week 2

The deliverable is `openapi.yaml`: a contract for the T-Shirt Store API, written against
ERD commit `8d47aae` on `challenge/erd`. Week 3 implements it.

## Files

| File | What it is |
| --- | --- |
| `openapi.yaml` | The contract. OpenAPI **3.0.3**, single file. |
| `DECISIONS.md` | The cross-cutting calls every operation inherits, in Chose / Gave up / Why form. |
| `REVIEW.md` | Claude's findings per review round, tagged and verdicted. |
| `.spectral.yaml` | Spectral ruleset. Exists because v6 refuses to run without one. |

## Checking it

```sh
npx --yes @redocly/cli@latest lint 5-api-design/openapi.yaml
npx --yes @stoplight/spectral-cli@6 lint 5-api-design/openapi.yaml --ruleset 5-api-design/.spectral.yaml
```

`--ruleset` is not optional here. Spectral resolves `.spectral.yaml` **relative to the
working directory**, not to the document it is linting, so running from the repo root
with the ruleset in this directory fails with *"No ruleset has been found"*, which reads
like a missing file rather than a path-resolution rule. Writing the flag down beats
rediscovering that.

Neither tool is installed; both run through `npx`. `oasdiff` is a Go tool and is not on
npm. `npx oasdiff` reaches a security placeholder, not the tool. It is a Week 3 need.

Three warnings are left standing rather than silenced with placeholder data:
`info-license` and `info-contact` (coursework, not a published API) and
`no-server-example.com` (the server really is localhost). Zero errors.

## Why 3.0.3 and not 3.1

`@nestjs/swagger` emits `3.0.0`, so staying on 3.0 keeps Week 3's generated document
diffable against this one, so the diff reports drift rather than a version shift. The
concrete tell is nullability: 3.0 spells it `nullable: true`, 3.1 spells it
`type: [string, "null"]`, and Nest generates the 3.0 form. The classic
`editor.swagger.io` is also reliable on 3.0.x.
