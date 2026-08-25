# ERD Teardown: `store.dbml`

Schema review for the T-Shirt Store capstone. Thirteen required features checked
against the schema, one third-normal-form violation with its update anomaly, and
a list of the changes deliberately **not** recommended.

**Subject:** `4-database/3-erd/store.dbml`
**Also read:** `DECISIONS.md`, `Challenge - T-Shirt Store API.md`
**Date:** 2026-08-14

| Broken | Partial | Clean | Findings | DECISIONS calls upheld |
| ------ | ------- | ----- | -------- | ---------------------- |
| 4      | 7       | 2     | 11       | 4 of 5                 |

`DECISIONS.md` is good work: five real trade-offs, each with the rejected
alternative named. Four of the five hold up under pressure. This document goes
after the fifth, and after everything the file doesn't mention.

---

## Part 1: Feature by feature

| #   | Feature                             | Verdict     | Why                                                        |
| --- | ----------------------------------- | ----------- | ---------------------------------------------------------- |
| 1   | Auth: sign up / in / _out_, reset  | **Partial** | Sign-out has no server-side representation                  |
| 2   | Products, variants, images          | **Partial** | Variants aren't unique; images have no primary              |
| 3   | Manager / Client roles              | Clean       | none                                                           |
| 4   | Manager CRUD + disable              | **Partial** | `delete` either fails forever or destroys order history     |
| 5   | Client browse / cart / like / orders| **Partial** | Inherits #9; duplicate cart lines possible                  |
| 6   | CASL, cancel before shipped         | **BROKEN**  | The cancel/ship race has no lock target                     |
| 7   | Stripe, both flows + webhooks       | **BROKEN**  | No idempotency, no stock floor                              |
| 8   | Stock notification at 3             | **BROKEN**  | No dedup, non-deterministic image, undefined grain          |
| 9   | Order history with filters          | **BROKEN**  | Price and status filters can't be indexed or pushed down    |
| 10  | Order status flow                   | **Partial** | `varchar` with no constraint on values or transitions       |
| 11  | Delivery person _(opt)_             | **Partial** | Depends on the #9 fix                                       |
| 12  | Full status history _(opt)_         | Clean       | What the history table is genuinely good at                 |
| 13  | Promo codes _(opt)_                 | **Partial** | `usage_limit` cannot be enforced                            |

---

### B1: There is no order total, and feature 9 requires filtering by one

The brief asks for a **price range (min/max)** filter with **limit and offset**
pagination. Today that query is:

```sql
SELECT o.id FROM orders o
JOIN order_items oi ON oi.order_id = o.id
WHERE o.user_id = $1 AND o.created_at BETWEEN $2 AND $3
GROUP BY o.id
HAVING SUM(oi.price_at_purchase * oi.quantity) - COALESCE(o.discount_amount,0)
       BETWEEN $4 AND $5
ORDER BY o.created_at DESC LIMIT 20 OFFSET 40;
```

You must aggregate every line item of every order the user has ever placed before
`HAVING` can reject a single one, and only then can `LIMIT` apply. No index can
help a predicate over an aggregate. Page 40 costs exactly what page 1 costs.

`order_payments.amount` is not a substitute: a `pending` or `cancelled` order has
no successful payment row, so filtering on it silently drops orders from the one
place they must appear.

The second argument is your own. `DECISIONS.md` #3 says a receipt has to reflect
what the customer actually paid. The total _is_ the receipt. Deriving it later
from line items is exactly the failure `price_at_purchase` exists to prevent.
Add shipping, tax, or a partial refund and the sum of the lines stops being what
was charged.

**Change:** `orders.subtotal_amount` and `orders.total_amount`, both
`numeric(10,2) NOT NULL`.

> **What it can do after:** filter order history by price range with an index
> range scan instead of a full aggregate, and render subtotal → discount → total
> as three stored facts rather than one stored fact and two guesses. Neither is
> possible today.

---

### B2: No current status on `orders`. Where I disagree with DECISIONS #4

Your reasoning is sound where it applies: status changes _are_ a sequence of
events, and feature 12 wants the full history. Keep the table. But you framed it
as a choice between the history table and a status column, and it isn't one.
You keep both. What you gave up isn't "a slightly more complex query." It's three
specific things.

