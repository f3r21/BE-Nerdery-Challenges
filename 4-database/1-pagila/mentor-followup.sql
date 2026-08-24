/*
    Follow-up to the Week 1 review, 2026-08-18.

    Two items from that session were not exercise corrections. They were topics
    to study, because the submitted challenge.sql does not contain them:

      1. "Study the other 2 JOIN (right, outer) i only used left and inner."
      2. "Study CTE, i didnt use it in the exercises."

    Verified before writing this file, from the repository root:

      git grep -icE '(WITH [a-z_]+ AS|RIGHT JOIN|FULL OUTER)' challenge/database -- '*.sql'
      -> no output, so zero matches on every file

      printf 'WITH x AS (\n' | grep -cE 'WITH [a-z_]+ AS'
      -> 1, which proves the pattern fires and the zero above is real

    challenge.sql is NOT edited. It is what was reviewed. This is a separate file
    so the reviewed work stays intact and the new work is visible as new work.

    Run it:
      cd 4-database && docker compose up -d
      docker exec -i postgres-sample psql -U postgres -d nerdery_db < 1-pagila/mentor-followup.sql

    Every result comment below was measured on PostgreSQL 17, Pagila as seeded by
    init.db/, on 2026-08-23. Row counts in the database at that time: film 1000,
    inventory 4581, rental 16044, customer 599.
*/

\pset pager off

/* ==========================================================================
   PART 1. CTE. Rewriting challenge 5.
   ==========================================================================

   Challenge 5 asked for the films rented more times than the average rental
   count per film.

   PREDICTION, written in the week plan on 2026-08-21, before any of this ran:
   the submitted answer computes the per-film count TWICE. Once in the outer
   GROUP BY, and once again inside the derived table in HAVING. A CTE lets it
   be computed once and referred to twice. So I expected the plan to change
   from two scan trees to one, and I expected the buffer count to halve.

   What I did NOT predict, and had to look up after seeing the plan: WHY the
   CTE gets computed once. It is not the WITH keyword. Section 1.5 is the
   control that settles it.
*/

-- 1.1  The submitted version, quoted unchanged from challenge.sql so the two
--      forms can be compared. The derived table in HAVING is the repetition.

SELECT f.title, count(r.rental_id) AS rental_count
FROM film f
LEFT JOIN inventory i ON i.film_id = f.film_id
LEFT JOIN rental r ON r.inventory_id = i.inventory_id
GROUP BY f.film_id, f.title
HAVING count(r.rental_id) > (
    SELECT AVG(film_count)
    FROM (
        SELECT count(r2.rental_id) AS film_count
        FROM film f2
        LEFT JOIN inventory i2 ON i2.film_id = f2.film_id
        LEFT JOIN rental r2 ON r2.inventory_id = i2.inventory_id
        GROUP BY f2.film_id
    ) AS film_counts
);

-- 1.2  The rewrite. The per-film count is named once and used twice: once as
--      the rows to filter, once as the input to the average.

WITH film_counts AS (
    SELECT f.film_id, f.title, count(r.rental_id) AS rental_count
    FROM film f
    LEFT JOIN inventory i ON i.film_id = f.film_id
    LEFT JOIN rental r ON r.inventory_id = i.inventory_id
    GROUP BY f.film_id, f.title
)
SELECT title, rental_count
FROM film_counts
WHERE rental_count > (SELECT avg(rental_count) FROM film_counts);

-- 1.3  Same rows, or the rewrite is wrong. EXCEPT ALL in both directions,
--      because one direction only proves containment, not equality.
--
--      MEASURED: submitted_rows 475, rewritten_rows 475,
--                in_submitted_not_rewritten 0, in_rewritten_not_submitted 0.

