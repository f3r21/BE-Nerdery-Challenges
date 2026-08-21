# Review rounds

Claude attacking the contract, and what I did about it. Three rounds, a fresh session each,
because the session that wrote the document already believes the assumptions that produced
the hole.

Every finding carries a tag. Untagged findings do not enter the ledger.

| Tag | Means | Who decides |
| --- | --- | --- |
| `[SPEC]` | Required or forbidden by OpenAPI 3.0.3 | I verify it against `spec.openapis.org/oas/v3.0.3` before accepting |
| `[CONVENTION]` | Common practice, with a named source | I weigh it |
| `[TASTE]` | Claude's preference | Rejectable without argument |

Verdict column: `applied`, `rejected`, or `deferred` with the reason. A finding with no
verdict has not been decided yet.

---

## Round 1, 2026-08-19

**Scope.** The shared component layer and one placeholder operation, 251 lines. Deliberately
run before the other operations are authored: a flaw in `Problem` or `PageMeta`
propagates into every one of them, so it is cheaper to find here than on Friday.

**Lenses run**, from `Week 2 - REST Design + NestJS Foundations.md:264-267`: missing status
codes and inconsistent pagination and error shapes; is it understandable, not just valid;
where is the same idea expressed two ways; and whether the document does what
`DECISIONS.md` says it does.

### Ledger

| # | Tag | Finding | Verdict | Reasoning | Commit |
| --- | --- | --- | --- | --- | --- |
| R1-1 | `[SPEC]` | Item 2 cited RFC 7807. RFC 9457 obsoletes it, and the two differ on whether `type` is required. | applied | Verified against the RFC index before accepting. The successor also supplies the `about:blank` rule that R1-2 depends on. | `a3f1eb7` |
| R1-2 | `[SPEC]` | `Problem` listed `type` in `required`. RFC 9457 defines an absent `type` as `about:blank`, meaning the status code carries the whole story, so a 404 or a 429 has no member to name. | applied | Making it required would force a type URI onto every problem, which defeats the point of minting them only where the status code cannot separate two failures. | `8da03a5` |
| R1-3 | `[SPEC]` | `Problem.type` was a bare `$ref` with a sibling `description`. OpenAPI 3.0.3 ignores every sibling of a `$ref`, so the description would not have rendered. | applied | Wrapped in `allOf`, which is the 3.0 idiom for a `$ref` that needs a sibling keyword. | `ba14f7f` |
| R1-4 | `[CONVENTION]` | Item 5's own date-range example used an inclusive `to` of `2026-08-31T23:59:59Z`, contradicting the half-open rule stated three lines above it. | applied | The example was the trap the rule exists to prevent. August is now `from=2026-08-01T00:00:00Z&to=2026-09-01T00:00:00Z`. | `a3f1eb7` |
| R1-5 | `[SPEC]` | The problem kinds were prose in `DECISIONS.md` and free strings in the schema, so each operation could invent its own spelling. | applied | Closed as an enum in `components/schemas/ProblemType`, which makes the linter enforce the set across every operation. | `ba14f7f` |
| R1-6 | `[CONVENTION]` | Item 1 attributed "adding an enum value is a breaking change" to the brief's breaking-change table. The table does not say it. | applied | The claim is true and the source was wrong. Rewritten in the first person as my own reading, which is where it belonged. | `ede7219` |
| R1-7 | `[CONVENTION]` | Item 7 said CASL's natural failure is `ForbiddenException`, which is 403. | applied | Measured rather than assumed: `@casl/ability` throws its own `ForbiddenError`, whose prototype chain is `Error -> Object` with no `.status` and no `.getStatus()`. It is not a Nest `HttpException`, so an uncaught one renders as 500, not 403. Two mappings are needed in Week 3, not one. | `ede7219` |

### The hole

Round 1 found no missing endpoint or response shape, because at 251 lines there was one
placeholder operation and nothing to be missing from. What it found instead was a class of
defect worth naming: **four of the seven findings are citation failures rather than design
failures.** R1-1, R1-4, R1-6 and R1-7 are all the same shape, a claim that reads as sourced
and is not. R1-7 is the one that would have cost real time: it would have produced a Week 3
exception filter with one mapping where two are needed, and the missing one turns every
authorization failure into a 500.

The week's bar asks for a hole in the specification. Round 2 has it.

### What I rejected, and why

Nothing was rejected in round 1. Every finding was a checkable fact about a standard or a
library, so there was nothing to weigh. That is itself a signal that the round was scoped too
narrowly, and round 2 was widened accordingly.

---

## Round 2, 2026-08-20

**Scope.** The working tree at 390 lines: five auth operations across four path keys, the
full shared component layer, and `DECISIONS.md` at 616 lines with ten decisions plus a
deferred list. Run against the Week 1 ERD at `8d47aae` and against the assigned readings.