#### (a) "Cancel before shipped" is not enforceable

```
req A (client cancels)              req B (manager ships)
SELECT ... ORDER BY changed_at      SELECT ... ORDER BY changed_at
DESC LIMIT 1  -> 'processing'       DESC LIMIT 1  -> 'processing'
INSERT 'cancelled'                  INSERT 'shipped'
COMMIT                              COMMIT
```

Nothing conflicts. `order_status_history` is append-only, so there is no row for
the two transactions to contend on. Postgres has nothing to serialize. The order
is now both cancelled and shipped, and which one "wins" is decided by microsecond
ordering on `changed_at`. A CASL guard cannot fix this: it runs before the
transaction and reads the same stale value.

With a status column it collapses to one statement:

```sql
UPDATE orders SET status = 'cancelled'
WHERE id = $1 AND status IN ('pending','paid','processing');
-- rowcount 0 -> already shipped -> 409
```

The row lock serializes them. One of the two gets zero rows back. That guarantee
costs one column and is unavailable at any price today.

#### (b) Feature 9's status filter can't be pushed down

Stack it on B1 and you are running a full aggregate _plus_ a per-order lateral to
resolve `max(changed_at)`, across the user's entire history, before
`LIMIT 20 OFFSET 40` can apply. Feature 11 has the same shape: "view assigned
orders (status: shipped)" becomes
`WHERE assigned_delivery_person_id = me AND <resolve latest history row per order> = 'shipped'`.

#### (c) Feature 8's "haven't purchased it yet" needs it

A cancelled order isn't a purchase, and a `pending` one isn't either. So the
notification query has to resolve current status _inside_ a four-table join, per
candidate user.

There is also nothing requiring the initial `pending` row to exist. An order with
zero history rows has no status at all, and the schema is fine with that.

**Change:** `orders.status` as a Postgres enum, `NOT NULL`. Keep
`order_status_history` exactly as it is.

> **What it can do after:** reject a cancel-after-ship atomically; serve
> status-filtered paginated history from a `(user_id, status, created_at DESC)`
> index; guarantee every order has exactly one current status. Today, none of the
> three.

---

### B3: Stripe webhooks can be applied twice

Stripe's delivery guarantee is **at-least-once**. Your handler commits, the
response times out, Stripe redelivers. Nothing in this schema stops the second
delivery from doing everything again: a second `order_payments` row, a second
`paid` row in the history, and a second `stock = stock - quantity`.

`stripe_reference` is not unique. That is the load-bearing omission, and it is
also the answer to question 2, worked through in Part 2.

**Change:** `UNIQUE (stripe_reference)` on `order_payments`. Optionally also
`UNIQUE (order_id, status)` on `order_status_history`. No status legitimately
repeats in your flow, so it blocks a duplicate `paid` row for free.

> **What it can do after:** `INSERT ... ON CONFLICT (stripe_reference) DO NOTHING`
> in the same transaction as the stock decrement, so a replay is rejected by the
> database. This cannot be done in application code: check-then-insert races
> against itself, and the whole point is that the two deliveries may be concurrent.

---

### B3b: Stock can go negative

`product_variants.stock` has no `CHECK (stock >= 0)`. The brief's "validate stock
availability before creating payment" is a read, then an HTTP round-trip to
Stripe, then a write, which is inherently racy. Two buyers on the last unit both pass
validation.

**Change:** `CHECK (stock >= 0)` on `product_variants`.

> **What it can do after:** the second concurrent decrement aborts instead of
> committing `-1`. Today it commits, you have sold inventory you don't have, and
> feature 8's threshold logic is now reading a nonsense number.

---

### B4: Feature 8 will email the same person repeatedly, and you can't detect it

Nothing records that a notification was sent. The brief mandates a queue, and
BullMQ retries failed jobs by default. If the mail provider 500s after delivering,
or the worker dies between send and ack, the job re-runs: it re-queries "liked P,
hasn't purchased P", gets the identical set, and emails all of them again. The
predicate does not change on retry, so it is not self-limiting.

