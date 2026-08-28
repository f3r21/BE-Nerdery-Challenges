# Review rounds

I attack the contract myself, and record what I did about each finding. Three rounds, each
one started cold rather than continued from the writing, because the pass that wrote the
document already believes the assumptions that produced the hole.

Every finding carries a tag. Untagged findings do not enter the ledger.

| Tag | Means | Who decides |
| --- | --- | --- |
| `[SPEC]` | Required or forbidden by a named standard: OpenAPI 3.0.3, an RFC, or the brief | I verify it against the named source before accepting, not against recall |
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
| R2-1 | `[CONVENTION]` | `POST /auth/sessions` answers 201 and sends no `Location` header, and `grep -cin location openapi.yaml` returns 0. Two assigned readings ask for the header: HTTP Methods says SHOULD, and HTTP Status Codes states it with no normative keyword at all. **The rule is weaker than it first looks:** RFC 9110 15.3.2 says the created resource is identified "by either a Location header field in the response or, if no Location header field is received, by the target URI", so omitting it is permitted. The defect here is that the fallback does not work: the target URI is the collection `/auth/sessions`, so a client that signs in cannot learn which row it just created. | Applied | Both halves. `createSession` now sends `Location` naming the row that `DELETE /auth/sessions/{id}` addresses, and every `Location` example carries the `/v1` that `servers.url` holds. The row's own claim was wrong and is corrected here: `'201':` returns 8 and `Location:` returned 6, so sessions was never the lone exception. `createPaymentIntent` is the second, and it keeps 201 with no `Location` because no operation in this contract reads a payment attempt back. | TBD |
| R2-2 | `[SPEC]` | `GET /auth/sessions` returns a `{data, meta}` envelope whose `PageMeta.limit` and `PageMeta.offset` are both required, and the operation declares no `parameters` at all. `grep -n "in: query"` returns nothing across the whole document. The envelope promises pagination no caller can perform, and item 3 commits to both parameters "without exception". | Applied | `components/parameters` now declares `Limit` and `Offset`, referenced by all six collections. `grep -c "in: query"` returned 9, and 10 since R3-2 added `userId`. | `25d9595` |
| R2-3 | `[SPEC]` | `PageMeta.limit` carries `default: 20` and `maximum: 100`, and `PageMeta.offset` carries `default: 0`, on a response-only schema where both fields are required. A default on a required response property is unreachable by construction, and the maximum constrains the server's own output rather than the caller's request. | Applied | `default` struck from `PageMeta.limit` and `PageMeta.offset`, which is the half that was unreachable by construction. `maximum: 100` stays, because it documents a server invariant a client can rely on. The request-side `Limit` and `Offset` keep their defaults, which is the place a default is reachable. | TBD |
| R2-4 | `[CONVENTION]` | `Problem` carries property-level examples drawn from a single 409 email-taken occurrence, and `Problem` is referenced by all eight error responses. Swagger UI and Redoc synthesise the body sample from those keywords, so the rendered 401 on sign-in displays `status: 409` with an email-conflict title. | Applied | The three occurrence-specific examples are off `Problem`, and each of the ten shared responses carries its own example at its own status. A rendered 401 now shows a 401. | TBD |
| R2-5 | `[CONVENTION]` | No 2xx response in the document carries an example. All eleven `example:` keywords sit on request properties or on `Problem`. `SessionTokens` and `Session` are the two schemas a frontend consumes and both render as empty strings in a mock server. The week's own consumer checklist names examples explicitly. | Applied | `Session` and `SessionTokens` carry examples, and every schema written after them does too. | `65376be` |
| R2-6 | `[CONVENTION]` | Feature 6 marks CASL a MUST and the contract expresses authorization nowhere. `Forbidden` and `Role` are each referenced zero times, no operation description names a role, and no operation declares a 403. The 403-versus-404 split is settled in item 7 and appears in no part of the document a consumer reads. | Applied | Twelve operations declare 403 and ten descriptions carry "Only a manager may use this operation." `Forbidden` and `Role` are both referenced. | `0d75487` |
| R2-7 | `[SPEC]` | Item 8 defines rotation as deleting the presented refresh row and issuing a new one. `Session.id` is that row's id. So the identifier `GET /auth/sessions` hands the client, and the one `DELETE /auth/sessions/{id}` targets, is destroyed roughly every fifteen minutes by ordinary use. Neither document states whether the id survives, so the contract is silent where it must not be. | Applied | Decided rather than worked around: rotation updates the refresh row in place, so `token_hash` and `expires_at` change and `id` and `created_at` survive. Item 8 argues it, `refreshSession` and `Session` state it to a client, and the ERD ledger carries the schema half as the row 4 addendum. `Session.createdAt` means first sign-in on that device. | TBD |
| R2-8 | `[SPEC]` | No operation declares 500, although item 7 promises it for every uncaught failure. `InternalServerError` is consequently an unused component that both linters warn about. | Applied | `grep -c "'500':"` returns 36, one per operation, per item 7's floor. | `65376be` |
| R2-9 | `[CONVENTION]` | No request property anywhere carries `minLength`, `maxLength`, `pattern` or `minimum`, while `BadRequest` promises that `errors` names each rejected field. The 400 fires on validation rules the document never states, and there is no password policy in the ledger to state them from. | Applied | Every request property now carries the rule its 400 fires on. `email` is bounded at 254 from RFC 5321 4.5.3.1.3. | `65376be` |
| R2-10 | `[SPEC]` | Nothing in the ledger decides null against absent. `grep -ci nullable DECISIONS.md` returns 0 across 616 lines, while the YAML header names nullability as the reason for pinning 3.0.3. `deviceName` is bare `type: string` against an ERD column declared `[null]`. | Applied | `DECISIONS.md` item 11: absent, never null. No field declares nullability and none needs to, which is also what keeps the document diffable if it ever moves to 3.1. Re-derive with `grep -cE '^ +nullable:' openapi.yaml`. | TBD |
| R2-11 | `[TASTE]` | Enum value casing is inconsistent three lines apart: `OrderStatus` is lowercase and `Role` is SCREAMING_SNAKE. Item 4 governs field names and says nothing about enum values. | Applied | `Role` lowered to match `OrderStatus`, which is the enum that reproduces the ERD exactly. | `65376be` |
| R2-12 | `[CONVENTION]` | The `Unauthorized` response lists three causes and omits a rejected email or password, yet it is the 401 on `POST /auth/sessions`, where credentials are the only route to a 401. Item 8 already generalises the member to "credentials rejected", so the component is narrower than the decision it implements. | **Rejected** | The shared response describes the shape, not the cause. `ProblemType` carries `invalid-credentials` and `createSession`'s own description names it, so enumerating every caller's cause in the shared component would couple it to every operation that references it. |  |
| R2-13 | `[CONVENTION]` | `TooManyRequests` declares no `Retry-After` header. The reset-password rate limit is a named Mandatory Implementation, and this is the only part of it a contract can carry. | Applied | `TooManyRequests` declares `Retry-After`, matching the shape of `WWW-Authenticate` on `Unauthorized`. RFC 9110 10.2.3 allows a number of seconds or an HTTP-date, so the schema is a string. | TBD |
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

