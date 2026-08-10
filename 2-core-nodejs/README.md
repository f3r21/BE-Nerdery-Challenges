# 2. Core Node.js Modules

Everything so far has been pure JavaScript. This module is about what **Node**
adds: reading and writing files, taking input from the command line, and keeping
data around after the process exits.

You'll build one complete application end to end.

## 🎯 The challenge: Wishlist Tracker

A command-line tool for managing a personal wishlist. Each item has a **name**,
a **price**, and a **store**.

> **No starter code.** This folder contains only this README — the structure is
> yours to design. Create your files here, in `2-core-nodejs/`.

### Requirements

**Built-in modules only.** No npm packages — no `commander`, no `inquirer`, no
`chalk`. Reach for `fs`, `readline`, `path`, and `process` instead. Working
without a framework is the entire point of this module.

**CRUD operations**

- **Create** — add an item with a name, price, and store
- **Read** — list every item in the wishlist
- **Update** — edit an existing item, selected by its ID
- **Delete** — remove an item, selected by its ID

IDs are generated incrementally and are how the user refers to an item.

**Data persistence**

- Store the wishlist in a JSON file
- Load it on startup and save on change, so data survives a restart

**User interface**

- Drive the tool through command-line arguments
- Validate input and fail with a clear message — a bad price or an unknown ID
  should never crash the program

### Bonus

Reach for these once the core tool works:

- **CSV export** — write the wishlist to a `.csv` file with name, price, store
- **Summary view** — most expensive item, average price, total cost, and item
  count

## 💡 Tips

- Sketch your commands before writing code. Knowing what
  `node wishlist.js add --name "Keyboard" --price 120 --store "Logitech"` should
  do makes the implementation obvious.
- Separate the pieces: reading and writing the file, parsing arguments, and the
  wishlist logic itself are three different jobs. Keeping them apart is what
  makes the bonus features easy to add later.
- Think about the first run, when the JSON file doesn't exist yet.
- Node's file APIs come in callback, promise, and sync flavours. Pick one and be
  consistent.

## 📤 Submitting

See **[How to submit your work](../README.md#-how-to-submit-your-work)** in the
root README.