**Change:** `stock_notifications(user_id, product_id, sent_at)` with
`UNIQUE(user_id, product_id)`.

> **What it can do after:** make the queue job idempotent, so it is safe to retry
> and safe to fire on every stock change. Today the job is not safe to retry,
> which means you either lose notifications or duplicate them. The schema offers
> no third option.

---

### B4b: "The stock of a product reaches 3" is undefined in this model

Likes are on `products`. Stock is on `product_variants`. A tee in four sizes ×
two colors has eight stock numbers. Is the trigger `SUM(stock) = 3` across the
product, or any single variant hitting 3? Both readings are defensible and they
produce different systems, and the dedup grain in B4 depends on which you pick.

This isn't a missing column. It's a missing decision, and it's the one
`DECISIONS.md` doesn't have.

**Change:** none to the schema. Pick a reading and write it down as decision #6.
A reviewer will ask.

---

### B4c: "Include the product's image" is non-deterministic

`product_images` has no `is_primary` and no `position`. The email job does
`ORDER BY id LIMIT 1`: whichever row happened to get the lowest id, and it
changes when a manager deletes and re-uploads.

**Change:** `is_primary boolean`, plus
`CREATE UNIQUE INDEX ON product_images (product_id) WHERE is_primary`.

> **What it can do after:** the manager chooses which image the customer sees in
> the low-stock email and as the catalog thumbnail. Today nobody chooses.

---

### B5: `order_items` snapshots price but not identity. Finish what DECISIONS #3 started

Your own reasoning: "a product's price change would retroactively alter every
past order." Correct, and identical for everything else on the receipt:

```sql
UPDATE products         SET name  = 'Vintage Wash Tee' WHERE id = 7;
UPDATE product_variants SET color = 'Midnight'         WHERE id = 31;  -- was 'Navy'
```

Every order ever placed now claims the customer bought a Vintage Wash Tee in
Midnight. They bought a Classic Tee in Navy. Same anomaly, same argument. The
snapshot just stopped one column short.