**Closed 2026-08-25, and the first option won.** The row keeps its `id` and `created_at`, and
rotation changes `token_hash` and `expires_at`. Item 8 carries the sentence, `Session` carries
the note, and the ERD ledger carries the schema half as the row 4 addendum. Three ERD passes
landed between this finding and its answer without touching it, which is what a deferral to
"the next pass" buys when nothing names the pass.

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
| R3-1 | `[SPEC]` | `createUser`'s description stated "A manager assigns any other role" and no operation accepts a role. Zero request bodies mention one, so the ten manager-only operations are reachable only by seeding the database. | Applied | Closed by deleting the promise rather than building the endpoint. The brief's Manager Capabilities at `Challenge - T-Shirt Store API.md:54-63` list six abilities and role assignment is not among them, and the CASL abilities at `:89-99` do not name it either. The sentence was the defect, not the missing operation. Recorded in the scope entry with its cost: a fresh database has no manager until one is seeded. | TBD |
| R3-2 | `[SPEC]` | Feature 4 requires "Show client orders". Neither `Order` nor `OrderSummary` carries a customer identifier and `listAllOrders` declares no user filter, so a manager reading every order cannot tell whose any of them is. | Applied | `OrderCustomer` on `Order` and `OrderSummary`, present only when the caller is a manager, plus a `userId` filter on `listAllOrders`. What a manager may see is written out as its own deferred entry rather than assumed, which is what this row asked for. | TBD |
| R3-3 | `[SPEC]` | `listProducts` and `getProduct` declare `security: []` while also declaring 401, 403 and an `includeInactive` parameter only a manager may set. In 3.0.3 an empty array removes every scheme, so the contract offers no way to authenticate on an operation it says may refuse you for not authenticating. | Applied | The row needed correcting first: `getProduct` declared neither 401 nor 403 nor `includeInactive`, so only `listProducts` matched the finding as written. Both now spell optional authentication `[{}, {bearerAuth: []}]`, and `getProduct` declares 401 because its answer depends on who is asking. `security: []` drops from 9 to 7 and the seven that keep it are genuinely public. | TBD |
| R3-4 | `[SPEC]` | `DECISIONS.md` item 7's floor sends "referencing a variant that does not exist" to 422. Every operation that can do that answers 404. | Applied | Applied to the ledger, which was the outlier as this row said. Item 7's floor now splits the case in two: a row named by a path parameter is 404, and a row named in the body, such as a `categoryIds` entry, is 422. The contract did not move. | TBD |
| R3-5 | `[CONVENTION]` | `createVariant` and `setVariantStock` say a stock below zero returns 422, and both request schemas declare `minimum: 0`, which makes it a schema validation failure. Item 7 routes those to 400. | Applied | The schemas were right and the prose was wrong. Both descriptions now say 400, and `'422'` is gone from `createVariant` and `setVariantStock` because nothing on those two operations fires it. The two 422s that survive, on `createProduct` and `updateProduct`, now state their cause. | TBD |
| R3-6 | `[CONVENTION]` | Three paginated collections declared no 400 although they take the same bounded `limit` and `offset` as the three that did. | Applied | Every collection that references `Limit` or `Offset` now declares 400. Found by enumerating them rather than by trusting the linter, which flagged only the one collection that had no 4xx at all. | `cde5392` |
| R3-7 | `[CONVENTION]` | Item 6 named `minPrice`, `maxPrice`, `sortBy`, `discountAmount`, `minPurchaseAmount` and `priceAtPurchase`. None exists in the contract. A later sweep found `priceFrom` and `amount` missing from the same list. | Applied | Corrected twice. The entry now says to re-derive the list from the `Money` references rather than trust the prose, because this list has gone stale twice. R4-9 closes the last gap in that rule, since `minTotal` and `maxTotal` referenced nothing until then. | `676e5ff`, `cde5392` |
| R3-8 | `[SPEC]` | Item 5 pinned the range semantics on `from` and `to`. The parameters are `createdFrom` and `createdTo`, renamed when order history was authored. | Applied | The rule was right and the names went stale the same day. | `676e5ff` |
| R3-9 | `[TASTE]` | `[SPEC]` is defined as "required or forbidden by OpenAPI 3.0.3", and eight of the nine round 2 `[SPEC]` findings are not about OpenAPI 3.0.3. | Applied | The tag definition changed, not the findings. It now reads "required or forbidden by a named standard", which is what the rows always asserted. | TBD |
| R3-10 | `[CONVENTION]` | `README.md` and the YAML header cited a private note path and a reading-contradiction sheet that exist outside this repository. | Applied | Replaced with `openapi.yaml` itself and the reading URL from the week's Content table. A pointer a reviewer cannot follow is worse than none. | `6d2e823` |

