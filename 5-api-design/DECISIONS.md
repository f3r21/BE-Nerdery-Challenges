# API design decisions

Written against ERD commit `8d47aae` on `challenge/erd`.

Every decision below appears in **every** operation. Retrofitting any one of them is a
full-document rewrite, which is why they are settled before the first path is typed.

Same shape as `4-database/3-erd/DECISIONS.md`: what was chosen, what it cost, and why.
A decision with no "Gave up" line is not a decision, it is a default nobody examined.

## The ten calls

| # | Question | Chose |
| --- | --- | --- |
| 1 | Version in the path | `/v1` prefix, carried in `servers.url` |
| 2 | Error shape | RFC 9457 Problem Details, `application/problem+json` |
| 3 | Pagination | `{data, meta}` envelope, `offset` / `limit`, `meta.total` |
| 4 | Field casing | `camelCase`, query parameters included |
| 5 | Date-time | RFC 3339 with `Z`, full datetimes on filters, `createdFrom` inclusive and `createdTo` exclusive |
| 6 | Money | Integer minor units (cents), no `currency` field |
| 7 | Status codes | 400 on validation, 404 on another client's order. 403 protects an action, 404 protects a fact |
| 8 | Tokens | 15 min access, 7 day refresh, rotation on use, per-device sign-out, typed 401 |
| 9 | Password change | `PATCH /v1/users/me/password` exists, kills every session |
| 10 | Path naming | A segment is a noun when a row is addressable, a `kebab-case` verb when not |

Items 2, 8 and 9 depend on each other: item 2's `Problem.type` is what makes item 8's typed
401 work, and item 8's session eviction is what makes item 9 cheap. Item 10 depends on items
1, 4 and 8. It puts no version prefix on a path key (item 1 puts it in `servers.url`) and
spells a verb `kebab-case` while item 4 keeps query parameters `camelCase`. It exists at all
because item 8's refresh table gave sessions a row worth naming.

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
client at once. The brief's breaking-change table lists changing a status code as a break,
so the escape hatch is not hypothetical for this API. Adding a value to a response enum is
also breaking for a consumer with an exhaustive switch, which is my own reading and is not
in the table.

---

## 2. One error schema, everywhere

**The question.** A single `Error` component that every non-2xx response `$ref`s, and what
its fields are.

**What it costs either way.** One shape means every client writes one error handler.
Per-endpoint shapes carry more detail but nothing can consume them generically. Leaving the
shape unpinned means inheriting Nest's default, `{statusCode, message, error}`, where
`message` is an **array** from `ValidationPipe` and a **string** from a plain
`NotFoundException`.

**Chose:** RFC 9457 Problem Details, which obsoletes RFC 7807. One `Problem` component
`$ref`d by every non-2xx response, served as `application/problem+json`, with members
`type`, `title`, `status`, `detail` and `instance`. Validation failures use the spec's
extension-member mechanism to add an `errors` array of `{field, message}`, which is where
`ValidationPipe`'s array goes.

RFC 9457 registers `about:blank` for a problem with no semantics beyond its HTTP status
code, and treats it as the value when `type` is absent. A type URI is minted only where the
status code alone cannot tell a client which failure it hit: the three 401 cases and the
three 409 cases.

**The six members**, as a closed enum in `components/schemas/ProblemType` so the linter
enforces them across every operation rather than each one inventing its own spelling:

| URI | Status | Why the code alone is not enough |
| --- | --- | --- |
| `.../invalid-credentials` | 401 | Wrong email or password at sign-in |
| `.../access-token-expired` | 401 | Refresh and retry |
| `.../refresh-token-unknown` | 401 | Unknown or already rotated. Send the user to sign in |
| `.../email-taken` | 409 | Sign-up against an existing account |
| `.../order-not-cancellable` | 409 | Already shipped |
| `.../insufficient-stock` | 409 | Fewer units on hand than requested |

A client that cannot separate the three 401s loops between refreshing and re-authenticating.
A client that cannot separate the three 409s shows the wrong message.