**Lenses run.** The four from `Week 2 ...md:264-267` as in round 1, plus three more:
requirement coverage against `Challenge - T-Shirt Store API.md` features 1 to 10; the
document against the ERD it claims to be written on; and the document against the obligations
stated in the week's own required readings, which is what the review session grades.

**Findings were adversarially verified** before entering this ledger. One was refuted
outright and eleven were downgraded, and those do not appear below.

### Ledger

| # | Tag | Finding | Verdict | Reasoning | Commit |
| --- | --- | --- | --- | --- | --- |
| R2-1 | `[CONVENTION]` | `POST /auth/sessions` answers 201 and sends no `Location` header, and `grep -cin location openapi.yaml` returns 0. Two assigned readings recommend the header, both at SHOULD strength. **The rule is weaker than it first looks:** RFC 9110 15.3.2 says the created resource is identified "by either a Location header field in the response or, if no Location header field is received, by the target URI", so omitting it is permitted. The defect here is that the fallback does not work: the target URI is the collection `/auth/sessions`, so a client that signs in cannot learn which row it just created. | | | |
| R2-2 | `[SPEC]` | `GET /auth/sessions` returns a `{data, meta}` envelope whose `PageMeta.limit` and `PageMeta.offset` are both required, and the operation declares no `parameters` at all. `grep -n "in: query"` returns nothing across the whole document. The envelope promises pagination no caller can perform, and item 3 commits to both parameters "without exception". | | | |
| R2-3 | `[SPEC]` | `PageMeta.limit` carries `default: 20` and `maximum: 100`, and `PageMeta.offset` carries `default: 0`, on a response-only schema where both fields are required. A default on a required response property is unreachable by construction, and the maximum constrains the server's own output rather than the caller's request. | | | |
| R2-4 | `[CONVENTION]` | `Problem` carries property-level examples drawn from a single 409 email-taken occurrence, and `Problem` is referenced by all eight error responses. Swagger UI and Redoc synthesise the body sample from those keywords, so the rendered 401 on sign-in displays `status: 409` with an email-conflict title. | | | |
| R2-5 | `[CONVENTION]` | No 2xx response in the document carries an example. All eleven `example:` keywords sit on request properties or on `Problem`. `SessionTokens` and `Session` are the two schemas a frontend consumes and both render as empty strings in a mock server. The week's own consumer checklist names examples explicitly. | | | |
| R2-6 | `[CONVENTION]` | Feature 6 marks CASL a MUST and the contract expresses authorization nowhere. `Forbidden` and `Role` are each referenced zero times, no operation description names a role, and no operation declares a 403. The 403-versus-404 split is settled in item 7 and appears in no part of the document a consumer reads. | | | |
| R2-7 | `[SPEC]` | Item 8 defines rotation as deleting the presented refresh row and issuing a new one. `Session.id` is that row's id. So the identifier `GET /auth/sessions` hands the client, and the one `DELETE /auth/sessions/{id}` targets, is destroyed roughly every fifteen minutes by ordinary use. Neither document states whether the id survives, so the contract is silent where it must not be. | | | |
| R2-8 | `[SPEC]` | No operation declares 500, although item 7 promises it for every uncaught failure. `InternalServerError` is consequently an unused component that both linters warn about. | | | |
| R2-9 | `[CONVENTION]` | No request property anywhere carries `minLength`, `maxLength`, `pattern` or `minimum`, while `BadRequest` promises that `errors` names each rejected field. The 400 fires on validation rules the document never states, and there is no password policy in the ledger to state them from. | | | |
| R2-10 | `[SPEC]` | Nothing in the ledger decides null against absent. `grep -ci nullable DECISIONS.md` returns 0 across 616 lines, while the YAML header names nullability as the reason for pinning 3.0.3. `deviceName` is bare `type: string` against an ERD column declared `[null]`. | | | |
| R2-11 | `[TASTE]` | Enum value casing is inconsistent three lines apart: `OrderStatus` is lowercase and `Role` is SCREAMING_SNAKE. Item 4 governs field names and says nothing about enum values. | | | |
| R2-12 | `[CONVENTION]` | The `Unauthorized` response lists three causes and omits a rejected email or password, yet it is the 401 on `POST /auth/sessions`, where credentials are the only route to a 401. Item 8 already generalises the member to "credentials rejected", so the component is narrower than the decision it implements. | | | |
| R2-13 | `[CONVENTION]` | `TooManyRequests` declares no `Retry-After` header. The reset-password rate limit is a named Mandatory Implementation, and this is the only part of it a contract can carry. | | | |
| R2-14 | `[SPEC]` | The YAML header gives the Spectral command without `--ruleset`. Run verbatim it exits with "No ruleset has been found", which this directory's own README predicts and calls misleading. | | | |
| R2-15 | `[SPEC]` | The YAML header and the README both claim "0 errors, three warnings". Measured 2026-08-20 at 390 lines: Redocly gives 0 errors and **10** warnings, Spectral gives 0 errors and **11** warnings, and neither produces the named trio. `info-license` does not appear in the Spectral run at all. The figure was true at 251 lines. | | | |
| R2-16 | `[CONVENTION]` | `listSessions` and `refreshSession` carry a summary and no description. They are the two operations with the most unstated behaviour: the refresh one hides that a replayed token deletes every session for that user, which is the only thing that makes `refresh-token-unknown` legible to a client. | | | |
| R2-17 | `[TASTE]` | Item 6 applies the money rule "without exception" to `discountAmount` and `minPurchaseAmount`. Both are Optional Feature 13 fields that this contract puts out of scope. | | | |
| R2-18 | `[SPEC]` | The id-exposure settlement in the deferred section has no "Gave up" line, and line 9 of the same file states that a decision without one is not a decision. It gave up enumerability, and the option to move to opaque ids without a contract break. | | | |
| R2-19 | `[CONVENTION]` | Item 4's load-bearing evidence is that `user_auth_data` becomes `users` "on Thursday". It is Thursday evening and `challenge/erd` at `8d47aae` still reads `user_auth_data`. The rename is legitimately Saturday work, so the tense is wrong rather than the argument. | | | |
| R2-20 | `[TASTE]` | The header summary says "Items 2, 8 and 9 depend on each other", which was written when the file had nine items. Item 10 now names items 1, 4 and 8. | | | |
| R2-21 | `[CONVENTION]` | The scope decision is not recorded as a decision. Cutting Optional Features 11 to 13 exists only as a two-line YAML comment. It has a real cost and no Chose / Gave up / Why entry, and the operation count it implies appears nowhere a mentor can read. | | | |
| R2-22 | `[SPEC]` | Feature 8, the stock notification system, correctly has no endpoint and also has no mention. A reviewer reading only this document cannot tell whether it was covered or forgotten. | | | |