### The hole

**R3-2.** Feature 4 asks a manager to show client orders. The contract gave a manager every
order and no way to attribute one. This was the only Minimum Required Feature that came back
partial, and it is a schema gap rather than a missing operation: `orders.user_id` exists in
the ERD and no response shape exposed it.

**Closed 2026-08-25.** It was left open because adding a customer to an order representation
is a decision about what a manager may see, and item 7 already argues that 404 protects a
fact. That argument is now made rather than assumed, in its own deferred entry: item 7's rule
protects which orders exist and whose they are, and it does not reach a manager who is already
authorized to read every one of them. `OrderCustomer` is optional on both order shapes and
`listAllOrders` takes a `userId` filter.

### What I rejected, and why

Nothing in round 3. Every finding above is either a checkable contradiction between two files
or a capability the brief names and the contract lacks. That is a narrower round than round 2,
which is what happens when the document has already survived two passes.

**All five open rows closed on 2026-08-25**, and two of the findings needed correcting before
they could be applied. R3-3 described `getProduct` as declaring 401, 403 and `includeInactive`,
and it declared none of the three. R3-4 and R3-5 both turned out to indict the ledger rather
than the contract. A finding that is wrong about its own evidence is still worth filing, and
it is worth saying so in the row that closes it.

## Round 4, 2026-08-25