Feature 4's `delete` is the harder version. `order_items.product_variant_id` is a
hard FK, so a manager deleting a sold product either gets an FK error forever (in
which case `delete` isn't implemented) or cascades and erases order history (in
which case feature 9 isn't). `is_active` covers _disable_; the brief lists delete
and disable as separate operations.

**Change:** `product_name`, `variant_size`, `variant_color` on `order_items`,
plus `products.deleted_at`.

> **What it can do after:** render a two-year-old order exactly as it was
> purchased, and let a manager delete a discontinued product without an FK error
> and without destroying history. Today, neither.

---

### B6: Two missing unique constraints let duplicate rows exist

**`UNIQUE (product_id, size, color)` on `product_variants`.** Nothing stops two
rows for (product 7, Red, M) with stock 2 and stock 4. The catalog lists "Red / M"
twice, checkout decrements one arbitrarily, and B4b's threshold gives a different
answer per row.

> **What it can do after:** "the stock of a Red M" becomes a single well-defined
> number.

**`UNIQUE (cart_id, product_variant_id)` on `shopping_cart_items`.**

> **What it can do after:** "add to cart" twice becomes
> `ON CONFLICT DO UPDATE SET quantity = quantity + $1`. Today it's two rows, and
> the cart shows the same shirt on two lines.

---

### B7: Sign-out is in the brief and has nowhere to live

No sessions table, no refresh tokens, no `password_changed_at`. With a stateless
JWT, "sign out" can only mean the client discards its own copy; the token stays
valid until it expires.

The sharpest version: the brief pairs password reset with a _notification email_.
That email exists to tell the user their account may be compromised. The only
useful response is "kill the other sessions", and this schema cannot.

**Change:** `user_auth_data.tokens_valid_from timestamptz`. Reject any JWT whose
`iat` precedes it. Or a refresh-token table if you want per-device sign-out.

> **What it can do after:** a signed-out or post-reset token actually stops
> working. One column buys the whole thing.

---

### B8: `promo_codes.usage_limit` cannot be enforced

No counter, no redemptions table.
`SELECT COUNT(*) FROM orders WHERE promo_code_id = ?` returns the right number but
offers no lock target. N concurrent checkouts all read the same count and all
pass.

**Change:** `times_used integer NOT NULL DEFAULT 0`, incremented as
`UPDATE promo_codes SET times_used = times_used + 1 WHERE id = $1 AND times_used < usage_limit`
and checked by rowcount. Also: `discount_type` is an unconstrained `varchar`
(should be a two-value enum), and
`CHECK ((promo_code_id IS NULL) = (discount_amount IS NULL))` stops a discount
existing without a code.

> **What it can do after:** hold a 100-use limit against concurrent checkout,
> because the row lock serializes the increment. Today it can't.

---

### Cheap and real

- **`timestamp` → `timestamptz` everywhere.** The brief's extra credit is a Heroku
  deploy. A UTC dyno and a GMT-6 laptop currently disagree about whether a reset
  token has expired and which orders fall inside "January." After: they agree.
- **`numeric` → `numeric(10,2)`.** Unconstrained `numeric` accepts `19.999`;
  Stripe charges integer cents. After: you can't store a price Stripe can't charge.
- **`status varchar` → Postgres enum.** Four writers touch it: client, manager,
  webhook, delivery person. After: the database rejects `'Shipped'`.
- **Indexes on FK columns.** Postgres does not index the referencing side.
  `orders.user_id`, `order_items.order_id`, `product_variants.product_id`,
  `product_likes.product_id` and `order_status_history.order_id` are all
  sequential scans. Arguably out of scope for a week-1 ERD, but this file becomes
  your Prisma schema, and `@@index` lives in it.
- **Naming.** `user_auth_data` holds `first_name`/`last_name`. It's a users
  table. And singular/plural is inconsistent (`user_role` vs `products`).
  Cosmetic, but a reviewer will say it.

---

## Part 2: The third-normal-form violation

It's `order_payments`. Specifically: `stripe_reference` is a determinant that is
not a superkey.

```
order_payments(id, order_id, payment_method, stripe_reference, amount, status, created_at)
```

`stripe_reference` identifies a Stripe object: a PaymentIntent `pi_...` or a
Checkout Session `cs_...`. Stripe guarantees these are globally unique, and that
each has exactly one amount, one status, one order, and one flow type. So this
functional dependency holds in the real world:

```
stripe_reference  ->  { order_id, amount, status, payment_method }
```

Note `payment_method` in particular. The brief defines it as "Payment Link or
Payment Intent", which is literally the prefix of `stripe_reference`. It is
derivable from the determinant by string inspection.

Now check the definition. A relation is in 3NF iff for every non-trivial FD
`X -> A`, either `X` is a superkey or `A` is prime.

- `stripe_reference` is **not declared unique**, so it is not a superkey.
- `amount`, `status`, `payment_method` and `order_id` are all **non-prime**. The
  only candidate key is `id`.

**⇒ 3NF violated.** Equivalently: `id -> stripe_reference -> amount` is a textbook
transitive dependency of a non-key attribute on the primary key.

### The update anomaly

```sql
-- Stripe delivers payment_intent.succeeded. Handler commits, response times out.
INSERT INTO order_payments (order_id, payment_method, stripe_reference, amount, status)
VALUES (42, 'payment_intent', 'pi_3ABC', 149.00, 'succeeded');   -- id 101

-- Stripe redelivers the same event ~20s later. At-least-once. Nothing rejects it.
INSERT INTO order_payments (order_id, payment_method, stripe_reference, amount, status)
VALUES (42, 'payment_intent', 'pi_3ABC', 149.00, 'succeeded');   -- id 102

-- Customer refunds. The handler updates "the" payment row for this intent.
UPDATE order_payments SET status = 'refunded' WHERE id = 101;
```

```
SELECT id, status, amount FROM order_payments WHERE stripe_reference = 'pi_3ABC';

 101 | refunded  | 149.00
 102 | succeeded | 149.00
```

One real-world payment, two stored copies, one of them stale. That is the update
anomaly in its literal textbook form: a fact stored in more than one place, and an
update that touched one copy. Downstream, feature 9's "total amount paid" now
reports **298.00** on a 149.00 order, and the stock decrement ran twice.

### The fix

```sql
ALTER TABLE order_payments
  ADD CONSTRAINT uq_stripe_reference UNIQUE (stripe_reference);
```

`stripe_reference` becomes a candidate key, therefore a superkey, therefore the FD
no longer violates 3NF. Zero new columns.

> **What it can do after:** the webhook handler becomes
> `INSERT ... ON CONFLICT (stripe_reference) DO NOTHING` in the same transaction
> as the stock decrement, so a replay is rejected by the database, not by a
> check-then-insert in application code that races against itself. Today the
> schema actively permits the duplicate.

One nuance so you get this right: the constraint is correct because
`order_payments` is one row **per Stripe object**, mutated in place, which is
what the `status` column implies. If you ever model it one row **per event** (Stripe sends
`payment_intent.created`, `.succeeded` and `.payment_failed` all sharing the
same `pi_`), then the reference legitimately repeats and you'd need a
separate `stripe_events(event_id text primary key)` table instead. Your current
design says object-per-row. Keep it, and add the unique.

### Two things that look like violations and aren't

Be ready to defend both, because a reviewer will raise them.

- **`order_items.price_at_purchase`** duplicates `product_variants.price`. Not a
  violation: it is a temporally distinct fact. "The price at 14:32 on 2026-03-11"
  is not the same attribute as "the price now." `DECISIONS.md` #3 already says
  this correctly.
- **`orders.discount_amount`** looks derivable from the promo code. It isn't: for
  a percentage code the discount depends on the order subtotal too, so
  `promo_code_id -> discount_amount` does not hold: no FD, no violation. And even
  for a fixed-amount code it's a deliberate snapshot, for the same reason as
  above. Keep it.

---

## Part 3: What I am not asking you to change

You said you'd ask what the schema could do after each change. Here is where the
honest answer is _nothing_.

| Thing                                                        | Why it stays                                                                                                                                          |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **One role per user**, DECISIONS #1                          | Right call, right reasoning. Every ability in the brief is per-role, not per-user-with-many-roles.                                                      |
| **Fixed `size`/`color` columns**, DECISIONS #2               | Right. EAV here buys flexibility the brief never asks for and taxes every catalog query.                                                                |
| **`product_categories` many-to-many**, DECISIONS #5          | Right, and the Pagila precedent is a good justification.                                                                                                |
| **`price_at_purchase`**, DECISIONS #3                        | Right. B5 extends it; it does not reverse it.                                                                                                           |
| **`product_likes.created_at`**                                 | Nice for analytics. Nothing in the thirteen features reads it. Skip.                                                                                    |
| **Variant-level `is_active`**                                  | The brief only says disable _products_. Skip.                                                                                                           |
| **S3 key instead of full URL in `image_url`**                  | Images are public to logged-out users, so there is no presigning to do. The URL is fine.                                                                 |
| **DB-level check on `assigned_delivery_person_id`'s role**     | Doable with `UNIQUE(id, role_id)` and a composite FK, but it hardcodes a role id into a constraint, and a CASL guard already covers it on an optional feature. |
| **`changed_by` on `order_status_history`**                     | Real stores need it: "did the client cancel, or did we?" This brief doesn't ask. One nullable FK if you want it, but it unblocks nothing.               |
| **`sku` on `product_variants`**                                | The brief says "SKUs", so the vocabulary is off, but nothing needs a human-readable code that `product_variants.id` doesn't already provide.            |

---

## If you take four things

| Change                     | Buys                                                                        | See |
| -------------------------- | --------------------------------------------------------------------------- | --- |
| `orders.status`            | Feature 9's status filter, and cancel-before-shipped becomes enforceable      | B2  |
| `orders.total_amount`      | Feature 9's price-range filter with pagination                                | B1  |
| `UNIQUE (stripe_reference)`| Fixes the 3NF violation and makes the webhook handler replay-safe             | B3  |
| `stock_notifications`      | Makes the feature 8 queue job idempotent, and therefore retryable             | B4  |

Everything else on this list is smaller than these four.
