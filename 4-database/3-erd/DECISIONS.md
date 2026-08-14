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