**Scope.** The contract against its own two ledgers, after `challenge/erd` merged into this
branch at `f96d62a`. That merge brought the ERD three passes past the `8d47aae` this document
was written against, so a class of finding exists here that could not exist on 2026-08-21: a
claim that was true when it was written and that the merge made false.

**How it differs from the earlier rounds.** Rounds 1 to 3 audited one document. This one
audits the seam between three: `openapi.yaml`, `5-api-design/DECISIONS.md` and
`4-database/3-erd/DECISIONS.md`. Six of the fourteen rows below are not defects in any single
file. They are two files disagreeing.

**This round also closed the twelve rows rounds 2 and 3 left open.** Their verdicts are
updated in place above, which is the convention this file already uses. That reverses the
position held on 08-21, which was to declare them rather than fix them because the deliverable
had shipped. The argument for reversing it: the ERD merge reopened the document anyway, and a
finding carrying a verdict and a commit is a stronger artifact than a finding left standing.

**Lenses run.** Every claim in both ledgers re-derived against the merged tree, one at a time.
Every cross-file citation resolved before it was trusted. Every figure re-measured with the
command that produced it, never quoted.

**A third lens, added late: run the document.** R4-15 and R4-16 were found by serving the
contract through a Prism mock behind Swagger UI and reading what it actually returned. Neither
linter reports either one, and no amount of reading the file finds them, because both are about
what a consumer renders rather than what the document says. This is the cheapest lens in the
four rounds and it was the last one tried.

### Ledger

