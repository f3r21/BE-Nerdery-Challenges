# Review rounds

I attack the contract myself, and record what I did about each finding. Three rounds, each
one started cold rather than continued from the writing, because the pass that wrote the
document already believes the assumptions that produced the hole.

Every finding carries a tag. Untagged findings do not enter the ledger.

| Tag | Means | Who decides |
| --- | --- | --- |
| `[SPEC]` | Required or forbidden by OpenAPI 3.0.3 | I verify it against `spec.openapis.org/oas/v3.0.3` before accepting |
| `[CONVENTION]` | Common practice, with a named source | I weigh it |
| `[TASTE]` | Preference, with no source behind it | Rejectable without argument |

Verdict column: `applied`, `rejected`, or `deferred` with the reason. A finding with no
verdict has not been decided yet.

---

## Round 1, 2026-08-19

**Scope.** The shared component layer and one placeholder operation, 251 lines. Deliberately
run before the other operations are authored: a flaw in `Problem` or `PageMeta`
propagates into every one of them, so it is cheaper to find here than after every operation
is written.

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
stated in the week's own required readings. The last of the three is what the mentor review
grades.

**Findings were adversarially verified** before entering this ledger. One was refuted
outright and eleven were downgraded, and those do not appear below.

### Ledger

| # | Tag | Finding | Verdict | Reasoning | Commit |
| --- | --- | --- | --- | --- | --- |
| R2-1 | `[CONVENTION]` | `POST /auth/sessions` answers 201 and sends no `Location` header, and `grep -cin location openapi.yaml` returns 0. Two assigned readings ask for the header: HTTP Methods says SHOULD, and HTTP Status Codes states it with no normative keyword at all. **The rule is weaker than it first looks:** RFC 9110 15.3.2 says the created resource is identified "by either a Location header field in the response or, if no Location header field is received, by the target URI", so omitting it is permitted. The defect here is that the fallback does not work: the target URI is the collection `/auth/sessions`, so a client that signs in cannot learn which row it just created. | Open | The narrowed finding stands. Six other creates now send `Location`, so sessions is the lone exception and needs a written reason rather than a fix. Carried to round 3. |  |
| R2-2 | `[SPEC]` | `GET /auth/sessions` returns a `{data, meta}` envelope whose `PageMeta.limit` and `PageMeta.offset` are both required, and the operation declares no `parameters` at all. `grep -n "in: query"` returns nothing across the whole document. The envelope promises pagination no caller can perform, and item 3 commits to both parameters "without exception". | Applied | `components/parameters` now declares `Limit` and `Offset`, referenced by all six collections. `grep -c "in: query"` returns 9. | `25d9595` |
| R2-3 | `[SPEC]` | `PageMeta.limit` carries `default: 20` and `maximum: 100`, and `PageMeta.offset` carries `default: 0`, on a response-only schema where both fields are required. A default on a required response property is unreachable by construction, and the maximum constrains the server's own output rather than the caller's request. | Open | `PageMeta` still carries `default` and `maximum` on required response fields. The `maximum` documents a real server invariant, so only the `default` is clearly wrong. Carried to round 3. |  |
| R2-4 | `[CONVENTION]` | `Problem` carries property-level examples drawn from a single 409 email-taken occurrence, and `Problem` is referenced by all eight error responses. Swagger UI and Redoc synthesise the body sample from those keywords, so the rendered 401 on sign-in displays `status: 409` with an email-conflict title. | Open | `Problem` still carries examples drawn from one 409, and it is now referenced by ten error responses rather than eight. Carried to round 3. |  |
| R2-5 | `[CONVENTION]` | No 2xx response in the document carries an example. All eleven `example:` keywords sit on request properties or on `Problem`. `SessionTokens` and `Session` are the two schemas a frontend consumes and both render as empty strings in a mock server. The week's own consumer checklist names examples explicitly. | Applied | `Session` and `SessionTokens` carry examples, and every schema written after them does too. | `65376be` |
| R2-6 | `[CONVENTION]` | Feature 6 marks CASL a MUST and the contract expresses authorization nowhere. `Forbidden` and `Role` are each referenced zero times, no operation description names a role, and no operation declares a 403. The 403-versus-404 split is settled in item 7 and appears in no part of the document a consumer reads. | Applied | Twelve operations declare 403 and ten descriptions carry "Only a manager may use this operation." `Forbidden` and `Role` are both referenced. | `0d75487` |
| R2-7 | `[SPEC]` | Item 8 defines rotation as deleting the presented refresh row and issuing a new one. `Session.id` is that row's id. So the identifier `GET /auth/sessions` hands the client, and the one `DELETE /auth/sessions/{id}` targets, is destroyed roughly every fifteen minutes by ordinary use. Neither document states whether the id survives, so the contract is silent where it must not be. | Open | Still true, and it is an ERD question rather than a contract one: whether the refresh row keeps its id across rotation. Carried to round 3. |  |
| R2-8 | `[SPEC]` | No operation declares 500, although item 7 promises it for every uncaught failure. `InternalServerError` is consequently an unused component that both linters warn about. | Applied | `grep -c "'500':"` returns 36, one per operation, per item 7's floor. | `65376be` |
| R2-9 | `[CONVENTION]` | No request property anywhere carries `minLength`, `maxLength`, `pattern` or `minimum`, while `BadRequest` promises that `errors` names each rejected field. The 400 fires on validation rules the document never states, and there is no password policy in the ledger to state them from. | Applied | Every request property now carries the rule its 400 fires on. `email` is bounded at 254 from RFC 5321 4.5.3.1.3. | `65376be` |
| R2-10 | `[SPEC]` | Nothing in the ledger decides null against absent. `grep -ci nullable DECISIONS.md` returns 0 across 616 lines, while the YAML header names nullability as the reason for pinning 3.0.3. `deviceName` is bare `type: string` against an ERD column declared `[null]`. | Open | No decision on null against absent exists, and no field declares `nullable`. Real, and it needs a ledger entry rather than a contract change. Carried to round 3. |  |
| R2-11 | `[TASTE]` | Enum value casing is inconsistent three lines apart: `OrderStatus` is lowercase and `Role` is SCREAMING_SNAKE. Item 4 governs field names and says nothing about enum values. | Applied | `Role` lowered to match `OrderStatus`, which is the enum that reproduces the ERD exactly. | `65376be` |
| R2-12 | `[CONVENTION]` | The `Unauthorized` response lists three causes and omits a rejected email or password, yet it is the 401 on `POST /auth/sessions`, where credentials are the only route to a 401. Item 8 already generalises the member to "credentials rejected", so the component is narrower than the decision it implements. | **Rejected** | The shared response describes the shape, not the cause. `ProblemType` carries `invalid-credentials` and `createSession`'s own description names it, so enumerating every caller's cause in the shared component would couple it to every operation that references it. |  |
| R2-13 | `[CONVENTION]` | `TooManyRequests` declares no `Retry-After` header. The reset-password rate limit is a named Mandatory Implementation, and this is the only part of it a contract can carry. | Open | `TooManyRequests` still declares no `Retry-After`, and there are now three 429s. Carried to round 3. |  |
| R2-14 | `[SPEC]` | The YAML header gives the Spectral command without `--ruleset`. Run verbatim it exits with "No ruleset has been found", which this directory's own README predicts and calls misleading. | Applied | The header command now carries `--ruleset`, matching README.md. | `25d9595` |
| R2-15 | `[SPEC]` | The YAML header and the README both claim "0 errors, three warnings". Measured 2026-08-20 at 390 lines: Redocly gives 0 errors and **10** warnings, Spectral gives 0 errors and **11** warnings, and neither produces the named trio. `info-license` does not appear in the Spectral run at all. The figure was true at 251 lines. | Applied | Corrected, then re-measured at 36 operations: Redocly 0 errors and 2 warnings, Spectral 0 errors and 1. | `25d9595`, `bf22922` |
| R2-16 | `[CONVENTION]` | `listSessions` and `refreshSession` carry a summary and no description. They are the two operations with the most unstated behaviour: the refresh one hides that a replayed token deletes every session for that user, which is the only thing that makes `refresh-token-unknown` legible to a client. | Applied | Both operations carry descriptions. `refreshSession` now states that a replayed token deletes every refresh row, per item 8. | `25d9595` |
| R2-17 | `[TASTE]` | Item 6 applies the money rule "without exception" to `discountAmount` and `minPurchaseAmount`. Both are Optional Feature 13 fields that this contract puts out of scope. | Applied | `discountAmount` and `minPurchaseAmount` removed from item 6's list, and `priceAtPurchase` corrected to `unitPrice`. All three appear zero times in the contract. | `676e5ff` |
| R2-18 | `[SPEC]` | The id-exposure settlement in the deferred section has no "Gave up" line, and line 9 of the same file states that a decision without one is not a decision. It gave up enumerability, and the option to move to opaque ids without a contract break. | Applied | Id exposure now carries a Gave up line. The real cost is that 36 operations depend on integer ids, so reversing it changes a field type everywhere at once. | `5c045c7` |
| R2-19 | `[CONVENTION]` | Item 4's load-bearing evidence is that `user_auth_data` becomes `users`, and the tense says the rename has already landed. It has not: `challenge/erd` at `8d47aae` still reads `user_auth_data`. The rename belongs to the next ERD pass, so the tense is wrong rather than the argument. | Applied | The tense is corrected and the working-day narration removed. `challenge/erd` at `8d47aae` still reads `user_auth_data`, which is the point rather than an excuse. | `5c045c7`, `6d2e823` |
| R2-20 | `[TASTE]` | The header summary says "Items 2, 8 and 9 depend on each other", which was written when the file had nine items. Item 10 now names items 1, 4 and 8. | Applied | The dependency paragraph now names both chains, including item 10 on items 1, 4 and 8. | `5c045c7` |
| R2-21 | `[CONVENTION]` | The scope decision is not recorded as a decision. Cutting Optional Features 11 to 13 exists only as a two-line YAML comment. It has a real cost and no Chose / Gave up / Why entry, and the operation count it implies appears nowhere a mentor can read. | Applied | The scope decision is recorded, with the 36 against 39 table and all three differences traced to decisions in the file. | `5c045c7` |
| R2-22 | `[SPEC]` | Feature 8, the stock notification system, correctly has no endpoint and also has no mention. A reviewer reading only this document cannot tell whether it was covered or forgotten. | Applied | Feature 8 is named on `ProductVariant.stock`, so a reader can tell it was covered rather than forgotten. | `99d4d9f` |

