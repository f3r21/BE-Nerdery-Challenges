# 1.1 JavaScript Fundamentals

Five exercises to sharpen the core JavaScript you'll lean on for everything
else: string and array manipulation, recursion, and algorithmic thinking.

This is the only module with a test suite. Every exercise ships with the tests
that grade it, so you always know exactly when you're done.

## 📝 The exercises

| File                         | Challenge                                                       |
| ---------------------------- | --------------------------------------------------------------- |
| `1-time-difference.js`       | Format the gap between two times as `HH:MM:SS`                  |
| `2-array-rotation.js`        | Rotate an array _n_ positions clockwise, wrapping around        |
| `3-factorial-chain.js`       | Sum the factorials of `1…n`, return the last digits as a string |
| `4-palindrome-counter.js`    | Count palindromic words at or above a minimum length            |
| `5-find-majority-element.js` | Find the element appearing more than `n/2` times, or `null`     |

Each `N-name.js` holds the brief as a comment and an empty function underneath.
Write your solution in that function.

**Keep the existing `module.exports` line.** The tests import your function
directly — change the export shape and they'll fail before your logic even runs.

## 🧪 Running the tests

Run one exercise's tests:

```bash
npm test -- 1-time-difference.spec.js
```

Or re-run them automatically as you save:

```bash
npm run test:watch -- 1-time-difference.spec.js
```

Drop the filename to run all five at once:

```bash
npm test
```

> **Don't edit the `.spec.js` files.** They define what "correct" means for this
> module. If a test looks wrong to you, that's worth a conversation with your
> mentor — it usually means the brief is being read differently than intended.

## 💡 Tips

- Read the examples in the challenge comment. They pin down the edge cases the
  prose leaves vague.
- Let a failing test guide you. The assertion message tells you the exact input
  and the expected output.
- Once the tests are green, reread your solution and clean it up. Green tests
  are the floor, not the ceiling.

## 📤 Submitting

See **[How to submit your work](../../README.md#-how-to-submit-your-work)** in
the root README.