**The enum will grow before release, and that is not a breaking change.** Item 1 argues that
adding a value to a response enum breaks a consumer with an exhaustive switch, and that is
true of a *released* contract. This one has no consumer yet. Payment declined and
promo-code-invalid are the likely additions when orders and payments are authored. The rule
starts at first release: after that, adding a member is a minor version and removing one is
breaking.

**`https`, not a `tag:` or `urn:` URI.** RFC 9457 recommends
resolvable URIs, and says switching to a non-resolvable one later would itself be breaking.
Its section 3.1.1 offers `tag:` for APIs that cannot serve documentation. I can serve it, so
the choice is `https` and **Week 3 serves a short page at `/problems/{slug}`**, one per
member. The domain is the store's canonical one and is deliberately not the `servers` URL,
because a type URI has to be identical in development and in production.

Consumers `SHOULD NOT` dereference automatically, per the same section, so nothing breaks in
the window before those pages exist.

**Gave up:** three things. Nest ships no support for it, so this costs a global exception
filter in Week 3 plus an explicit `P2002` mapping, and the filter is now load-bearing
rather than optional. `status` duplicates the HTTP status code in every error body, which
is redundancy the standard accepts and I inherit. And the `type` URIs are a promise: a
reviewer can ask what is at the other end of one.

**Why:** at least three places in this API return the same status code for different
reasons, and the code alone cannot say which. String-matching `message` is the alternative,
and it breaks the moment the wording changes.

The remaining choice was between inventing a shape and citing one. RFC 9457 is an IETF
standard with tooling across languages, and its extension-member rule means the
validation-error array fits without leaving the standard. Inventing
`{code, message, details[]}` would have been slightly lighter and would have needed
defending as a local invention instead.

---

## 3. Pagination envelope

**The question.** What a collection response looks like. Bare array, or an object wrapping
`data` plus metadata. Offset/limit, page/size, or cursor. What the metadata contains.

**What it costs either way.** A bare array is simpler and cannot carry a total count.
Offset pagination is easy and drifts when rows are inserted mid-scan. Cursor pagination is
stable and cannot jump to page 7.

**Chose:** an envelope, `{ data: [...], meta: { total, limit, offset } }`, with `offset` and
`limit` as query parameters. `limit` has a default and a documented maximum so an unbounded
request cannot ask for the whole table. Products, categories, order history and anything
added later use this shape, without exception, because two collections that paginate
differently is what a review round finds first.

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
results. Offset over cursor follows from the same place: page numbers need addressable
pages.

Offset also matches Prisma's `skip` and `take` directly, so the contract and the Week 3
query are the same idea rather than a translation.

---

## 4. JSON field casing

**The question.** `camelCase`, `snake_case`, or the ERD's own column names.

**What it costs either way.** The ERD is `snake_case`. Prisma will hand you whatever the
schema says. A JSON API in `camelCase` needs a mapping layer; one in `snake_case` leaks the
column names into the contract and couples the two.

**Chose:** `camelCase` for every JSON field, and for **query parameters too**:
`minTotal`, `maxTotal`, `createdFrom`, not `min_total`. The schema stays `snake_case`, and
the two are deliberately different vocabularies.

**Gave up:** a mapping layer, and the duplication that comes with it. Every field now has
a column name and a wire name, and both are maintained. In Week 3 that is `@map("created_at")`
in the Prisma schema or `@Expose({ name })` in a serializer, one line per field. It also
means a field can drift: the column and the property can disagree, and nothing catches it
except review.

**Why:** the coupling is the thing being avoided, and this week proves it is not
hypothetical. `user_auth_data` becomes `users` in the Saturday ERD pass because a reviewer
asked, and the rename is still pending: `challenge/erd` at `8d47aae` reads `user_auth_data`
today. That is the point rather than an excuse, because the contract is already written and
the rename will not touch it. If
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
`?createdFrom=2026-08-01T00:00:00Z&createdTo=2026-09-01T00:00:00Z`, not
`2026-08-31T23:59:59Z`, which the half-open rule below avoids.

Range semantics, pinned here so no operation has to decide it: **`createdFrom` is inclusive,
`createdTo` is exclusive.** Half-open, so consecutive ranges tile without overlapping or
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

