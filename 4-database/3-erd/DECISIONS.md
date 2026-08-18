# ERD Design Decisions

## 1. One role per user, not many
**Chose:** `user_auth_data.role_id` — a single FK to `user_role`, not a many-to-many join table.
**Gave up:** flexibility for a user to hold multiple roles simultaneously (e.g., someone who's both Manager and Delivery Person).
**Why:** the brief phrases roles as *"kinds of users"* — Manager, Client, Delivery — language that describes a category a user belongs to, not a set of permissions they accumulate. Nothing in the challenge asks for a user to hold more than one role at once, so the added complexity of a join table buys nothing here.

## 2. Fixed `size`/`color` columns, not generic attribute/value
**Chose:** `product_variants` has `size` and `color` as direct columns.
**Gave up:** the ability to add new variant dimensions (material, print, etc.) without a schema migration.
**Why:** the brief only ever asks for size and color. A generic attribute/value structure solves a problem this store doesn't have, at the cost of every query needing extra joins to reconstruct a variant's attributes. Simpler wins when the requirement is fixed and known.

## 3. Price snapshot on `order_items`, not a live lookup
**Chose:** `order_items.price_at_purchase` stores the price at the moment of purchase.
**Gave up:** a single source of truth for price — the same value now exists on both `product_variants` and, historically, on `order_items`.
**Why:** without the snapshot, a product's price change would retroactively alter every past order's total. A customer's receipt has to reflect what they actually paid, not today's price. This is the same reasoning behind not aggregating a computed value where a stored fact is what's actually needed.

## 4. `order_status_history` table, not a single status column
**Chose:** status lives as rows in `order_status_history` (order_id, status, changed_at); `orders` has no status column at all — current status is the latest history row.
**Gave up:** a simpler schema and a slightly more complex "what's the current status" query (needs the latest row, not a direct column read).
**Why:** the optional delivery extension asks for full status history, and Stripe webhooks plus manual status changes are naturally a sequence of events over time, not a value that gets silently overwritten. Building the history table now means never having to redesign this if the optional feature gets picked up later — and it costs almost nothing extra today.

## 5. Many-to-many `product_categories`, not one category per product
**Chose:** a join table between `products` and `categories`, same shape as Pagila's `film_category`.
**Gave up:** the simplicity of a single `category_id` column directly on `products`.
**Why:** real catalogs tag a product into multiple categories (e.g., "Men's" + "New Arrivals"). A single FK can't express that at all without duplicating product rows. This is the exact pattern already proven this week in the Pagila exercises — a film in multiple genres — so it's not new complexity, just the same shape reapplied.

## Round 2 - responding the review

The five decisions above were written before the schema was reviewed. This section
records what changed after it was, and what deliberately did not.

Each row cites the commit that carries it. Findings labelled `B*` come from
`REVIEW.md`; the mentor's items are numbered as he sent them.

| # | Finding | Source | Verdict | Commit | Why |
| --- | --- | --- | --- | --- | --- |
| 1 | No stored order total | `REVIEW.md` B1 · mentor 5 | Accepted | `a133054` | The total IS the receipt; deriving it later is the failure `price_at_purchase` exists to prevent. And the price-range filter couldn't use an index — it had to sum every line item of every order before it could reject one. |
| 2 | No current status on `orders` | `REVIEW.md` B2 | Accepted | `203361c` | Cancel-before-shipped needs a row to lock. With status only in history, current status is derived from `max(changed_at)`, so a cancel and a ship both read the same value and both proceed — there is nothing to lock. |
| 3 | `stripe_reference` not unique | `REVIEW.md` B3 · 3NF violation | Accepted | `cdaadce` | A replayed Stripe webhook inserts a second payment row. Same constraint is the 3NF fix: `stripe_reference` determined `amount`/`status` without being a key. |
| 4 | Sign-out has nowhere to live | `REVIEW.md` B7 · mentor 4 | **Finding accepted, fix rejected** | `abfd505` | Refresh-token table — state confined to one endpoint. Cost: revocation lags one access-token lifetime. |
| 5 | Required FKs nullable; cart cardinality wrong | Mine — found while editing | Accepted | `44f7eda` | dbdiagram refused a nullable FK on `refresh_tokens`, which exposed two defects: 11 required FKs were declared nullable, and `shopping_carts.user_id` was marked `unique` while its `Ref` said many-to-one — the constraint and the relationship contradicted each other. |
| 6 | Bare `timestamp` and `numeric` | `REVIEW.md` cheap-and-real | Accepted | `47a4d91` |  Bare timestamp: a UTC server and a GMT-6 laptop disagree about whether a reset token has expired and which orders fall in "January". Bare numeric: accepts 19.999, and Stripe charges integer cents. |
| 7 | `is_primary` on `product_images` | `REVIEW.md` B4c | Accepted | `38021f3` | Feature 8 says "include **the** product's image" — singular, definite, while a product has many. Something has to choose, and today `ORDER BY id LIMIT 1` chooses arbitrarily and silently changes when a manager deletes and re-uploads. One boolean and a partial unique index is a cheap price for making the choice explicit. |
| 8 | Snapshot product identity on `order_items` | `REVIEW.md` B5 | **`deleted_at` accepted, the three columns rejected** | `38021f3` | `products.deleted_at` is not optional: "Delete products" is a manager capability and `order_items.product_variant_id` is a hard FK, so a real delete either errors forever or cascades and destroys order history. The three snapshot columns are a different question — they freeze a **display** fact, not a binding one. `price_at_purchase` exists because what the customer was charged is disputable; a product's name and colour are labels. Three denormalized columns on every order line, kept in sync at write time, to preserve a label — the cost outruns the benefit. |

### Row 4 — why the proposed fix was rejected

The finding is real — a signed JWT can't be revoked and sign-out is required.
The fix isn't: `tokens_valid_from` puts a database read on every authenticated
request. A refresh-token table confines that state to one endpoint, at the cost
of a revocation lag bounded by the access-token lifetime.

### What I am not changing, and why

- **B5's three snapshot columns** — argued in row 8.
- **Indexes on FK columns** — real, but an ERD is not where index strategy belongs.
  `REVIEW.md` concedes this itself.

### Still open

Agreed with, not yet done — distinct from the section above.

- **B6** — `UNIQUE (product_id, size, color)` on variants, `UNIQUE (cart_id, product_variant_id)` on cart items.
- **B8** — `promo_codes.times_used`; the usage limit cannot be enforced without a lock target.
- **B4 / B4b** — `stock_notifications`, and "stock reaches 3" being undefined at the variant grain.
- **Non-FK required columns are still nullable** — `email`, `password_hash`, `products.name`, `quantity`, `price`. Same class as row 5, wider scope.
- **Table renames** — mentor item 6.