### The hole

**R2-2, and it is closed in the document.**

`GET /auth/sessions` returns a `{data, meta}` envelope that requires `PageMeta.limit` and
`PageMeta.offset`, and declares no `parameters` at all. It tells a caller how many rows were
skipped and gives it no way to skip any. `grep -n "in: query"` returns nothing across all 390
lines, and there is no `components/parameters` block to reference. That is a missing request
shape, one of the three kinds the week's bar names, and it contradicts item 3's own words:
every collection uses this shape "without exception". The first collection authored uses half
of it.

It is the right hole to fix first because it is about to be copied. Five or more collections
follow, and one reusable `Limit` and `Offset` pair in `components/parameters` serves all of
them. Fixing it after they exist is five edits instead of one.

**R2-1 is the second fix, and the finding itself needed correcting.** The first draft of this
ledger called the missing `Location` header "a reading assigned and ignored". That overstates
it. HTTP Methods says SHOULD, HTTP Status Codes states the header with no normative keyword
at all, and RFC 9110 15.3.2 is weaker still: with no `Location` header
the created resource is identified "by the target URI". Omitting the header is permitted. The
narrower fault is real: the target URI here is the collection, so nothing tells the client
which session it just created. Item 10 argues for the noun path because a client can address
a row, and today the operation that creates the row does not say which one.

