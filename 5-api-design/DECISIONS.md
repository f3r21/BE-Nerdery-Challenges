# API design decisions

Written against ERD commit `8d47aae` on `challenge/erd`.

Every decision below appears in **every** operation. Retrofitting any one of them is a
full-document rewrite, which is why they are settled before the first path is typed.

Same shape as `4-database/3-erd/DECISIONS.md`: what was chosen, what it cost, and why.
A decision with no "Gave up" line is not a decision, it is a default nobody examined.

## The nine calls

| # | Question | Chose |
| --- | --- | --- |
| 1 | Version in the path | `/v1` prefix, carried in `servers.url` |
| 2 | Error shape | RFC 9457 Problem Details, `application/problem+json` |
| 3 | Pagination | `{data, meta}` envelope, `offset` / `limit`, `meta.total` |
| 4 | Field casing | `camelCase`, query parameters included |
| 5 | Date-time | RFC 3339 with `Z`, full datetimes on filters, `from` inclusive and `to` exclusive |
| 6 | Money | Integer minor units (cents), no `currency` field |
| 7 | Status codes | 400 on validation, 404 on another client's order. 403 protects an action, 404 protects a fact |
| 8 | Tokens | 15 min access, 7 day refresh, rotation on use, per-device sign-out, typed 401 |
| 9 | Password change | `PATCH /v1/users/me/password` exists, kills every session |

Items 2, 8 and 9 depend on each other. Item 2's `Problem.type` is what makes item 8's
typed 401 work, and item 8's session eviction is what makes item 9 cheap.

---

## 1. Version in the path, or not

**The question.** `/v1/products` or `/products`. If not in the path, then where: a header,
a media type, or nowhere at all.

**What it costs either way.** A path prefix is visible, cacheable and trivially routable,
and it commits you to the claim that a v2 could exist. No prefix is honest for a service
with one consumer, and adding a prefix later breaks every client at once.

**Chose:** URI versioning, not header or media-type versioning. Every effective URL is
`/v1/...`.

**The prefix lives in `servers.url`** (`http://localhost:3000/v1`), not repeated on each
`paths` key. Both render the same URL in Swagger and both are valid OpenAPI; putting it in
`servers` keeps `paths` keys as pure resource names, which is the same rule as "no schema
table name appears in the spec" applied to the version. It also means bumping to v2 is one
line rather than forty. NestJS implements the runtime half with
`app.enableVersioning({ type: VersioningType.URI })`, which prefixes routes rather than
requiring the version in every controller path.

**Gave up:** two things. The URI stops being a pure identifier: `/v1/products/42` and a
future `/v2/products/42` name the same product under two addresses, which is why strict
REST prefers versioning by `Accept` header or media type. And the prefix asserts that a v2
could exist, so "what would v2 be?" is now a fair question with no answer yet.

**Why:** it costs four characters now and cannot be added later without breaking every
client at once. The asymmetry is the whole argument: the cost of having it and never
needing it is trivial, the cost of needing it and not having it is a coordinated break.
The brief's breaking-change table lists changing a status code as a break, so the escape
hatch is not hypothetical for this API. Adding a value to a response enum is also breaking
for a consumer with an exhaustive switch, which is my own reading and is not in the table.

---

## 2. One error schema, everywhere

**The question.** A single `Error` component that every non-2xx response `$ref`s, and what
its fields are.

**What it costs either way.** One shape means every client writes one error handler.
Per-endpoint shapes carry more detail but nothing can consume them generically.

**The Week 3 trap, worth deciding around now.** Nest's default error body is
`{statusCode, message, error}` where `message` is an **array** when it comes from
`ValidationPipe` and a **string** when it comes from a plain `NotFoundException`. Pinning
one shape here means a global exception filter in Week 3 rather than a surprise.

**Chose:** RFC 9457 Problem Details, which obsoletes RFC 7807. One `Problem` component
`$ref`d by every non-2xx
response, served as `application/problem+json`, with members `type`, `title`, `status`,
`detail` and `instance`. Validation failures use the spec's extension-member mechanism to
add an `errors` array of `{field, message}`, which is where `ValidationPipe`'s array goes.