WITH submitted AS (
    SELECT f.title, count(r.rental_id) AS rental_count
    FROM film f
    LEFT JOIN inventory i ON i.film_id = f.film_id
    LEFT JOIN rental r ON r.inventory_id = i.inventory_id
    GROUP BY f.film_id, f.title
    HAVING count(r.rental_id) > (
        SELECT AVG(film_count) FROM (
            SELECT count(r2.rental_id) AS film_count
            FROM film f2
            LEFT JOIN inventory i2 ON i2.film_id = f2.film_id
            LEFT JOIN rental r2 ON r2.inventory_id = i2.inventory_id
            GROUP BY f2.film_id) AS film_counts)
), fc AS (
    SELECT f.film_id, f.title, count(r.rental_id) AS rental_count
    FROM film f
    LEFT JOIN inventory i ON i.film_id = f.film_id
    LEFT JOIN rental r ON r.inventory_id = i.inventory_id
    GROUP BY f.film_id, f.title
), rewritten AS (
    SELECT title, rental_count FROM fc
    WHERE rental_count > (SELECT avg(rental_count) FROM fc)
)
SELECT (SELECT count(*) FROM submitted) AS submitted_rows,
       (SELECT count(*) FROM rewritten) AS rewritten_rows,
       (SELECT count(*) FROM (SELECT * FROM submitted EXCEPT ALL SELECT * FROM rewritten) x)
           AS in_submitted_not_rewritten,
       (SELECT count(*) FROM (SELECT * FROM rewritten EXCEPT ALL SELECT * FROM submitted) y)
           AS in_rewritten_not_submitted;

/* 1.4  The two plans.

   MEASURED with EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF):

   Submitted, derived table in HAVING
     HashAggregate                       Buffers: shared hit=488
       InitPlan 1
         -> Aggregate                    Buffers: shared hit=244
              -> HashAggregate  rows=1000
                   -> Hash Right Join    Seq Scan rental 16044,
                                         Seq Scan inventory 4581,
                                         Seq Scan film 1000
       -> Hash Right Join                Buffers: shared hit=244
              (the same three Seq Scans again)
     Execution Time: 8.114 to 8.519 ms over three runs

   CTE referenced twice
     CTE Scan on film_counts             Buffers: shared hit=244
       CTE film_counts
         -> HashAggregate  rows=1000     Buffers: shared hit=244
              -> Hash Right Join         Seq Scan rental 16044,
                                         Seq Scan inventory 4581,
                                         Seq Scan film 1000
       InitPlan 2
         -> Aggregate
              -> CTE Scan on film_counts film_counts_1  rows=1000
     Execution Time: 4.408 to 4.682 ms over three runs

   Read the buffers, not the clock. 488 is exactly 244 + 244: the submitted form
   reads the three tables twice, once per scan tree. The CTE form reads them once
   and scans the stored result twice. The clock roughly halves because the work
   roughly halves, which is a consequence rather than the finding.
*/

-- 1.5  THE CONTROL. This is the part that stops the answer being "CTEs are faster".
--
--      1.5a  A CTE referenced ONCE. If WITH were an optimisation fence, this
--            plan would contain a CTE node.
--            MEASURED: no CTE node at all. Plan is HashAggregate over three
--            Seq Scans. PostgreSQL inlined it, exactly as if it were a subquery.

EXPLAIN (COSTS OFF)
WITH fc AS (
    SELECT f.film_id, count(r.rental_id) c
    FROM film f
    LEFT JOIN inventory i ON i.film_id = f.film_id
    LEFT JOIN rental r ON r.inventory_id = i.inventory_id
    GROUP BY f.film_id)
SELECT * FROM fc WHERE c > 30;

--      1.5b  The same twice-referenced CTE from 1.2, with materialisation
--            switched off by hand.
--            MEASURED: Buffers: shared hit=488, two full scan trees, the same
--            shape as the submitted version in 1.1. The saving disappears.

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
WITH film_counts AS NOT MATERIALIZED (
    SELECT f.film_id, f.title, count(r.rental_id) AS rental_count
    FROM film f
    LEFT JOIN inventory i ON i.film_id = f.film_id
    LEFT JOIN rental r ON r.inventory_id = i.inventory_id
    GROUP BY f.film_id, f.title)
SELECT title, rental_count
FROM film_counts
WHERE rental_count > (SELECT avg(rental_count) FROM film_counts);

/* 1.6  What I can now say about CTEs, and what I cannot.

   The CTE did not make anything faster. Materialisation did. From PostgreSQL 12
   onward a CTE referenced once is inlined and behaves as a subquery, which 1.5a
   shows. A CTE referenced more than once is materialised by default, which is
   why 1.2 computes the aggregate once. Turn that default off and the plan
   collapses back to the submitted one, which 1.5b shows.

   So the reason to reach for a CTE in challenge 5 is that the same derived set
   is needed twice, and naming it once removes the repetition from the query text
   and, as a consequence of the default, from the plan. If the set were needed
   once, the rewrite would be readability only and the plan would be identical.

   What I cannot claim: that this generalises to a large table. Pagila is small
   enough that all three tables sit in shared buffers, so the measurement above
   is CPU and buffer traffic, not disk. Materialising a large intermediate result
   can also lose an index the planner would have pushed a filter into. That is the
   cost side of NOT MATERIALIZED existing as a keyword at all.
*/