### The hole

**R2-2, and it is closed in the document.**

`GET /auth/sessions` returns a `{data, meta}` envelope whose `PageMeta.limit` and
`PageMeta.offset` are both in `required`, and the operation declares no `parameters` at all.
`grep -n "in: query"` returns nothing across all 390 lines, and there is no
`components/parameters` block to reference. The document tells a caller how many rows were
skipped and gives it no way to skip any. That is a missing request shape, which is one of the
three kinds the week's bar names, and it contradicts item 3's own words: every collection uses
this shape "without exception". The first collection authored uses half of it.

It is the right hole to fix first because it is about to be copied. Five or more collections
follow, and a reusable `Limit` and `Offset` pair in `components/parameters` is what all of
them want. Fixing it after they exist is five edits instead of one.

**R2-1 is the second fix and it needed correcting rather than promoting.** The first draft of
this ledger called the missing `Location` header "a reading assigned and ignored". That
overstates it. Both readings say SHOULD, and RFC 9110 15.3.2 is weaker still: the created
resource is identified "by either a Location header field in the response or, if no Location
header field is received, by the target URI". Omitting the header is permitted. What is
genuinely wrong here is narrower and still worth fixing: the fallback identifies the target
URI, which is the collection, so nothing tells the client which session it just created. Item
10's whole argument for the noun path is that the client can address a row, and today the
operation that creates the row does not say which one it is.

Recording the correction rather than quietly rewriting it, because overstating a SHOULD into
a violated rule is the exact fault the reading-contradiction sheet in the vault charges these
readings with. Making the same move while auditing them would not survive being asked.

**R2-7 is the deepest finding and it is not closed in this document.** It is an ERD question:
either the refresh row keeps its `id` and `created_at` across rotation and only `token_hash`
and `expires_at` change, or session identity is separated from the token row. That lands in
Saturday's ERD pass. What belongs in the contract is one sentence in item 8 saying which, and
a note on `Session.createdAt` saying whether it means first sign-in or last rotation.

### What I rejected, and why

*(To fill in as the ledger above is decided. At least one rejection is required by the week's
own bar, and R2-11, R2-17 and R2-20 are the likeliest candidates.)*

### Refuted before reaching this ledger

Recorded because the audit ran adversarially and the rejections are part of the result.

- **"No mentor review is recorded anywhere."** Refuted. The Week 1 feedback arrived off
  GitHub and its eight-row accept-reject ledger is committed at
  `4-database/3-erd/DECISIONS.md` on `challenge/erd`.
- **"PR #3's body describes a skeleton and is stale."** Refuted. The body is accurate for
  what is pushed. `origin/challenge/api-design` holds one placeholder operation and nine
  decisions. It becomes stale on the next push, which is when it gets rewritten.
- **"Modules 1 to 3 are unstarted graded work."** Refuted. `NodeJS.md` declares those topics
  assumed knowledge that will not be covered, and routes them to optional pre-work.

### Round 3

Friday afternoon, fresh session, against the authored operations. The eight components at
zero references are the checklist: anything still unreferenced when authoring stops is an
operation that was skipped.