I record the correction instead of quietly rewriting it. Overstating a SHOULD into a violated
rule is the move the readings themselves make: HTTP Methods section 2.1 says the response
SHOULD carry a `Location` header, and its own summary table then prints that header as the
answer for a collection POST with no hedge on it. Making the same move while auditing them
would not survive being asked.

**R2-7 is the deepest finding and it is not closed in this document.** It is an ERD question:
either the refresh row keeps its `id` and `created_at` across rotation and only `token_hash`
and `expires_at` change, or session identity is separated from the token row. That lands in
the next ERD pass. The contract needs one sentence in item 8 saying which, and a note on
`Session.createdAt` saying whether it means first sign-in or last rotation.

### What I rejected, and why

**R2-12, and it is the only rejection in this round.** The finding says the `Unauthorized`
response lists three causes and omits a rejected email or password, while it is the declared
401 on the operation where credentials are the only route to one.

The observation is correct and the conclusion does not follow. A shared response component
describes the **shape** a client parses, not the cause of any particular failure. The cause
travels in `Problem.type`, which is a closed enum, and `invalid-credentials` is a member of it.
`createSession`'s own description already names it. Making the shared component enumerate every
caller's cause would couple one component to all twenty operations that reference it, and every
new 401 would edit it again.

The three candidates named when this section was drafted were all applied instead, which is
worth recording. R2-11 and R2-20 were cheap and correct. R2-17 looked like taste and turned out
to be a factual error: item 6 applied the money rule to `discountAmount` and `minPurchaseAmount`,
and both appear zero times in the contract because Optional Feature 13 is cut. A finding filed
under `[TASTE]` was really a `[SPEC]` one, which is a lesson about the tags rather than about
that row.

### Refuted before reaching this ledger

- **"No mentor review is recorded anywhere."** Refuted. The Week 1 feedback arrived off
  GitHub and its eight-row accept-reject ledger is committed at
  `4-database/3-erd/DECISIONS.md` on `challenge/erd`.
- **"PR #3's body describes a skeleton and is stale."** Refuted. The body is accurate for
  what is pushed. `origin/challenge/api-design` holds one placeholder operation and nine
  decisions. It becomes stale on the next push, which is when it gets rewritten.
- **"Modules 1 to 3 are unstarted graded work."** Refuted. `NodeJS.md` declares those topics
  assumed knowledge that will not be covered, and routes them to optional pre-work.