/* ==========================================================================
   PART 2. RIGHT JOIN.
   ==========================================================================

   PREDICTION, before running: a RIGHT JOIN is a LEFT JOIN with the operands
   written the other way round, so any RIGHT JOIN can be rewritten as a LEFT
   JOIN and return the same rows. I expected the counts to match exactly.
*/

-- 2.1  Equivalence, proved rather than asserted. Films with no inventory copy,
--      written both ways, compared with EXCEPT ALL in both directions.
--
--      MEASURED: left_form 42, right_form 42, diff_a 0, diff_b 0.

SELECT
    (SELECT count(*) FROM film f
       LEFT JOIN inventory i ON i.film_id = f.film_id
      WHERE i.inventory_id IS NULL) AS left_form,
    (SELECT count(*) FROM inventory i
      RIGHT JOIN film f ON i.film_id = f.film_id
      WHERE i.inventory_id IS NULL) AS right_form,
    (SELECT count(*) FROM (
        (SELECT f.film_id FROM film f
           LEFT JOIN inventory i ON i.film_id = f.film_id WHERE i.inventory_id IS NULL)
        EXCEPT ALL
        (SELECT f.film_id FROM inventory i
          RIGHT JOIN film f ON i.film_id = f.film_id WHERE i.inventory_id IS NULL)) d) AS diff_a,
    (SELECT count(*) FROM (
        (SELECT f.film_id FROM inventory i
          RIGHT JOIN film f ON i.film_id = f.film_id WHERE i.inventory_id IS NULL)
        EXCEPT ALL
        (SELECT f.film_id FROM film f
           LEFT JOIN inventory i ON i.film_id = f.film_id WHERE i.inventory_id IS NULL)) d) AS diff_b;

-- 2.2  THE TRAP, and the reason this is worth knowing rather than trivia.
--      A predicate on the nullable side belongs in ON, not in WHERE. In WHERE it
--      runs after the join has already produced the NULL rows, and NULL = 1 is
--      not true, so every preserved row is discarded and the outer join silently
--      becomes an inner join.
--
--      MEASURED: outer_rows 4623, where_on_nullable 2270,
--                predicate_in_on 2511, plain_inner 2270.
--
--      where_on_nullable and plain_inner are the same number. That equality is
--      the proof: writing RIGHT JOIN bought nothing. predicate_in_on keeps all
--      1000 films and matches only the store 1 copies, which is the query a
--      person writing RIGHT JOIN actually meant.

SELECT
    (SELECT count(*) FROM inventory i RIGHT JOIN film f ON i.film_id = f.film_id)
        AS outer_rows,
    (SELECT count(*) FROM inventory i RIGHT JOIN film f ON i.film_id = f.film_id
      WHERE i.store_id = 1)
        AS where_on_nullable,
    (SELECT count(*) FROM inventory i RIGHT JOIN film f ON i.film_id = f.film_id
       AND i.store_id = 1)
        AS predicate_in_on,
    (SELECT count(*) FROM inventory i INNER JOIN film f ON i.film_id = f.film_id
      WHERE i.store_id = 1)
        AS plain_inner;

/* 2.3  Where RIGHT JOIN earns its place, and where it does not.

   It does not earn a place in a two-table query. Write the table you want to
   preserve first and use LEFT JOIN, because a reader scanning downward then sees
   the preserved table before the rule that preserves it.

   It earns a place in a chain. Once four tables are joined left to right and the
   fifth one is the one that must be preserved, RIGHT JOIN says so at the point of
   the join instead of making the whole FROM clause be reordered.

   Worth noticing: the planner already uses it on my own queries. Every plan in
   Part 1 renders my LEFT JOINs as "Hash Right Join", because the executor builds
   the hash table from the smaller relation and probes with the larger one, which
   swaps which side is preserved. LEFT and RIGHT are the same operator with the
   operands the other way round, and PostgreSQL treats them that way internally.
*/