**A `type` is not needed on every problem.** RFC 9457 registers `about:blank`, meaning the
problem has no semantics beyond the HTTP status code, and it is the assumed value when
`type` is absent. So a type URI is minted only where the status code alone cannot tell a
client which failure it hit. Here that is the three 401 cases and the three 409 cases.
Everything else omits it.

**Gave up:** three things. Nest ships no support for it, so this costs a global exception
filter in Week 3 plus an explicit `P2002` mapping, and the filter is now load-bearing
rather than optional. `status` duplicates the HTTP status code in every error body, which
is redundancy the standard accepts and I inherit. And the `type` URIs are a promise: a
reviewer can ask what is at the other end of one.

**Why:** at least three places in this API return the same status code for different
reasons. Sign-up 409s on a taken email, cancel 409s on an already-shipped order, and
add-to-cart 409s on insufficient stock. A client that shows the right message has to tell
them apart, and a status code alone cannot carry that. String-matching `message` is the
alternative and it breaks the moment the wording changes.

Given that a machine-readable discriminator is required, the remaining choice was between
inventing a shape and citing one. RFC 9457 is an IETF standard with tooling across
languages, and its extension-member rule means the validation-error array fits without
leaving the standard. Inventing `{code, message, details[]}` would have been slightly
lighter and would have needed defending as a local invention instead.

---

## 3. Pagination envelope

**The question.** What a collection response looks like. Bare array, or an object wrapping
`data` plus metadata. Offset/limit, page/size, or cursor. What the metadata contains.

**What it costs either way.** A bare array is simpler and cannot carry a total count.
Offset pagination is easy and drifts when rows are inserted mid-scan. Cursor pagination is
stable and cannot jump to page 7.

**Applies to.** Products, categories, order history, and anything added later. The failure
mode is two collections that paginate differently, which the review round will look for.

**Chose:** an envelope, `{ data: [...], meta: { total, limit, offset } }`, with
`offset` and `limit` as query parameters. `limit` has a default and a documented maximum
so an unbounded request cannot ask for the whole table. Every collection in this API uses
this shape, without exception.

**Gave up:** two things, and the first is a correctness cost rather than a cosmetic one.

Offset pagination **drifts under concurrent writes**. If a product is inserted while a
client is walking pages, an item from page 1 can reappear on page 2, and an item can be
skipped entirely. A cursor would have been stable. This is acceptable here because the
catalogue is manager-edited at low frequency and order history is append-only per user,
but it is a real property of the API and not a detail.

`meta.total` costs a second `COUNT(*)` per list request, matching the same `WHERE`. On
order history with five filters applied that count is not free.

**Why:** the envelope is the decision that cannot be undone. Adding `meta` to a bare array
later changes the response type of every collection at once, which is exactly the break
the version prefix in item 1 exists to survive, and paying for it in week two of a
four-week project would be self-inflicted.

`total` is required by the product itself, not by taste: a catalogue with pagination
controls has to render "page 3 of 18", and the client cannot compute that from a page of
results. Offset over cursor follows from the same place, because page numbers need
addressable pages and a cursor cannot jump to page 7.

Offset also matches Prisma's `skip` and `take` directly, so the contract and the Week 3
query are the same idea rather than a translation.

---

## 4. JSON field casing

**The question.** `camelCase`, `snake_case`, or the ERD's own column names.

**What it costs either way.** The ERD is `snake_case`. Prisma will hand you whatever the
schema says. A JSON API in `camelCase` needs a mapping layer; one in `snake_case` leaks the
column names into the contract and couples the two.

**Chose:** `camelCase` for every JSON field, and for **query parameters too**:
`minPrice`, `maxPrice`, `sortBy`, not `min_price`. The schema stays `snake_case`; the two
are deliberately different vocabularies.

**Gave up:** a mapping layer, and the duplication that comes with it. Every field now has
a column name and a wire name, and both are maintained. In Week 3 that is `@map("created_at")`
in the Prisma schema or `@Expose({ name })` in a serializer, one line per field. It also
means a field can drift: the column and the property can disagree, and nothing catches it
except review.