| # | Tag | Finding | Verdict | Reasoning | Commit |
| --- | --- | --- | --- | --- | --- |
| R4-1 | `[SPEC]` | Two ledgers decide the stock-notification grain in opposite directions and both ship in one branch. `5-api-design/DECISIONS.md` settled a single variant reaching 3 on 08-21. `4-database/3-erd/DECISIONS.md` settled the sum across variants at `62144ff` on 08-24. Each names the other's choice as its own failure mode. | Applied | The ERD's wins on two grounds: it is the literal reading of the brief, and `stock_notifications` is keyed `(user_id, product_id)`, so the table that records the mail cannot express a per-variant trigger without a schema change. A rule the schema cannot record is not a rule. `ProductVariant.stock` carried the old rule to clients and is rewritten. | TBD |
| R4-2 | `[SPEC]` | Three files claim the contract is "written against ERD commit `8d47aae` on `challenge/erd`". The branch carries the ERD three passes further on, so the citation names a schema this tree does not hold. | Applied | Replaced with the path and the merge commit, both reachable from the branch a reviewer opens. `REVIEW.md:68` and R2-19 keep `8d47aae`, because they record the scope of a round that really did run against it. | TBD |
| R4-3 | `[SPEC]` | `openapi.yaml` names `user_auth_data` and `user_role`. Both were renamed at `35597a4`. | Applied | Renamed in both comments. The substance of the `Role` comment survives: the schema still leaves the role set open and still spells the third role `Delivery`, and the three ERD passes closed neither. | TBD |
| R4-4 | `[CONVENTION]` | Item 4's load-bearing evidence says the `user_auth_data` rename "is still pending". It landed at `35597a4`. R2-19 had already corrected the tense once, in the other direction. | Applied | Rewritten in the past tense, which makes it a stronger argument than the one it replaces. The rename happened, and it touched no path, no schema and no field name in the contract. Two YAML comments moved and nothing a client can see. | TBD |
| R4-5 | `[SPEC]` | Two deferred entries say their ERD dependency is "on the ERD's agreed-and-not-done list". Both shipped at `c41729f`: `UNIQUE (cart_id, product_variant_id)` and `stock_notifications`. | Applied | Both entries record what shipped and keep their cost lines. The cart entry's idempotence promise is enforced by the schema for the first time. | TBD |
| R4-6 | `[CONVENTION]` | `4-database/3-erd/DECISIONS.md` row 10 says the cart uniqueness constraint exists "so the handler can add to the existing line". The contract says the quantity is absolute and explicitly not an increment. | Applied | The constraint is right and the reason given described semantics the contract rejects. The ERD row now says the handler replaces the quantity on the row already there. Found on the ERD side of the seam, which is the argument for auditing both. | TBD |
| R4-7 | `[SPEC]` | Every `Location` example is root relative: `/users/128`, `/products/12`, `/images/88`, `/variants/340`, `/orders/501`, `/orders/502`. A path-absolute reference resolves against the origin and not against the server base path, so each drops the `/v1` that item 1 put in `servers.url` and names a URL this API does not serve. | Applied | All six prefixed, and the seventh from R2-1 written that way. `grep -c 'example: /v1/'` returns 7. Item 1 was stated in one file and enforced nowhere, which is the cause these four defects share. | TBD |
| R4-8 | `[SPEC]` | `ProductSummary` lists `priceFrom` in `required`, and `createProduct`'s own description says a new product has no variant and so has no price. A product between creation and its first variant cannot be represented in `listProducts`. | Applied | `priceFrom` is optional and states when it is absent. Composes with item 11, which makes absent the only empty value. | TBD |
| R4-9 | `[SPEC]` | `Money` declares no `minimum` while `stock` and `quantity` both do, so a negative price validates against the schema whose own item spends 78 lines on money being exact. | Applied | `minimum: 0` on `Money`, which reaches all sixteen references at once. Nothing legal is excluded, because this contract carries no refund and no discount. | TBD |
| R4-10 | `[CONVENTION]` | Item 6 names `minTotal` and `maxTotal` as money fields and then tells the reader to re-derive the list from what references the `Money` schema. Those two were inline integers and referenced nothing, so the rule could not find the fields the same paragraph names. | Applied | Both parameters reference `Money` through `allOf`. The rule now enforces itself, which is what R3-7 asked for after this list went stale twice. | TBD |
| R4-11 | `[CONVENTION]` | Item 7's status-code floor omits 413 and 415, and `uploadProductImage` emits both. It also names 429 for the reset-password limit only, while the contract declares three. | Applied | Two rows added, the 429 row widened to any password endpoint, and item 9 now mentions the rate limit its own operation has always declared. | TBD |
| R4-12 | `[CONVENTION]` | Item 10 cites "Row C13 of my `Where the readings are wrong` sheet", a document outside this repository. R3-10 declared that class of pointer removed and removed it from `README.md` and the YAML header, and missed this one. | Applied | Replaced with the primary source that sheet's row rests on, Fielding's 2008 post, stated in the first person as my own reading. A pointer a reviewer cannot follow is worse than none. | TBD |
| R4-13 | `[CONVENTION]` | The B4b entry says `product_likes` keyed `(user_id, product_id)` "already matches the audience the brief asks for". The brief at `Challenge - T-Shirt Store API.md:122` says "users who liked the product **but haven't purchased it yet**". The claim drops the second clause. | Applied | Corrected, and the purchase half named as what it is: a query over `order_items` back through `product_variants`, held nowhere in the schema. The ERD ledger's row 9 had the predicate right all along, which is the tell that the two files were not being read against each other. | TBD |
| R4-15 | `[CONVENTION]` | `WWW-Authenticate` on `Unauthorized` and `Retry-After` on `TooManyRequests` declare a schema and no example. A mock and Swagger UI both render the type name, so every 401 in the demo carried the literal header value `string`. The `WWW-Authenticate` header is the one real MUST in the whole contract. | Applied | Both carry an example: `Bearer realm="tshirt-store"` and `60`. Found by running the document through a mock, not by reading it. | TBD |
| R4-16 | `[SPEC]` | Four shared error responses carried a single example naming a single cause, and each serves many operations. A 409 on `POST /orders` rendered the `email-taken` body, and a 404 on an order rendered "No product has this id". This is R2-4's defect one level down: R2-4 moved the example off the schema and onto the response, which fixed the status code and not the cause. | Applied | `Unauthorized`, `Conflict`, `NotFound` and `UnprocessableEntity` now use named `examples`, one per cause the status can carry, so the three 401 members and the three 409 members are enumerated where a client reads them. That is item 2's argument made visible rather than asserted, and it does not couple the component to any operation, which is what R2-12 rejected. | TBD |
| R4-14 | `[TASTE]` | `ProductImage.url`, `ProductSummary.primaryImageUrl` and `CartItem.imageUrl` are three names for one concept, which is round 1's own lens for the same idea expressed two ways. | **Rejected** | The three sit on three schemas and each reads correctly where it is: `url` on an image, `primaryImageUrl` on a product that has several, `imageUrl` on a cart line that shows one. A field rename is a contract change under this document's own rules, and there is no defect behind this one. |  |

