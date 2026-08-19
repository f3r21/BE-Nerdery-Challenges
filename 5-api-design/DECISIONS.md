# API design decisions

Written against ERD commit `8d47aae` on `challenge/erd`.

Every decision below appears in **every** operation. Retrofitting any one of them is a
full-document rewrite, which is why they are settled before the first path is typed.

Same shape as `4-database/3-erd/DECISIONS.md`: what was chosen, what it cost, and why.
A decision with no "Gave up" line is not a decision, it is a default nobody examined.

---

## 1. Version in the path, or not

**The question.** `/v1/products` or `/products`. If not in the path, then where: a header,
a media type, or nowhere at all.

**What it costs either way.** A path prefix is visible, cacheable and trivially routable,
and it commits you to the claim that a v2 could exist. No prefix is honest for a service
with one consumer, and adding a prefix later breaks every client at once.

**Chose:**

**Gave up:**

**Why:**

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

**Chose:**

**Gave up:**

**Why:**

---

## 3. Pagination envelope

**The question.** What a collection response looks like. Bare array, or an object wrapping
`data` plus metadata. Offset/limit, page/size, or cursor. What the metadata contains.

**What it costs either way.** A bare array is simpler and cannot carry a total count.
Offset pagination is easy and drifts when rows are inserted mid-scan. Cursor pagination is
stable and cannot jump to page 7.

**Applies to.** Products, categories, order history, and anything added later. The failure
mode is two collections that paginate differently, which the review round will look for.

**Chose:**

**Gave up:**

**Why:**

---

## 4. JSON field casing

**The question.** `camelCase`, `snake_case`, or the ERD's own column names.

**What it costs either way.** The ERD is `snake_case`. Prisma will hand you whatever the
schema says. A JSON API in `camelCase` needs a mapping layer; one in `snake_case` leaks the
column names into the contract and couples the two.

**Chose:**

**Gave up:**

**Why:**

---

## 5. Date-time format

**The question.** The wire format for `createdAt`, `changedAt`, `expiresAt` and every date
filter on order history.

**What it costs either way.** RFC 3339 with an explicit `Z` is unambiguous and is what
`format: date-time` means in OpenAPI. Epoch seconds are compact and unreadable in a log.
A naive local timestamp is the bug `timestamptz` was adopted to prevent, so it should not
reappear at the API boundary.

**Chose:**

**Gave up:**

**Why:**

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

**Chose:**

**Gave up:**

**Why:**

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

**Chose:**

**Gave up:**

**Why:**

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

**Chose:**

**Gave up:**

**Why:**

---

## 9. Authenticated password change

**The question.** The Challenge doc's email trigger is *"when the user changes their
password"*, which is broader than the forgot/reset flow. Does a guarded
`PATCH /users/me/password` exist, or is reset the only path a password can change by?

**Why it belongs next to item 8.** It is the same invalidate-live-sessions question. If
changing a password should kill other devices, that is refresh-token deletion, and the
endpoint has to say so.

**Chose:**

**Gave up:**

**Why:**

---

## Deferred to the operations that use them

Not cross-cutting enough to block authoring. Decided at first use and recorded here after.

- **Id exposure.** Sequential integers from the ERD, or opaque ids.
- **Filter and sort parameter naming.** Settled when order history is authored, since it
  carries all five filters.
- **Webhook endpoint convention.** Settled with the Stripe endpoint.
- **CORS and exposed headers.** Not expressible in OpenAPI; belongs in the Week 3 notes.