**Why:** the coupling is the thing being avoided, and this week proves it is not
hypothetical. `user_auth_data` becomes `users` on Thursday because a reviewer asked. If
the contract exposed column names, that rename would be an API break rather than a schema
tidy-up. This is the same rule as "no schema table name appears in the spec", applied to
fields instead of resources, and the version prefix in item 1 exists to survive exactly
the kind of break it prevents.

Second reason, smaller but real: separating the two names forces the question *what should
this be called to a client*, which is a different question from what the column is called.
`is_primary` is a good column name and `isPrimary` is a good field name, but
`assigned_delivery_person_id` is a good column name and a bad field name. Under coupling
that distinction never comes up.

The consumer is TypeScript, so `order.createdAt` reads natively and `order.created_at`
makes every client either rename on receipt or accept a lint warning on every access.

---

## 5. Date-time format

**The question.** The wire format for `createdAt`, `changedAt`, `expiresAt` and every date
filter on order history.

**What it costs either way.** RFC 3339 with an explicit `Z` is unambiguous and is what
`format: date-time` means in OpenAPI. Epoch seconds are compact and unreadable in a log.
A naive local timestamp is the bug `timestamptz` was adopted to prevent, so it should not
reappear at the API boundary.

**Chose:** RFC 3339 with an explicit `Z`, always UTC, `2026-08-19T14:32:00Z`. Declared as
`type: string, format: date-time` everywhere. The order-history range filter takes **full
datetimes**, not dates. August is
`?from=2026-08-01T00:00:00Z&to=2026-09-01T00:00:00Z`, not `2026-08-31T23:59:59Z`, which is
the trap the half-open rule below exists to avoid.

Range semantics, pinned here so no operation has to decide it: **`from` is inclusive,
`to` is exclusive.** Half-open, so consecutive ranges tile without overlapping or
dropping a row on the boundary.

**Gave up:** verbosity, and some client convenience. A UI date picker produces a day, not
an instant, so the client now converts before calling. That conversion is where a
timezone bug can still be introduced, except it is now the client's bug and a visible one,
rather than the server silently guessing which day the user meant.

**Why:** the same argument already settled at the database layer in `47a4d91`, applied one
layer out. Bare `timestamp` was replaced with `timestamptz` because a UTC server and a
GMT-6 laptop disagreed about which orders fall in January. Accepting a bare date at the
API would reintroduce exactly that disagreement, because "2026-08-01" is not an instant
until somebody picks a timezone, and the server picking silently is the failure.

Full datetimes on the filter make the client state the instant it means. Half-open
intervals then remove the second ambiguity: with an inclusive `to`, "give me August" and
"give me September" either both claim midnight on the 1st or neither does, and
`23:59:59Z` silently drops anything in the final second.

`format: date-time` is also the OpenAPI-native spelling, so the linter and any generated
client validate it without a custom pattern.

---

## 6. Money representation

**The one that bites in Week 3.** `numeric(10,2)` becomes a Prisma `Decimal`, and
`JSON.stringify` renders a `Decimal` as a **string**. So `{type: number}` is wrong on day
one, before anybody writes a bug.

**The question.** Integer minor units (cents), a decimal string, or a float.

**What it costs either way.** Integer cents match what Stripe charges and cannot round
wrong; every client divides by 100. A decimal string is readable and forces every client
to parse before arithmetic. A float is the one option that is simply incorrect for money.

**Applies to, without exception.** `price`, `priceAtPurchase`, `discountAmount`,
`subtotal`, `total`, `minPurchaseAmount`, **and the `minPrice` / `maxPrice` query
parameters.** Mismatching the params against the response fields is how a frontend divides
by 100 in one place and not the other.

**Chose:** integer minor units. Every money field is `type: integer` and carries a value
in cents, so 19.99 is `1999`. No `currency` field; the store is single-currency and the
currency is stated once in `info.description`. The ERD keeps `numeric(10,2)` as storage,
so cents are a wire format, not a storage format.

Conversion lives in **exactly one place**, the serialization layer, on the way out and on
the way in. Nowhere else multiplies or divides by 100. Writing that down is the decision;
without it the conversion ends up in three places and disagrees with itself.

