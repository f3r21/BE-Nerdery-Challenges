# ERD Design Decisions

## 1. One role per user, not many
**Chose:** `users.role_id`, a single FK to `roles`, not a many-to-many join table.
**Gave up:** flexibility for a user to hold multiple roles simultaneously (e.g., someone who's both Manager and Delivery Person).
**Why:** the brief phrases roles as *"kinds of users"* (Manager, Client, Delivery), language that describes a category a user belongs to, not a set of permissions they accumulate. Nothing in the challenge asks for a user to hold more than one role at once, so the added complexity of a join table buys nothing here.

## 2. Fixed `size`/`color` columns, not generic attribute/value
**Chose:** `product_variants` has `size` and `color` as direct columns.
**Gave up:** the ability to add new variant dimensions (material, print, etc.) without a schema migration.
**Why:** the brief only ever asks for size and color. A generic attribute/value structure solves a problem this store doesn't have, at the cost of every query needing extra joins to reconstruct a variant's attributes. Simpler wins when the requirement is fixed and known.

## 3. Price snapshot on `order_items`, not a live lookup
**Chose:** `order_items.price_at_purchase` stores the price at the moment of purchase.
**Gave up:** a single source of truth for price. The same value now exists on both `product_variants` and, historically, on `order_items`.
**Why:** without the snapshot, a product's price change would retroactively alter every past order's total. A customer's receipt has to reflect what they actually paid, not today's price. This is the same reasoning behind not aggregating a computed value where a stored fact is what's actually needed.

## 4. `order_status_history` table, not a single status column
**Chose:** status lives as rows in `order_status_history` (order_id, status, changed_at); `orders` has no status column at all, so current status is the latest history row.
**Gave up:** a simpler schema and a slightly more complex "what's the current status" query (needs the latest row, not a direct column read).
**Why:** the optional delivery extension asks for full status history, and Stripe webhooks plus manual status changes are naturally a sequence of events over time, not a value that gets silently overwritten. Building the history table now means never having to redesign this if the optional feature gets picked up later, and it costs almost nothing extra today.

## 5. Many-to-many `product_categories`, not one category per product
**Chose:** a join table between `products` and `categories`, same shape as Pagila's `film_category`.
**Gave up:** the simplicity of a single `category_id` column directly on `products`.
**Why:** real catalogs tag a product into multiple categories (e.g., "Men's" + "New Arrivals"). A single FK can't express that at all without duplicating product rows. This is the exact pattern already proven this week in the Pagila exercises (a film in multiple genres), so it's not new complexity, just the same shape reapplied.

## Round 2 - responding the review

The five decisions above were written before the schema was reviewed. This section
records what changed after it was, and what deliberately did not.

Each row cites the commit that carries it. Findings labelled `B*` come from
`REVIEW.md`; the mentor's items are numbered as he sent them.

| # | Finding | Source | Verdict | Commit | Why |
| --- | --- | --- | --- | --- | --- |
| 1 | No stored order total | `REVIEW.md` B1 · mentor 5 | Accepted | `a133054` | The total IS the receipt; deriving it later is the failure `price_at_purchase` exists to prevent. And the price-range filter couldn't use an index. It had to sum every line item of every order before it could reject one. |
| 2 | No current status on `orders` | `REVIEW.md` B2 | Accepted | `203361c` | Cancel-before-shipped needs a row to lock. With status only in history, current status is derived from `max(changed_at)`, so a cancel and a ship both read the same value and both proceed. There is nothing to lock. |
| 3 | `stripe_reference` not unique | `REVIEW.md` B3 · 3NF violation | Accepted | `cdaadce` | A replayed Stripe webhook inserts a second payment row. Same constraint is the 3NF fix: `stripe_reference` determined `amount`/`status` without being a key. |
| 4 | Sign-out has nowhere to live | `REVIEW.md` B7 · mentor 4 | **Finding accepted, fix rejected** | `abfd505` | Refresh-token table, with state confined to one endpoint. Cost: revocation lags one access-token lifetime. |
| 5 | Required FKs nullable; cart cardinality wrong | Mine, found while editing | Accepted | `44f7eda` | dbdiagram refused a nullable FK on `refresh_tokens`, which exposed two defects: 11 required FKs were declared nullable, and `shopping_carts.user_id` was marked `unique` while its `Ref` said many-to-one. The constraint and the relationship contradicted each other. |
| 6 | Bare `timestamp` and `numeric` | `REVIEW.md` cheap-and-real | Accepted | `47a4d91` |  Bare timestamp: a UTC server and a GMT-6 laptop disagree about whether a reset token has expired and which orders fall in "January". Bare numeric: accepts 19.999, and Stripe charges integer cents. |
| 7 | `is_primary` on `product_images` | `REVIEW.md` B4c | Accepted | `38021f3` | Feature 8 says "include **the** product's image": singular, definite, while a product has many. Something has to choose, and today `ORDER BY id LIMIT 1` chooses arbitrarily and silently changes when a manager deletes and re-uploads. One boolean and a partial unique index is a cheap price for making the choice explicit. |
| 8 | Snapshot product identity on `order_items` | `REVIEW.md` B5 | **`deleted_at` accepted, the three columns rejected** | `38021f3` | `products.deleted_at` is not optional: "Delete products" is a manager capability and `order_items.product_variant_id` is a hard FK, so a real delete either errors forever or cascades and destroys order history. The three snapshot columns are a different question. They freeze a **display** fact, not a binding one. `price_at_purchase` exists because what the customer was charged is disputable; a product's name and colour are labels. Three denormalized columns on every order line, kept in sync at write time, to preserve a label. The cost outruns the benefit. |
| 9 | `stock_notifications` has no table | `REVIEW.md` B4, shape from `REVIEW.md:186` | **Accepted, with a changed key** | `c41729f` | Nothing in the schema recorded that the Feature 8 mail went out, so a retried queue job re-queries "liked P, has not purchased P", gets the identical set, and emails all of them again. `REVIEW.md:186` proposed `UNIQUE (user_id, product_id)` and named no primary key, which would have left this the only table in the schema without one, so it is a composite `[pk]` instead, matching `product_likes`, the structurally identical join table. The cost is permanent and worth stating rather than discovering: one row per user per variant forever, so a variant restocked and falling to 3 again never notifies that user a second time. Notifying once per restock is a real requirement, it is undecided, and it is in Still open below rather than guessed at here. |
| 10 | Cart lines not unique per variant | `REVIEW.md` B6 | Accepted | `c41729f` | A double-clicked add-to-cart inserts two lines for the same variant instead of leaving one, and `openapi.yaml:1175` already promises the operation is idempotent. The contract sets an absolute quantity rather than adding a delta, per the add-to-cart entry in `5-api-design/DECISIONS.md`, so the constraint is what lets the second insert collide with the first and the handler replace the quantity on the row that is already there. Without it the second call leaves a duplicate and the contract's promise is false. |
| 11 | Variant rows not unique | `REVIEW.md` B6 | Accepted | `23f98b7` | Nothing stops a second row for the same product, size and colour, and each row carries its own `stock` and `price`. The two drift apart with nothing to reconcile them: the customer is charged whichever price the query returned, and the stock you can actually ship is neither number. |
| 12 | `promo_codes` has no usage counter | `REVIEW.md` B8 | Accepted | `23f98b7` | `usage_limit` was checked against a count of orders, which two concurrent checkouts both read as 99 before either commits, so both pass and a code capped at 100 is used 101 times. `times_used` gives the redemption a single row to lock, so the second transaction waits and reads 100. |
| 13 | Non-FK required columns nullable | `REVIEW.md`, same class as row 5 | **Partially accepted** | `23f98b7` | All five columns belong under `not null`. Three landed: `users.email`, `users.password_hash` and `products.name`. `quantity` and `price` did not, and the reason is the calendar, not a distinction between them. They stay in Still open below rather than being argued away, because inventing a principle after the fact would be worse than admitting the scope. |
| 14 | Table names too long | Mentor item 6 | Accepted | `35597a4` | `user_auth_data` held `first_name`, `last_name` and `role_id`, which are identity, not authentication, so the name misdescribed its own contents and cost every reader a lookup to find that out. The rename also settles the singular/plural split `REVIEW.md` flagged, where `user_role` sat beside `products`. Nothing breaks without this, which is why it was the last of his six still open. |
| 15 | Likes sit on the product while stock sits on the variant | Mentor review, 2026-08-25 | Accepted | `c4cc306` | Nothing recorded which variant a person wanted. `product_likes` was keyed `(user_id, product_id)` and `stock` lives on `product_variants`, so the two facts the notification needs sat at different grains and the threshold had to guess at one of them. Both tables now key to the variant, their composite keys move with them, and both `Ref:` lines retarget to `product_variants.id`. `product_likes` also gains `[not null]` on both columns, because it was one of five tables in this file carrying no marker at all and the block was open anyway. **This reverses the grain decision recorded at `62144ff`.** That entry settled the trigger as the sum across a product's variants, and its load-bearing reason was that `stock_notifications` was keyed by product, so the table recording the mail could not express a per-variant trigger without a schema change, and a rule the schema cannot record is not a rule. The mentor's review lifted exactly that constraint by sanctioning the schema change, so the premise is gone rather than the argument being wrong. The defect itself was named here first, in `62144ff` on 2026-08-25 at 06:37, with its cost already written: fixing it properly means variant-level likes, which moves `product_likes`, the notification key and the Week 2 contract. All three moved. |
| 16 | The reuse detection the contract promises cannot be implemented | Reading `refreshSession` against row 4's addendum | Accepted | `27ede64` | `openapi.yaml` tells clients, in `refreshSession`'s own description, that a token presented after it was already rotated deletes every refresh row for that user. Rotation updates the row in place, which overwrites `token_hash`, so a replayed token hashes to a value matching no row. The server cannot tell it from a garbage string, cannot identify the user, and therefore cannot fire the delete it published. This is not a defect the in-place choice introduced: delete-then-insert destroyed the old hash too, so the clause has never been implementable under either mechanism. `previous_token_hash` holds the value the current rotation replaced, nullable because a session on its first token has no earlier generation, and a presented token is matched against both. **Gave up:** an attacker who waits through two or more legitimate rotations before replaying is not caught. A used-token table with an expiry sweep would catch every generation, at the cost of a table that grows with traffic and needs cleaning, which for one Postgres and one store is the worse trade. `token_hash` and `expires_at` also become `[not null]` in the same pass, since the refresh path reads both on every call. |


### Row 4: why the proposed fix was rejected

The finding is real. A signed JWT can't be revoked and sign-out is required.
The fix isn't: `tokens_valid_from` puts a database read on every authenticated
request. A refresh-token table confines that state to one endpoint, at the cost
of a revocation lag bounded by the access-token lifetime.

### Row 4 addendum: rotation updates the row in place

Decided 2026-08-25, closing `5-api-design/REVIEW.md` R2-7, which had asked the question and
deferred it here.

`POST /auth/refresh` rotates the token. The row is **updated, not replaced**: `token_hash`
and `expires_at` change, `id` and `created_at` survive. The contract depends on that.
`GET /auth/sessions` hands the client `Session.id`, `DELETE /auth/sessions/{id}` targets it,
and a delete-then-insert rotation would destroy that id roughly every fifteen minutes. The
only session identifier the API exposes would be one no client can hold long enough to use.

`created_at` therefore means when the device first signed in, not when it last refreshed.
`expires_at` carries the refresh window and moves on every rotation.

**Gave up:** the audit trail a delete-and-insert would leave. One row per device keeps no
record of how often it rotated, so a replayed token is detectable at the moment it arrives
and invisible afterwards.

### What I am not changing, and why

- **B5's three snapshot columns**, argued in row 8.
- **Indexes on FK columns**. Real, but an ERD is not where index strategy belongs.
  `REVIEW.md` concedes this itself.

### Still open

Agreed with, not yet done, and distinct from the section above. Everything else that stood
here on 2026-08-23 shipped in rows 9 to 14.

- **Variant-level interest is not modelled.** *Closed 2026-08-25 at `c4cc306`.* `REVIEW.md`
  B4b asked at what grain "stock reaches 3" fires, and the answer was a guess either way for
  as long as likes sat on `products` while stock sat on `product_variants`. Summing
  under-notified, since eight variants holding one unit each sum to eight and nobody is told,
  and firing per variant over-notified. Both tables now key to the variant, so interest and
  stock share a grain and the threshold needs no interpretation. Named here on 2026-08-25 at
  06:37, with its full cost, before the mentor raised it.
- **A user is notified once per variant, ever.** The composite key in row 9 permits one row
  per `(user_id, product_variant_id)`, so a restock six months later notifies nobody who was
  already told. The re-key in row 15 made this finer without making it go away. Fixing it
  needs a real notion of a restock episode, because putting `sent_at` in the key does not
  work: a retried worker writes a different timestamp, the key does not collide, and the mail
  goes twice. That destroys the deduplication the table exists for. No episode rule is decided.
- **`quantity` and `price` are still nullable.** Three columns: `quantity` on `order_items`
  and on `shopping_cart_items`, and `price` on `product_variants`. Same class as row 5 and row
  13, and outstanding for the same reason row 13 gives: they were cut for time on 2026-08-24,
  not because they differ from the three that landed. A line item with no quantity means as
  little as a user with no email.

### Where the week's readings support this, and where they run out

One entry per Round 2 row. Read from the Week 1 required list, not from recall. Where a reading
asserts something without giving a reason, or does not cover the argument at all, this says so.

| Rows | Reading | The claim I am leaning on |
| --- | --- | --- |
| 1, 8 | Normalization vs Denormalization | It names "creating aggregates", meaning pre-calculated summary data, as one of three denormalization methods, and frames normalization and denormalization as two techniques rather than right and wrong. It gives no rule, threshold or measurement for choosing between them and says so. So `subtotal_amount` and `total_amount` are a denormalization I chose, not a normal form I broke, and rejecting the three snapshot columns in row 8 is the same judgement pointed the other way. |
| 3 | Normalization vs Denormalization | Its 3NF rule: remove any column that depends on a non-key column, so every attribute depends on the primary key only and not on another non-key attribute. `stripe_reference` determined `amount` and `status` without being a key, which is that rule exactly. |
| 5, 13 | Managing Tables | It lists `NOT NULL` among six constraints, and its own worked example writes `email VARCHAR (255) UNIQUE NOT NULL`. Row 13 put `not null` on `users.email` for the reason the reading's example already demonstrates. |
| 6 | Data Types | It names `TIMESTAMP` and `TIMESTAMPTZ` as separate temporal types and gives `numeric(p,s)` with precision and scale. It is an index of type families and gives no rule for preferring one over another, so the vocabulary is the reading's and the choice is mine. |
| 9, 10, 11 | Constraints | A primary key is technically a not-null constraint and a UNIQUE constraint together, PostgreSQL builds a unique B-tree index for it, and the composite form moves out of the column definition into its own clause, `PRIMARY KEY (order_id, item_no)`. That is the basis for the composite key in row 9. The same page asserts that every table should have a primary key and gives no reason for it, which matters because row 9 leans on that assertion. |
| 14 | SQL Best Practices | Its three priorities, in its order, are accuracy, then readability, then performance, and its reason for aliasing every table is that the reader should not have to work out which column belongs to which table. `user_auth_data` holding `first_name` is that same cost moved up to the schema. |
| 2, 12 | **None covers it** | Transactions gives ACID and the visibility rule before commit. How to work with PostgreSQL transactions gives `SAVEPOINT`, aborted blocks and the transaction modes. Neither covers row-level locking, and row-level locking is the entire argument in rows 2 and 12. That reasoning is mine, from the plans in `mentor-followup.sql` and from the banking exercise, not from a Week 1 reading. |
| 4, 7 | **None covers it** | No Week 1 reading covers token revocation or partial unique indexes. Row 4 and row 7 are argued from the brief and from `openapi.yaml`. |