Full datetimes on the filter make the client state the instant it means. Half-open intervals
remove the second ambiguity. With an inclusive `createdTo`, "give me August" and "give me
September" either both claim midnight on the 1st or neither does, and `23:59:59Z` silently
drops anything in the final second.

`format: date-time` is also the OpenAPI-native spelling, so the linter and any generated
client validate it without a custom pattern.

---

## 6. Money representation

**The question.** Integer minor units (cents), a decimal string, or a float.

**What it costs either way.** Integer cents match what Stripe charges and cannot round
wrong, and every client divides by 100. A decimal string is readable and forces every client
to parse before arithmetic. A float is the one option that is simply incorrect for money.
Doing nothing is not neutral: `numeric(10,2)` becomes a Prisma `Decimal`, and
`JSON.stringify` renders a `Decimal` as a **string**, so `{type: number}` is a contract the
implementation contradicts on day one.

**Chose:** integer minor units, everywhere and without exception. That is `price`,
`unitPrice`, `lineTotal`, `subtotal`, `total`, and the `minTotal` and `maxTotal` query
parameters. Mismatching the parameters against the response fields is how a frontend divides
by 100 in one place and not the other. Every money field is `type: integer` and carries a value
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

Between integer cents and a decimal string, Stripe decides it. Its API already speaks integer
minor units, so cents at this boundary leave the payment path with no conversion at all. That
is the one path where a rounding error costs real money. A decimal string would also be
exact, but JavaScript has no decimal type, so every client parses `"19.99"` into a float
anyway and the exactness is lost at the first arithmetic.

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

404-over-403 is the standard leak-prevention answer, and the source states it outright. 404
is the documented choice *"when the server does not wish to reveal exactly why the request
has been refused."* Order ids are plain integers here, not opaque, so a client can guess
them. A 403 or 404 difference then turns guessing into an enumeration of which orders exist. Note this does not depend on the ids being strictly sequential: `store.dbml` declares
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

**The question.** Mentor item 4 shipped on 2026-08-18 as `abfd505`: a `refresh_tokens`
table, which is `REVIEW.md` B7's finding accepted and its `tokens_valid_from` fix rejected.
See `4-database/3-erd/DECISIONS.md` row 4. What it forces on this document is open, and the
auth section should not be authored against a different assumption.

- Does `POST /auth/refresh` exist, and what does it accept and return?
- What does `DELETE /auth/sessions/current` do, and what does it return?
- What does a 401 mean here: access token expired, refresh row deleted, or both?
- A signed access token stays valid until it expires, so sign-out revokes the future, not
  the present. How long is that lag, and where is the number written down?

**Chose:** access token 15 minutes, refresh token 7 days, rotation on every refresh,
per-device sign-out, and a typed 401. Both lifetimes are stated in `info.description`, not
left implicit. In full:

**`POST /v1/auth/refresh`.** Refresh token in the request body, not a cookie. **Rotates on
every use:** the presented row is deleted and a new one issued. If an already-rotated token
is presented again, every refresh row for that user is deleted, on the assumption that it
was stolen and replayed.

**`DELETE /v1/auth/sessions/current`.** Deletes the presented device's row only, returns 204. Password
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
to 15 minutes after a password reset, and nothing here closes that.

**Why:**

**Body over cookie** because the cookie trades an XSS problem for a CSRF problem, needs
`SameSite` and probably a CSRF token, is awkward for a non-browser client, and breaks the
Swagger "try it out" check the brief requires.

**Rotation** because "what if the refresh token is stolen" is the obvious follow-up to
choosing a token table over `tokens_valid_from`. Without rotation the honest answer is
"it works for seven days and I never find out." With rotation a stolen token is usable
once, and the replay is the detection signal.

**Per-device sign-out, all-devices on password change**, because signing out on a laptop
should not kill a phone. But the password-reset email exists precisely so a user can evict
an attacker, and per-device sign-out cannot do that, so the eviction case gets the broader
delete. This also settles item 9 below, since it is the same mechanism.

**A typed 401** because a bare one leaves the client unable to distinguish "refresh and
retry" from "send them to the login screen", and a client that guesses will loop. This is
the payoff for RFC 9457 in item 2.