**Gave up:** three things.

Every client divides by 100, and any client can forget. `1999` in a log needs context to
read.

`order_payments.amount` pays a **double conversion**. Stripe sends an integer, this schema
stores a decimal, the API serves an integer, so a value that was never anything but an
integer makes two round trips through `Decimal`. Storing that one column as cents would
remove both. Not doing it, because `numeric(10,2)` is exact and the conversion is lossless
at two decimal places, and because reopening the ERD costs a commit on a pass that is
already full.

And the omitted `currency` is a bet that this store stays single-currency.

**Why:** the constraint is not a preference, and it was measured rather than assumed.
Prisma represents a `numeric` column with `Prisma.Decimal`, which is Decimal.js, and
Decimal.js defines `toJSON` as `toString`. Verified directly:

```
JSON.stringify({ price: new Decimal('19.99'), total: new Decimal('1234.50') })
  ->  {"price":"19.99","total":"1234.5"}
```

So `{type: number}` is a contract the implementation contradicts on day one. Note the
second field: **`1234.50` comes back as `"1234.5"`**, because Decimal.js drops the trailing
zero. A decimal-string API would hand clients a value that needs re-padding before display,
which integer cents avoids entirely. That rules out the float option
before taste enters, and float is wrong for money regardless.

Between integer cents and a decimal string, Stripe decides it: its API already speaks
integer minor units, so cents at this boundary means the payment path contains no
conversion at all, and that is the one path where a rounding error costs real money. A
decimal string would also be exact, but JavaScript has no decimal type, so every client
parses `"19.99"` into a float anyway and the exactness is lost at the first arithmetic.

The `currency` omission is safe because **adding a field to a response is non-breaking for
a tolerant reader**, which is the normal case and the one this API's consumer is. It is not
universally safe: a client generated against a schema with `additionalProperties: false`,
or one validating responses strictly, would reject the new field. That is a real caveat and
not a reason to add the field now.
Getting the money *type* wrong is not reversible in the same way, which is why the effort
went there.

---

## 7. Status-code floor

**The question.** Which codes this API promises, and what each one means here. The brief
requires that a 400, a 401, a 404 and a 409 all render something.

**The distinctions worth pinning, because they are the ones a reviewer asks about.**

| Pair | The question it settles |
| --- | --- |
| 400 vs 422 | Malformed request, or well-formed but semantically rejected |
| 401 vs 403 | Not authenticated, or authenticated and not allowed |
| 403 vs 404 | Whether "you may not see this" leaks that the resource exists |
| 409 vs 422 | Conflict with current state, or invalid regardless of state |

**Chose:** the floor below. Full per-endpoint mapping and the header obligations are in
the reading note, `Week 2 - REST Design + NestJS Foundations/REST Design/HTTP Status Codes`.

| Situation | Code |
| --- | --- |
| Validation failure on any body | **400** |
| Missing, expired, or revoked token | 401, with `WWW-Authenticate` |
| Client hitting a manager-only endpoint | 403 |
| Client requesting another client's order | **404** |
| Resource genuinely absent | 404 |
| Email already registered, cancel after shipped, ordering more than the stock on hand | 409 |
| Setting a stock value below zero, or referencing a variant that does not exist | 422 |
| Reset-password rate limit | 429 |
| Stripe webhook, bad signature | 400, and see the note below |
| Stripe webhook, replay of an applied event | **200** |
| Uncaught | 500 |

**403 protects an action, 404 protects a fact.** Both appear in this spec for
authorization failures and the split is deliberate. 403 when the endpoint is forbidden
whichever resource is named, because the endpoint's existence is already public in this
document and refusing it leaks nothing. 404 when answering at all would leak the
existence of a specific row: `GET /v1/orders/8123` returning 403 tells an attacker that
order exists and belongs to someone else.

**Gave up:** precision on validation, and honesty on ownership.

422 is the semantically exact code for a body that parsed and then failed the rules, and
400 is the generic client error. That precision is given up because the `Problem` object
from item 2 already carries `errors[]`, so the status code was never the thing
discriminating a validation failure from anything else.

