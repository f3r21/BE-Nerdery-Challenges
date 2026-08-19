# Review rounds

Claude attacking the contract, and what I did about it. Three rounds, a fresh session each,
because the session that wrote the document already believes the assumptions that produced
the hole.

Every finding carries a tag. Untagged findings do not enter the ledger.

| Tag | Means | Who decides |
| --- | --- | --- |
| `[SPEC]` | Required or forbidden by OpenAPI 3.0.3 | I verify it against `spec.openapis.org/oas/v3.0.3` before accepting |
| `[CONVENTION]` | Common practice, with a named source | I weigh it |
| `[TASTE]` | Claude's preference | Rejectable without argument |

---

## Round 1, 2026-08-19

**Scope.** The shared component layer and one placeholder operation, 251 lines. Deliberately
run before the other 27 operations are authored: a flaw in `Problem` or `PageMeta`
propagates into every one of them, so it is cheaper to find here than on Friday.

**Lenses run**, from `Week 2 - REST Design + NestJS Foundations.md:264-267`: missing status
codes and inconsistent pagination and error shapes; is it understandable, not just valid;
where is the same idea expressed two ways; and whether the document does what
`DECISIONS.md` says it does.

### Ledger

| # | Tag | Finding | Verdict | Reasoning | Commit |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |

### The hole

The week's bar needs one real hole found and closed **in the document**, not filed away for
Week 3. This is the one:

### What I rejected, and why