**Stating the lifetime** because the revocation lag is this design's known weakness, and an
undocumented weakness is a hole a reviewer finds rather than a bounded property with a
number on it. 15 minutes is conventional and defensible in both directions: shorter means
more refresh traffic, longer means a wider eviction window.

---

## 9. Authenticated password change

**The question.** The Challenge doc's email trigger is *"when the user changes their
password"*, which is broader than the forgot/reset flow. Does a guarded
`PATCH /users/me/password` exist, or is reset the only path a password can change by?
It is item 8's invalidate-live-sessions question again: if changing a password should kill
other devices, the endpoint has to delete refresh rows and say so.

**Chose:** `PATCH /v1/users/me/password` exists. Guarded. Body carries the current
password and the new one. Wrong current password is **401**, not 403, because it is an
authentication failure rather than a permissions one. On success it fires the same
password-change email as the reset flow, deletes **every** refresh row for that user
including the caller's own, and returns 204. The caller signs in again.

**Gave up:** one more operation, one more guard, and a second entry point into the email
and session-eviction paths, which is a second place they can be got wrong. Deleting the
caller's own refresh row also means the flow ends by kicking the user out, which reads as
hostile unless the client explains it.

**Why:** without this endpoint a signed-in user who simply wants a new password has to sign
out and ask for an email, and the brief's email trigger is only partly met.

The cost is small because item 8 already decided that a password change kills every
session, so this endpoint reuses that mechanism.

Requiring the current password makes it a re-authentication rather than a privilege
escalation: a stolen access token, valid for up to 15 minutes under item 8, cannot be used
to seize the account outright. That closes item 8's window at the one endpoint where it
would do the most damage.

The caller's own row goes too: a credential change should not leave any session alive on
the old credential.

---

## 10. Path segment naming

**The question.** Does a path segment name a resource or an action, and how is it spelled.

**What it costs either way.** All-verbs is what this file's prose said until today. It is
consistent and simple, and it leaves `refresh_tokens.device_name` with no endpoint that reads
it. All-nouns is the purer reading of Naming REST Resources, and it forces a noun onto two
operations that have no row behind them.

**Chose:** a segment is a noun when the client can address a row, and a verb when it cannot.
Verbs are spelled `kebab-case`. Query parameters stay `camelCase` per item 4, so a segment and
a parameter in the same URL follow different rules on purpose. The `/v1` prefix stays in
`servers.url` per item 1, so a path key carries no prefix even where the prose here quotes a
full URL.

| Operation | Path | Row the client can address |
| --- | --- | --- |
| Sign in | `POST /auth/sessions` | Yes, it creates one |
| List my devices | `GET /auth/sessions` | Yes, `device_name` exists to render it |
| Sign out this device | `DELETE /auth/sessions/current` | Yes, the one it presents |
| Sign out another device | `DELETE /auth/sessions/{id}` | Yes |
| Rotate the token | `POST /auth/refresh` | A row exists, the client holds a token not an id |
| Request a reset | `POST /auth/forgot-password` | No |
| Complete a reset | `POST /auth/reset-password` | No |
| Sign up | `POST /users` | It creates one |

**Gave up:** two things. Consistency, because the reader now has to learn one rule instead of
none, and a rule that splits is a rule that can be applied wrongly at the margin. And
`PATCH /password-resets/{token}`, which is where the noun form runs out: it puts a secret in a
path segment, and path segments land in access logs and in `Referer` headers. The reset token
stays in the request body, so those two operations keep verbs on security grounds rather than
taste.

**Why:** the resource is already in the ERD. `refresh_tokens` carries an `id` and a
`device_name`. Calling the path `/auth/sessions` describes something that exists. Calling it
`/auth/sign-out` hides it, and leaves a column in the schema that no endpoint ever reads.

Item 8 evicts an attacker by deleting every refresh row on a password change. That works, and
it is blunt: you lose every other device to get rid of one. `DELETE /auth/sessions/{id}` is the
same need at the right granularity, and it costs one operation, because the row it deletes was
always going to be there.