404-on-ownership means the API lies to a legitimate user who mistypes their own order id:
they are told it does not exist when it does. That is the accepted cost of not confirming
existence to an attacker walking ids.

**Why:** 400 is Nest's `ValidationPipe` default, so choosing it means the contract and the
framework agree without configuration, and every override is a place they can silently
drift apart.

404-over-403 is the standard leak-prevention answer and the source states it outright: 404
is the documented choice *"when the server does not wish to reveal exactly why the request
has been refused."* Order ids are plain integers in this schema, not opaque, so a client can
guess them, and a 403/404 difference turns guessing into an enumeration of which orders
exist. Note this does not depend on the ids being strictly sequential: `store.dbml` declares
`id integer [primary key]` with no `increment`, so nothing in the ERD promises a sequence.
Guessability is enough.

**Week 3 consequence, recorded because the implementation will drift here.** CASL throws its
own `ForbiddenError`, from `@casl/ability`. Measured 2026-08-19: its prototype chain is
`Error -> Object`, and it carries neither `.status` nor `.getStatus()`, so it is **not** a
Nest `HttpException`. An uncaught one is therefore rendered as **500**, not 403. Two
mappings are needed, not one: `ForbiddenError` to a 403 for role failures, and to a 404 for
ownership failures per the rule above. Every `409` promised above also needs Prisma `P2002`
mapped, or it surfaces as a 500 and the contract lies.

The **stock split** is the 409-versus-422 distinction from the table above, applied twice
and easy to misread as a contradiction. Ordering 5 units when 3 remain is a conflict with
current state: restock and the same request succeeds, so 409. Setting stock to -5, or
naming a variant id that does not exist, is invalid whatever the state, so 422.

The webhook `200` on replay is not a style choice. Stripe's own documentation: *"Stripe
attempts to deliver events to your destination for up to three days with an exponential
back off in live mode."* Returning 409 for a duplicate therefore buys three days of
retries. Stripe also documents the dedup strategy directly, recommending that endpoints log
processed event ids and skip already-logged ones, which is what `UNIQUE(stripe_reference)`
in the ERD implements at the database instead of in memory.

Note that Stripe counts **every** 4xx as a delivery failure and retries it, the 400 above
included. That is harmless here only because a genuine Stripe delivery carries a valid
signature, so the 400 path is unreachable for real traffic. Their signature check also has
a default 5-minute timestamp tolerance, which is the replay-attack defence and is separate
from the application-level dedup above.

---

## 8. Token model, and what the contract inherits from it

**Not open.** Mentor item 4 shipped on 2026-08-18 as `abfd505`: a `refresh_tokens` table,
which is `REVIEW.md` B7's finding accepted and its `tokens_valid_from` fix rejected. See
`4-database/3-erd/DECISIONS.md` row 4.

What is open is writing down what that forces on this document, before the auth section is
authored against a different assumption.

- Does `POST /auth/refresh` exist, and what does it accept and return?
- What does `POST /auth/signout` do, and what does it return?
- What does a 401 mean here: access token expired, refresh row deleted, or both?
- **The revocation lag.** A signed access token stays valid until it expires, so sign-out
  revokes the future, not the present. That bound is the access-token lifetime. State the
  number in `info.description` rather than leaving it implicit; it is the first thing a
  reviewer will probe.

**Chose:** access token 15 minutes, refresh token 7 days, rotation on every refresh,
per-device sign-out, and a typed 401. In full:

**Lifetimes.** Access token 15 minutes, refresh token 7 days. Both stated in
`info.description`, not left implicit.

**`POST /v1/auth/refresh`.** Refresh token in the request body, not a cookie. **Rotates on
every use:** the presented row is deleted and a new one issued. If a refresh token that has
already been rotated is presented again, every refresh row for that user is deleted, on the
assumption that the token was stolen and replayed.

**`POST /v1/auth/signout`.** Deletes the presented device's row only, returns 204. Password
change and password reset delete **every** row for that user.

**401 means "this access token is not usable, try refreshing."** The `Problem.type` from
item 2 says which case it is: token expired, refresh row gone, or credentials rejected.

