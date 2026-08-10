# 4. Database

Two sets of exercises on PostgreSQL. The first is about **querying** — pulling
answers out of a realistic dataset. The second is about **writing** data safely
when any step might fail.

## 🚀 Getting started

### Prerequisites

- **Docker Desktop**
- **A PostgreSQL client** — `psql`, TablePlus, DBeaver, pgAdmin, whichever you
  prefer

### Start the database

From this folder:

```bash
docker compose up
```

On first start, the scripts in `init.db/` run in filename order and set
everything up for you:

| Script                 | What it creates                                     |
| ---------------------- | --------------------------------------------------- |
| `01-pagila-schema.sql` | The Pagila tables, in the `public` schema           |
| `02-pagila-data.sql`   | The Pagila sample data                              |
| `03-transactions.sql`  | The `banking` schema, its tables, and seed accounts |

Then connect with these credentials:

```
Host:     localhost
Port:     5432
Database: nerdery_db
User:     postgres
Password: pass_nerdery
```

> Already using port 5432? Change the host side of the port mapping in
> `docker-compose.yml` — there's a comment showing how.

Stop the database with `docker compose down`. Your data persists in a named
volume, so it'll still be there next time. To start completely fresh — and
re-run the init scripts — use `docker compose down -v`.

### Without Docker

Install PostgreSQL yourself, create a database, and run the three files in
`init.db/` in the order listed above.

## 📝 The exercises

### 1. Pagila — `1-pagila/challenge.sql`

Pagila models a DVD rental business: films, categories, customers, rentals, and
payments. Eight queries, written under the `-- your query here` markers, in the
`public` schema.

They ramp up deliberately — grouping and aggregation, then joins, then
subqueries and set logic, finishing with a **materialized view** for revenue by
category. That last one also asks you two written questions about when a
materialized view is worth it; answer them in a comment.

### 2. Banking — `2-banking/challenge.sql`

Write a stored function, `banking.transfer_funds(from_id, to_id, amount)`, that
moves money between two accounts.

The exercise is the failure cases, not the happy path. Your function must reject
transfers to the same account, non-positive amounts, missing accounts, frozen
accounts, and insufficient funds — raising a meaningful exception each time. On
success it debits, credits, and logs **two** transactions (a withdrawal and a
deposit) sharing one UUID reference.

Either the whole transfer happens or none of it does. A partial transfer that
debits one account without crediting the other is the bug this exercise exists
to teach you to avoid.

The `banking` schema is seeded with accounts 1, 2, and 3 — **account 3 is
`frozen`**, so you can test that path immediately. Add more rows if you need
them.

## 💡 Tips

- Read the requirement list under each challenge carefully — it names the exact
  columns and ordering expected.
- Build queries outwards: get the join right and eyeball the raw rows before
  adding grouping and filtering on top.
- For the banking function, try to break your own code. Transfer to a frozen
  account, transfer more than the balance, transfer a negative amount — then
  check the balances still add up.
- `EXPLAIN` is worth running on the heavier queries, just to see what the
  planner does with them.

## 📤 Submitting

See **[How to submit your work](../README.md#-how-to-submit-your-work)** in the
root README.