`forgot-password` has no row behind it, so there is nothing to name, and inventing
`/password-resets` for consistency alone would put a reset token in a path segment.

---

## Deferred to the operations that use them

Not cross-cutting enough to block authoring. Decided at first use and recorded here after.

- **Id exposure.** *Settled 2026-08-20, at the first `{id}` in the document.* **Sequential
  integers**, uniformly, as the ERD already has them. Opaque ids protect against enumeration,
  and enumeration is only a vulnerability if guessing an id returns the data. CASL and item 7's
  404-on-ownership are what stop that. Obscurity on top of correct authorization buys nothing,
  and on top of broken authorization it hides the bug from the tests instead of fixing it.

  Checked against the brief rather than assumed: the only ids that leave the API are product
  ids, in the shareable payment links at `Challenge - T-Shirt Store API.md:107` and the stock
  notification email at `:122`. The catalog is public, so enumerating it leaks nothing. No
  order id travels anywhere, because the brief has no order confirmation email.

  **What would overturn this:** an id reaching a place authorization does not cover, such as an
  order confirmation email, a support chat, or a `Referer` header. A real store sends that
  email. The fix is not UUID primary keys but a separate customer-facing order number, so
  orders carry an opaque `orderNumber` beside the integer key. That column is an ERD change,
  not a contract change, and it is scheduled with the Saturday ERD pass.

  **Gave up:** enumerability, and the option to change course without a break. Every product
  id in this contract is guessable, so anyone can walk the catalog, which costs nothing while
  the catalog is public. The second cost grows. An id sits in the response body of nearly every
  operation, so moving to opaque ids later changes the type of a field on `Product`, `Order`,
  `CartItem` and every id parameter at once. The week's own table calls a type change a break,
  and 36 operations now depend on the choice.
- **Add-to-cart semantics.** *Settled 2026-08-21, before the cart block.* **One row per variant
  per cart, addressed by the variant id, with the request setting the quantity rather than
  adding to it.** Item 10 answers this: a segment is a noun when the client can address a row,
  and the client addresses this row by the variant id it just chose. Nothing needs minting,
  which is the one condition `PUT vs POST` attaches to a create that is not a POST. The cart is
  the only place in this contract where that holds.

  The reason to care is not tidiness. Setting a quantity is idempotent, and RFC 9110 9.2.2
  defines idempotency by the intended effect on the server, so the same request sent twice
  leaves the cart in the state the client asked for. An increment does not have that property,
  and add-to-cart is the operation most likely to be sent twice, because it is the one people
  press again on a slow connection.

  **Gave up:** the reading's "always use POST for CREATE". A client that wants one more of
  something now sends the resulting total rather than a delta, so it has to know the current
  quantity. It does, because it is rendering the cart, but that is an assumption this contract
  depends on. The other cost is an ERD change. `shopping_cart_items` carries no uniqueness
  marker today, so two rows for the same variant in one cart are legal. `UNIQUE (cart_id,
  product_variant_id)` is already on the ERD's agreed-and-not-done list, and this decision
  depends on it. Without that constraint the contract promises something the schema does not
  enforce.
- **B4b, what "stock reaches 3" counts.** *Settled 2026-08-21. It changes no operation here,
  and is recorded because it came up while authoring Week 2.* **A single variant reaching 3
  fires the notification, and the audience stays everyone who liked the parent product.**

  The brief says "when the stock of a product reaches 3" and "notify users who liked the
  product", so it is written as though stock lived on the product. It does not:
  `product_variants` carries `stock`, which is the more correct model, because a store counts
  Medium Black separately from Large White. The mismatch is the brief's, not the ERD's.

  Only the trigger needed a decision. `product_likes` is keyed `(user_id, product_id)`, which
  already matches the audience the brief asks for.

  **Gave up:** precision, in favour of firing at all. Summing stock across variants is the
  literal reading and it fails silently: a product with a hundred Smalls and no Larges never
  reaches 3, so the person waiting on a Large is never told. Keying likes to the variant would
  be exact and wrong for people, who like a shirt rather than a size. The cost is noise:
  someone waiting on a Large is emailed when a Medium runs low. One thing stays open. No
  `stock_notifications` table exists, so nothing records that a mail was sent and the same
  person can be told repeatedly. That gap is on the ERD's agreed-and-not-done list and belongs
  to the Saturday pass.
