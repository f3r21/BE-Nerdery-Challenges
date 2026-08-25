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
| 9 | `stock_notifications` has no table | `REVIEW.md` B4, shape from `REVIEW.md:186` | **Accepted, with a changed key** | `c41729f` | Nothing in the schema recorded that the Feature 8 mail went out, so a retried queue job re-queries "liked P, has not purchased P", gets the identical set, and emails all of them again. `REVIEW.md:186` proposed `UNIQUE (user_id, product_id)` and named no primary key, which would have left this the only table in the schema without one, so it is a composite `[pk]` instead, matching `product_likes`, the structurally identical join table. The cost is permanent and worth stating rather than discovering: one row per user per product forever, so a product restocked and falling to 3 again never notifies that user a second time. Notifying once per restock is a real requirement, it is undecided, and it is in Still open below rather than guessed at here. |
| 10 | Cart lines not unique per variant | `REVIEW.md` B6 | Accepted | `c41729f` | A double-clicked add-to-cart inserts two identical lines instead of one line with quantity 2, and `openapi.yaml:1144` already promises the operation is idempotent. The constraint is what lets the second insert collide with the first so the handler can add to the existing line, which is the only way the contract's promise is true. |
| 11 | Variant rows not unique | `REVIEW.md` B6 | Accepted | `23f98b7` | Nothing stops a second row for the same product, size and colour, and each row carries its own `stock` and `price`. The two drift apart with nothing to reconcile them: the customer is charged whichever price the query returned, and the stock you can actually ship is neither number. |
| 12 | `promo_codes` has no usage counter | `REVIEW.md` B8 | Accepted | `23f98b7` | `usage_limit` was checked against a count of orders, which two concurrent checkouts both read as 99 before either commits, so both pass and a code capped at 100 is used 101 times. `times_used` gives the redemption a single row to lock, so the second transaction waits and reads 100. |
| 13 | Non-FK required columns nullable | `REVIEW.md`, same class as row 5 | **Partially accepted** | `23f98b7` | All five columns belong under `not null`. Three landed: `users.email`, `users.password_hash` and `products.name`. `quantity` and `price` did not, and the reason is the calendar, not a distinction between them. They stay in Still open below rather than being argued away, because inventing a principle after the fact would be worse than admitting the scope. |
| 14 | Table names too long | Mentor item 6 | Accepted | `35597a4` | `user_auth_data` held `first_name`, `last_name` and `role_id`, which are identity, not authentication, so the name misdescribed its own contents and cost every reader a lookup to find that out. The rename also settles the singular/plural split `REVIEW.md` flagged, where `user_role` sat beside `products`. Nothing breaks without this, which is why it was the last of his six still open. |


### Row 4: why the proposed fix was rejected

The finding is real. A signed JWT can't be revoked and sign-out is required.
The fix isn't: `tokens_valid_from` puts a database read on every authenticated
request. A refresh-token table confines that state to one endpoint, at the cost
of a revocation lag bounded by the access-token lifetime.

### What I am not changing, and why

- **B5's three snapshot columns**, argued in row 8.
- **Indexes on FK columns**. Real, but an ERD is not where index strategy belongs.
  `REVIEW.md` concedes this itself.

### Still open

Agreed with, not yet done, and distinct from the section above. Everything else that stood
here on 2026-08-23 shipped in rows 9 to 14.

- **"Stock reaches 3" is undefined at the variant grain.** `REVIEW.md` B4b. A product has many
  variants and each carries its own `stock`. The trigger fires on a product, so the threshold
  has no grain. This is a specification question, not a column, which is why row 9 does not
  close it.
- **A user is notified once per product, ever.** The composite key in row 9 permits one row
  per `(user_id, product_id)`, so a restock six months later notifies nobody who was already
  told. Fixing it needs a real notion of a restock episode, because putting `sent_at` in the
  key does not work: a retried worker writes a different timestamp, the key does not collide,
  and the mail goes twice. That destroys the deduplication the table exists for. No episode
  rule is decided.
- **`quantity` and `price` are still nullable.** Three columns: `quantity` on `order_items`
  and on `shopping_cart_items`, and `price` on `product_variants`. Same class as row 5 and row
  13, and outstanding for the same reason row 13 gives: they were cut for time on 2026-08-24,
  not because they differ from the three that landed. A line item with no quantity means as
  little as a user with no email.