/* ==========================================================================
   PART 3. FULL OUTER JOIN.
   ==========================================================================

   PREDICTION, written in the week plan on 2026-08-21, before running: a FULL
   OUTER JOIN across two tables related by a foreign key can never produce a
   right-side orphan, because the foreign key guarantees every child row has a
   parent. So the obvious Pagila demo degenerates into a LEFT JOIN and proves
   nothing. To see both sides I need two sets where neither contains the other.

   PASS CONDITION, written before running: at least one NULL-left row AND at
   least one NULL-right row, both counts non-zero, in the same result.
*/

-- 3.1  THE NEGATIVE CONTROL. film and inventory are related by a foreign key.
--
--      MEASURED: film_no_inventory 42, inventory_no_film 0.
--
--      The right side is zero and cannot be anything else while the foreign key
--      holds. This FULL OUTER JOIN is a LEFT JOIN wearing a different keyword.
--      It is here because an outer join that returns nothing extra proves nothing,
--      and running it is how I know the demo in 3.2 is not vacuous.

SELECT count(*) FILTER (WHERE i.inventory_id IS NULL) AS film_no_inventory,
       count(*) FILTER (WHERE f.film_id IS NULL)      AS inventory_no_film
FROM film f
FULL OUTER JOIN inventory i ON i.film_id = f.film_id;

-- 3.2  THE REAL DEMO. Two sets built from the same table, neither of which
--      contains the other: customers who rented in February 2022, and customers
--      who rented in May 2022. This is the retention question a store actually
--      asks, which is why FULL OUTER JOIN is the right tool rather than a trick.
--
--      MEASURED: feb_only 19, may_only 381, both 139.
--      Both orphan sides are non-zero, so the pass condition is met.

WITH feb AS (
    SELECT DISTINCT customer_id
    FROM rental
    WHERE rental_date >= DATE '2022-02-01' AND rental_date < DATE '2022-03-01'
), may AS (
    SELECT DISTINCT customer_id
    FROM rental
    WHERE rental_date >= DATE '2022-05-01' AND rental_date < DATE '2022-06-01'
)
SELECT count(*) FILTER (WHERE m.customer_id IS NULL) AS feb_only,
       count(*) FILTER (WHERE f.customer_id IS NULL) AS may_only,
       count(*) FILTER (WHERE f.customer_id IS NOT NULL
                          AND m.customer_id IS NOT NULL) AS both
FROM feb f
FULL OUTER JOIN may m ON m.customer_id = f.customer_id;

-- 3.3  The same three numbers without FULL OUTER JOIN, as the alternative a
--      reviewer will ask about. Set operations answer it too.
--
--      MEASURED: identical to 3.2, feb_only 19, may_only 381, both 139.
--
--      FULL OUTER JOIN wins here because it produces all three groups in one
--      pass and keeps the columns, so a report can list WHICH customers churned
--      rather than only how many. EXCEPT and INTERSECT need three statements and
--      discard everything except the key.

WITH feb AS (
    SELECT DISTINCT customer_id
    FROM rental
    WHERE rental_date >= DATE '2022-02-01' AND rental_date < DATE '2022-03-01'
), may AS (
    SELECT DISTINCT customer_id
    FROM rental
    WHERE rental_date >= DATE '2022-05-01' AND rental_date < DATE '2022-06-01'
)
SELECT (SELECT count(*) FROM (SELECT * FROM feb EXCEPT SELECT * FROM may) a) AS feb_only,
       (SELECT count(*) FROM (SELECT * FROM may EXCEPT SELECT * FROM feb) b) AS may_only,
       (SELECT count(*) FROM (SELECT * FROM feb INTERSECT SELECT * FROM may) c) AS both;

/* 3.4  What I can now say about outer joins.

   LEFT and RIGHT are one operator. Which one to write is a readability decision
   about which table the reader meets first, and PostgreSQL swaps them anyway when
   it picks a hash side.

   FULL OUTER is a different thing: it is the set-comparison join, and it is only
   worth reaching for when both sides can have rows the other lacks. A foreign key
   between the two tables removes that possibility in one direction, which is why
   3.1 returns a zero and 3.2 does not.

   The failure mode for all three is the same and it is section 2.2. A predicate
   on a preserved-NULL column belongs in ON. Put it in WHERE and the outer join is
   an inner join that still reads as an outer join, which is worse than writing
   INNER JOIN in the first place because nothing looks wrong.
*/