### The hole

**R4-1, and it is the only finding in four rounds that neither document could have found on
its own.** Both ledgers were internally consistent. Both cited their sources. Both stated a
cost. They answered the same question in opposite directions, and the contradiction became
visible at the moment the two files entered one branch and not before.

The four rounds have found four kinds of defect, and the progression is the point. Round 1
found citation failures inside one file. Round 2 found a missing request shape. Round 3 found
a feature the contract only partly covered. Round 4 found two documents that disagree. Only
the last needed the merge to exist.

**What would have caught it earlier.** Nothing in the process, and that is the honest answer.
The two decisions were taken three days apart, by the same person, reading the same brief,
and each was written into the ledger that owned it. The check that catches it is a pass over
both ledgers for questions that appear in both, and no such pass existed until this one.

### What I rejected, and why

**R4-14, the three image field names.** The observation is correct and the conclusion does not
follow. Each name reads correctly on the schema that carries it, and this document treats a
field rename as a contract change. Consistency for its own sake is not worth a break, and "the
same idea expressed two ways" is a lens for finding real duplication rather than a rule that
every concept owns exactly one spelling.

One rejection in fourteen rows. A round with no rejection is a round that weighed nothing.

---

## Round 5, 2026-08-28. The first round from outside

The first four rounds were self-review. This one is not: every finding is a mentor observation
from the review of 2026-08-25, applied three days late because the observations were not
written down while he spoke and had to be recovered from a meeting summary.

That delay is itself the finding worth recording. `notes/week-2-review-notes.md` existed
specifically to be filled during the meeting, and its own header explains that the Week 1 items
"existed nowhere until they were written down by hand three days later". The same thing happened
again. The recovered rows are a paraphrase, not his words, and the file says so.

### R5-1, likes and stock notifications move to the variant

**He said:** likes and stock notifications should attach to the product variant, not the
product, for size and colour precision.