## Round 3, 2026-08-21

**Scope.** All 36 operations, after authoring stopped. Two lenses this time: the fifteen
obligations the week's own readings place on an operation, and the brief's Minimum Required
Features 1 to 10 walked bullet by bullet.

**How it differs from the plan.** This round was written up after authoring rather than run as
one cold pass, because most of it was collected while the operations were being written. That
is a weaker guarantee than rounds 1 and 2 and it is recorded rather than glossed: a pass that
watched the code being written knows where the bodies are, and also shares its assumptions.
The feature-coverage half below was run cold and found the two blockers, which is the argument
for keeping the cold pass.

**The checklist that closed.** The eight components at zero references were the coverage probe.
All eight are now referenced, so no feature was left with a component and no operation.

### Ledger

| # | Tag | Finding | Verdict | Reasoning | Commit |
| --- | --- | --- | --- | --- | --- |
| R3-1 | `[SPEC]` | `openapi.yaml:356` states "A manager assigns any other role" and no operation accepts a role. Zero request bodies mention one, so the ten manager-only operations are reachable only by seeding the database. | Open | A real gap and a design decision: either add the operation or delete the sentence that promises it. | |
| R3-2 | `[SPEC]` | Feature 4 requires "Show client orders". Neither `Order` nor `OrderSummary` carries a customer identifier and `listAllOrders` declares no user filter, so a manager reading every order cannot tell whose any of them is. | Open | The only Minimum Required Feature that is partially covered. | |
| R3-3 | `[SPEC]` | `listProducts` and `getProduct` declare `security: []` while also declaring 401, 403 and an `includeInactive` parameter only a manager may set. In 3.0.3 an empty array removes every scheme, so the contract offers no way to authenticate on an operation it says may refuse you for not authenticating. | Open | The correct spelling for optional authentication is `security: [{}, {bearerAuth: []}]`. | |
| R3-4 | `[SPEC]` | `DECISIONS.md` item 7's floor sends "referencing a variant that does not exist" to 422. Every operation that can do that answers 404. | Open | The contract is consistent across all ten sites and the ledger row is the outlier, so the row is what changes. | |
| R3-5 | `[CONVENTION]` | `createVariant` and `setVariantStock` say a stock below zero returns 422, and both request schemas declare `minimum: 0`, which makes it a schema validation failure. Item 7 routes those to 400. | Open | Two rows of one table answer the same input differently. | |
| R3-6 | `[CONVENTION]` | Three paginated collections declared no 400 although they take the same bounded `limit` and `offset` as the three that did. | Applied | Every collection that references `Limit` or `Offset` now declares 400. Found by enumerating them rather than by trusting the linter, which flagged only the one collection that had no 4xx at all. | `cde5392` |
| R3-7 | `[CONVENTION]` | Item 6 named `minPrice`, `maxPrice`, `sortBy`, `discountAmount`, `minPurchaseAmount` and `priceAtPurchase`. None exists in the contract. A later sweep found `priceFrom` and `amount` missing from the same list. | Applied | Corrected twice. The entry now says to re-derive the list from the `Money` references rather than trust the prose, because this list has gone stale twice. | `676e5ff`, `cde5392` |
| R3-8 | `[SPEC]` | Item 5 pinned the range semantics on `from` and `to`. The parameters are `createdFrom` and `createdTo`, renamed when order history was authored. | Applied | The rule was right and the names went stale the same day. | `676e5ff` |
| R3-9 | `[TASTE]` | `[SPEC]` is defined as "required or forbidden by OpenAPI 3.0.3", and eight of the nine round 2 `[SPEC]` findings are not about OpenAPI 3.0.3. | Open | The tag definition is wrong rather than the findings. It should say "required by a named standard", which is what the rows actually assert. | |
| R3-10 | `[CONVENTION]` | `README.md` and the YAML header cited a private note path and a reading-contradiction sheet that exist outside this repository. | Applied | Replaced with `openapi.yaml` itself and the reading URL from the week's Content table. A pointer a reviewer cannot follow is worse than none. | `6d2e823` |

### The hole

**R3-2, and it is not closed.** Feature 4 asks a manager to show client orders. The contract
gives a manager every order and no way to attribute one. This is the only Minimum Required
Feature that came back partial, and it is a schema gap rather than a missing operation:
`orders.user_id` exists in the ERD and no response shape exposes it.

It is left open deliberately. Adding a customer to an order representation is a decision about
what a manager may see, and item 7 already argues that 404 protects a fact. That argument has
to be made explicitly for this field rather than assumed.

### What I rejected, and why

Nothing in round 3. Every finding above is either a checkable contradiction between two files
or a capability the brief names and the contract lacks. That is a narrower round than round 2,
which is what happens when the document has already survived two passes.