**Gave up:** four things.

Rotation costs a write on every refresh, where reuse would have cost none, and it adds a
reuse-detection path that has to be implemented and tested rather than described.

A body-carried refresh token is readable by JavaScript, so XSS can steal it. An `httpOnly`
cookie would not be.

Per-device sign-out plus kill-all-on-password-change is two code paths where one would do.

And 15 minutes is a real window: an evicted attacker keeps a working access token for up
to 15 minutes after a password reset. Nothing here closes that; the decision is to bound
it and say so.

**Why:**

**Body over cookie** because the cookie trades an XSS problem for a CSRF problem, needs
`SameSite` and probably a CSRF token, is awkward for a non-browser client, and breaks the
Swagger "try it out" check the brief requires. The XSS exposure is accepted with that
named as the reason.

**Rotation** because "what if the refresh token is stolen" is the obvious follow-up to
choosing a token table over `tokens_valid_from`, and without rotation the honest answer is
"it works for seven days and I never find out." With rotation a stolen token is usable
once, and the replay is the detection signal.

**Per-device sign-out, all-devices on password change**, because these answer different
questions. Signing out on a laptop should not kill a phone. But the password-reset email
exists precisely so a user can evict an attacker, and per-device sign-out cannot do that,
so the eviction case gets the broader delete. This also settles item 9 below, since it is
the same mechanism.

**A typed 401** because a bare one leaves the client unable to distinguish "refresh and
retry" from "send them to the login screen", and a client that guesses will loop. This is
the payoff for RFC 9457 in item 2.

**Stating the lifetime** because the revocation lag is this design's known weakness and it
is currently undocumented, which is the worst state for it to be in. Written down it is a
bounded property with a number attached rather than a hole a reviewer discovers. 15 minutes
is conventional and defensible in both directions: shorter means more refresh traffic,
longer means a wider eviction window.

---

## 9. Authenticated password change

**The question.** The Challenge doc's email trigger is *"when the user changes their
password"*, which is broader than the forgot/reset flow. Does a guarded
`PATCH /users/me/password` exist, or is reset the only path a password can change by?

**Why it belongs next to item 8.** It is the same invalidate-live-sessions question. If
changing a password should kill other devices, that is refresh-token deletion, and the
endpoint has to say so.

**Chose:** `PATCH /v1/users/me/password` exists. Guarded. Body carries the current
password and the new one. Wrong current password is **401**, not 403, because it is an
authentication failure rather than a permissions one. On success it fires the same
password-change email as the reset flow, deletes **every** refresh row for that user
including the caller's own, and returns 204. The caller signs in again.

So a password changes by exactly two doors, and both end in the same place: this endpoint,
and the forgot/reset flow.

**Gave up:** one more operation, one more guard, and a second entry point into the email
and session-eviction paths, which is a second place they can be got wrong. Deleting the
caller's own refresh row also means the flow ends by kicking the user out, which reads as
hostile unless the client explains it.

**Why:** the brief's email trigger is *"when the user changes their password"*, which is
wider than forgot/reset. Without this endpoint a signed-in user who simply wants a new
password has to sign out and ask for an email, and the brief's wording is only partly
met.

The cost is genuinely small because item 8 already built the interesting half. Killing
every session on a password change was decided there, so this endpoint reuses that
mechanism rather than introducing one.

Requiring the current password is what makes it a re-authentication rather than a
privilege escalation: a stolen access token, valid for up to 15 minutes under item 8,
cannot be used to seize the account outright. That is the same 15-minute window named
there, closed at the one endpoint where it would do the most damage.

Deleting the caller's own row is deliberate. A credential change should not leave any
session alive on the old credential, including the one that made the change.

---

## Deferred to the operations that use them

Not cross-cutting enough to block authoring. Decided at first use and recorded here after.

- **Id exposure.** Sequential integers from the ERD, or opaque ids.
- **Filter and sort parameter naming.** Settled when order history is authored, since it
  carries all five filters.
- **Webhook endpoint convention.** Settled with the Stripe endpoint.
- **CORS and exposed headers.** Not expressible in OpenAPI; belongs in the Week 3 notes.
