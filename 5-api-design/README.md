# API design: Week 2

## Check the spec

```sh
npx --yes @redocly/cli@latest lint 5-api-design/openapi.yaml
npx --yes @stoplight/spectral-cli@6 lint 5-api-design/openapi.yaml --ruleset 5-api-design/.spectral.yaml
```

`--ruleset` is not optional. Spectral resolves `.spectral.yaml` relative to the working
directory, not to the document. Run from the repo root with the ruleset in this directory
and Spectral fails with *"No ruleset has been found"*. That message reads like a missing
file. The file is present. The path is wrong.

Neither tool is installed. Both run through `npx`.

## Files

| File | What it is |
| --- | --- |
| `openapi.yaml` | The contract. OpenAPI 3.0.3, single file. |
| `DECISIONS.md` | The cross-cutting calls every operation inherits, in Chose / Gave up / Why form. |
| `REVIEW.md` | Claude's findings per review round, tagged and decided. |
| `.spectral.yaml` | Spectral ruleset. Exists because v6 refuses to run without one. |

The deliverable is `openapi.yaml`: a contract for the T-Shirt Store API, written against
ERD commit `8d47aae` on `challenge/erd`. Week 3 implements it.

## Decisions about the toolchain

**The warnings stay.** Do not silence them with placeholder data. Measured 2026-08-21 with
all 36 operations authored: Redocly reports 0 errors and 2 warnings. Spectral reports 0
errors and 1 warning. Re-measure before you quote either number.

The two tools ask for different `info` fields. Redocly asks for `license` and Spectral asks
for `contact`. Neither applies to coursework. `no-server-example.com` is correct, because
the server really is localhost. The other 8 warnings name unused components, which is the
authoring checklist rather than a defect.

**3.0.3, not 3.1.** `@nestjs/swagger` emits 3.0.0, so staying on 3.0 keeps Week 3's
generated document diffable against this one and the diff reports drift rather than a
version shift. The concrete tell is nullability: 3.0 spells it `nullable: true`, 3.1
spells it `type: [string, "null"]`, and Nest generates the 3.0 form. The classic
`editor.swagger.io` is also reliable on 3.0.x.

**Single file, not a `$ref`-split tree.** The Swagger editor cannot resolve external
refs, so a split spec means bundling before every paste.

**`oasdiff` is a Week 3 need and is not on npm.** It is a Go tool. `npx oasdiff` reaches
a security placeholder, not the tool.
