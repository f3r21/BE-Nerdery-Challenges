# Node.js Nerdery Program

Hands-on backend challenges for the **Node.js Nerdery Program**.

This repository is a set of exercises, not an application. Every challenge lives
in its own file, with the full brief written as a comment at the top and an
unimplemented stub right below it. You read the brief, write the code, and run
the check for that module.

Work through the modules in order — each one builds on the last.

---

## 🎯 What you'll learn

| Module              | You'll practice                                                                                                                                          |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1. JS & Async**   | The language itself: data manipulation, algorithmic thinking, and the three ways JavaScript handles asynchrony — callbacks, promises, and `async/await`. |
| **2. Core Node.js** | What Node gives you before any dependency: the file system, process arguments, streams of user input, and data that survives a restart.                  |
| **3. TypeScript**   | Modelling real data with precise types, then letting the compiler prove your logic is sound. Generics and conditional types included.                    |
| **4. Database**     | Thinking in sets instead of loops: joins, aggregation, subqueries, materialized views, and transactions that stay correct when things fail.              |

---

## ✅ Prerequisites

- **Node.js >= 22** — check with `node --version`
- **Docker Desktop** — module 4 only, to run PostgreSQL
- **A PostgreSQL client** — module 4 only (`psql`, TablePlus, DBeaver, pgAdmin…)

## 🚀 Setup

```bash
npm install
```

> This repo uses **npm**. Stick with it so the lockfile stays consistent.

---

## 📘 Challenges

### 1. JS and Async Programming

- **[1.1 JavaScript Fundamentals](1-js-and-async-programming/1-javascript-fundamentals)**
  Five exercises covering core JavaScript. _Verified by Jest — the only module
  with tests._

- **[1.2 Asynchronous JavaScript](1-js-and-async-programming/2-asynchronous-js)**
  Three exercises on callbacks, promises, and `async/await`. _Run each file
  directly._

### 2. Core Node.js

- **[Core Node.js Modules](2-core-nodejs)**
  Build a "Wishlist Tracker" CLI from scratch using only built-in modules.
  _No starter code — the whole thing is yours._

### 3. TypeScript

- **[TypeScript](3-typescript)**
  Type an e-commerce dataset, then build custom utility types and a generic deep
  clone. _Verified by the compiler._

### 4. Database

- **[Database](4-database)**
  Eight SQL queries against the Pagila rental database, plus a transactional
  fund-transfer function. _Run against PostgreSQL in Docker._

---

## 🛠️ Commands

Run these from the repository root.

| Command                                 | What it does                                       |
| --------------------------------------- | -------------------------------------------------- |
| `npm test`                              | Run the full Jest suite                            |
| `npm test -- 1-time-difference.spec.js` | Run one test file (the argument is a path pattern) |
| `npm run test:watch`                    | Re-run tests as you save                           |
| `npm run lint`                          | Lint with ESLint                                   |
| `npm run lint:fix`                      | Lint and auto-fix                                  |
| `npm run prettier`                      | Check formatting                                   |
| `npm run format`                        | Auto-fix lint **and** formatting                   |
| `npx tsc --noEmit`                      | Type-check module 3 without emitting files         |
| `docker compose up`                     | Start PostgreSQL (run from `4-database/`)          |

---

## 📤 How to submit your work

The same flow for every module:

1. **[Fork this repository](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo)**
   and clone your fork locally.
2. **Create a branch** for the module you're working on — e.g.
   `git checkout -b challenge/javascript-fundamentals`.
3. **Implement the exercises** in the files provided. Leave the challenge
   descriptions and the test files as they are.
4. **Commit** with clear messages following
   [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) —
   e.g. `feat: solve time difference calculator`.
5. **Push** your branch to your fork.
6. **[Open a pull request](https://docs.github.com/en/pull-requests)** against
   your fork's default branch.
7. **Share the pull request link with your mentor** for review.

> Commit as you go rather than all at once at the end. Your mentor reviews the
> journey, not just the destination.

---

## 💡 Tips for success

- **Read the whole brief first.** Each challenge lists its own constraints —
  "no external libraries", "don't use `any`", "only work inside this method".
  They're part of the exercise, not suggestions.
- **Make it pass, then make it clean.** Get to a working solution, then reread
  it and improve the naming and structure.
- **Prefer clarity over cleverness.** A readable solution beats a one-liner
  nobody can follow — including you, next week.
- **Get stuck on purpose.** Struggling with a problem before looking up the
  answer is what makes it stick. Reach for your mentor when you're properly
  blocked, not at the first error.