**Applied.** `/products/{id}/like` becomes `/variants/{id}/like` for both verbs, `likeProduct`
and `unlikeProduct` become `likeVariant` and `unlikeVariant`, and the feature 8 trigger sentence
on `ProductVariant.stock` is rewritten. It read "the sum of this value across every variant of
that product reaches 3", which is the product-grain statement.

**This supersedes R4-1.** Round 4 settled this in favour of the product grain, on the reasoning
that it was the literal reading of the brief and that `stock_notifications(user_id, product_id)`
could not express a per-variant trigger. The second half was true of the ERD as it then stood;
the ERD moved on 2026-08-26 at `c4cc306`, at his instruction, and the key is now
`(user_id, product_variant_id)`. So R4-1's premise was retired by the same review that produced
this row. R4-1 stands as correctly decided on the information available and is closed as
superseded rather than wrong.

**What it costs, stated because a reader will find it.** `ProductSummary` carries no variant
ids, so a like cannot be sent from the product list. It is sent from the product page, where
`Product.variants` carries them. That is also where a person picks a size, so the constraint and
the interaction agree, but it is a constraint and not a free change.

**`listLikedProducts` still returns products.** A person browses products, not sizes, and two
liked variants of one product are one entry. Collapsing variant likes to products is a
`DISTINCT`; the reverse cannot be done at all, which is the asymmetry that makes the variant
grain the safe direction.

### R5-2, the sign-in response carries the user

**He said:** the login response should also return user info, name and role, to reduce client
follow-up queries.

**Applied.** `SessionTokens` gains a required `user` member referencing the existing `User`
schema. Required rather than optional: the server holds the row at that moment, so an optional
member would only invite a client to handle an absence that never occurs.

Worth noting that this is the first time the contract has been changed for a reason that is
neither correctness nor consistency. It is changed because a client would otherwise make two
requests where one would do, which is a cost the contract could not see from inside itself.

### R5-3, emptying the cart moves to the cart

**He said:** cart delete should be `DELETE /users/me/cart`, dropping `items`, to match the `GET`
convention. Item-level endpoints stay as they are.

**Applied.** `clearCart` moves from `/users/me/cart/items` to `/users/me/cart`, so the two verbs
on the collection sit on the path the collection is read from.

### R5-4, a way to add to the cart

**He said:** there is no POST endpoint to add items to the cart.

**Applied.** `POST /users/me/cart/items` with `variantId` and `quantity`, where the quantity is
an amount to add. `PUT .../{variantId}` keeps its absolute-set semantics.

Both belong, and the distinction is not pedantry: a product page adds, and a cart page sets. A
single operation would force one of the two callers to read the current quantity first, which is
a request the other endpoint exists to avoid.

### R5-5, ownership on sign-out-other-device

**He said:** the sign-out-other-device endpoint needs a check that the target session belongs to
the same account as the caller's token, to prevent user A logging out user B with a known
session id.

**No change required, and it was already built.** `DELETE /auth/sessions/{id}` has always
declared 404 and deliberately no 403, on the reasoning at R2 that a 403 would confirm the
session exists. The implementation scopes its delete by `{ id, userId }` and answers 404 on zero
rows, so the attempt neither succeeds nor reveals anything, and there is an end-to-end test for
exactly that case.

The observation is still worth its row. He arrived at the requirement independently, and a rule
that two people reach separately is one worth keeping.

### R5-6, the reset flow, ambiguous and not applied

**He said:** the password reset flow, email verification and logout all devices, is not yet
reflected in the contract.

**Not applied, because it resolves two ways and guessing is worse than asking.** Logging every
device out on a reset is in the contract already, and is implemented and tested. Account email
verification at sign-up is in neither the contract nor the brief, and adding it would be new
scope rather than a correction. The question is with him.

### What this round did not do

Nothing was rejected. Six observations, four applied, one already satisfied, one held open on a
question of fact. A round with no rejection weighed nothing, by round 4's own standard, so this
one is weaker than it looks: these are instructions from the grader, and the only judgement
exercised was on R5-6, where the honest move was to decline to guess.
