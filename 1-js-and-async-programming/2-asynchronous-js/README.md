# 1.2 Asynchronous JavaScript

Three exercises on the same underlying problem — doing work that takes time —
solved three different ways. Work through them in order; each style builds on
the one before it.

## 📝 The exercises

| File               | Challenge                                                                             |
| ------------------ | ------------------------------------------------------------------------------------- |
| `1-callback.js`    | Retry a flaky request until it succeeds — callback style                              |
| `2-promise.js`     | Find users who dislike more movies than they like — using Promise static methods only |
| `3-async-await.js` | Find the most common subscription among those same users — using `await`              |

Each file holds the brief as a comment and a stub underneath. Write your
solution in the stub.

## ▶️ Running them

There are no tests here — you run each file and read the output:

```bash
node 1-callback.js
```

The files call your function at the bottom, so running the file exercises your
code immediately.

## 🧰 The provided utilities

`utils/` contains helpers you should treat as an external service you don't
control. Use them, don't modify them.

- **`make-requests.js`** — simulates a network call with a 1 second delay.

  > ⚠️ **It fails roughly 9 times out of 10, on purpose.** That's the whole
  > point of the retry exercise. Seeing "Request failed on attempt 1" does not
  > mean your code is broken — run it a few times and watch how your retry
  > logic copes.

- **`mocked-api.js`** — returns promises of users, their liked and disliked
  movies, and their subscription tier. `getUserSubscriptionByUserId` takes a
  single id, so you'll need to think about how to fetch for many users at once.

## 💡 Tips

- Handle the failure path, not just the happy one. These exercises are about
  what your code does when things go wrong.
- Watch for work you're doing sequentially that could run in parallel — and
  work you're running in parallel that shouldn't be.
- No external libraries. Everything here is solvable with the language itself.

## 📤 Submitting

See **[How to submit your work](../../README.md#-how-to-submit-your-work)** in
the root README.