- **Scope, and the operation count it produces.** *Settled 2026-08-21, when authoring
  stopped.* **The three Optional Features are out. Features 1 to 10 are in, and the contract
  holds 36 operations.**

  The brief marks 11 (delivery person), 12 (the `delivered` state) and 13 (promo codes) as
  optional. They are cut. Two traces stay on purpose. `OrderStatus` keeps `delivered` and
  `Role` keeps `delivery_person`, so the contract and the Week 1 ERD describe the same domain.
  `orders` keeps both `subtotal` and `total`, always equal without a discount. Adding an
  optional field later is the one change the week's own table calls safe, so shipping the pair
  now makes promo support additive rather than a break.

  **Gave up:** the Extra Points, and the ability to say the contract covers the whole ERD.
  `promo_codes`, `assigned_delivery_person_id` and `orders.discount_amount` are columns no
  operation in this document reads or writes. A reviewer can find schema this contract does
  not reach, and the honest answer is that it was cut rather than missed.

  **The count is 36, not the 39 an earlier derivation gave.** All three differences follow from
  decisions in this file, not from omissions:

  | Where | Planned | Actual | Why |
  | --- | --- | --- | --- |
  | Catalog read | 7 | 6 | Images are embedded in the product detail. A separate image read would rebuild the N+1 that the summary and detail split exists to avoid |
  | Catalog write | 10 | 9 | Disabling is `isActive` on `PATCH /products/{id}`. Item 10 makes it a field on an addressable row, not a verb endpoint |
  | Cart | 5 | 4 | The add-to-cart decision above makes the request set an absolute quantity, so adding an item and changing its quantity are the same idempotent call |

  Re-derive: `grep -c operationId openapi.yaml`.
- **Filter and sort parameter naming.** *Settled 2026-08-21, with the order history.*
  **`status`, `createdFrom`, `createdTo`, `minTotal`, `maxTotal`, declared once in
  `components/parameters` and referenced by both order collections.**

  `camelCase` per item 4, which covers query parameters. The date pair follows item 5:
  `createdFrom` is inclusive and `createdTo` is exclusive, so one calendar day is `createdFrom`
  that day and `createdTo` the next. The price pair reads the order total in minor units per
  item 6, so a filter and the field it filters use one representation.

  **Gave up:** a sort parameter, and the shorter names. Nothing in this contract sorts: the
  brief asks for filters and pagination and never for an order, so a `sort` parameter would be
  a guess at a requirement. `createdFrom` is longer than `from`, the first choice. `from` reads
  as a date on an order collection and as nothing in particular anywhere else, and a parameter
  declared once in `components` is copied to every collection that follows.
- **Webhook endpoint convention.** *Settled 2026-08-21, with the Stripe endpoint.*
  **`POST /webhooks/stripe`, one route for every event type, `security: []`, and a 200 on a
  replay.**

  It sits under `/webhooks` rather than beside the resources it changes, because a route
  belongs to whoever calls it and the caller here is Stripe. One route rather than one per
  event type, because Stripe signs the envelope and the signature has to be checked before the
  `type` field is trustworthy enough to route on.

  `security: []` is honest rather than lax. The bearer scheme does not apply, and the real
  credential is the `Stripe-Signature` header, which the operation declares as a required
  parameter. Item 7's floor already settled the two odd codes: a signature that fails
  verification is 400, and an event already applied is 200.

  **Gave up:** a route a human can read at a glance, and per-event typing in the contract. The
  request body is declared as an opaque Stripe event with `id` and `type` required, so the
  document says less about this payload than about any other. Typing both event shapes fully
  would pin this contract to a Stripe API version it does not control.

  Stripe retries, so a replay must not lower the stock twice.
  `order_payments.stripe_reference` is unique in the ERD, which is what makes the
  already-applied check reliable rather than a best effort. That column came out of the Week 1
  review, and this is the operation that needs it.
- **CORS and exposed headers.** Not expressible in OpenAPI; belongs in the Week 3 notes.
