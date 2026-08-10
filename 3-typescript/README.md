# 3. TypeScript

Two parts. The first applies TypeScript to a realistic e-commerce dataset; the
second goes under the hood of the type system itself.

There are no tests here — **the compiler is your test suite.**

## 📝 Part 1: E-commerce

Four exercises in `1-ecommerce/`, built on the JSON files in
`1-ecommerce/data/`.

| File               | Challenge                                                         |
| ------------------ | ----------------------------------------------------------------- |
| `1-types.ts`       | Define types that describe the JSON data accurately               |
| `2-products.ts`    | Price analysis, a brand-enriched catalog, and image filtering     |
| `3-brands.ts`      | Count products per country, keyed by country name                 |
| `4-departments.ts` | Reshape departments to id, name, product count, and product names |

**Start with `1-types.ts`.** The other three build on the types you define
there, so time spent modelling the data properly pays off immediately.

As you write them, think about:

- Which properties are genuinely optional versus always present
- Where a union type describes the data better than a bare `string`
- Where a fixed set of values calls for an enum
- How entities relate — a product's `brandId` points at a brand

### Reading the data

Use the provided helper, `1-ecommerce/utils/read-json.util.ts`:

```ts
import { readJsonFile } from "./utils/read-json.util";

const products = await readJsonFile<Product>("./data/products.json");
```

`readJsonFile<T>` is generic — the type argument you pass is what makes the
result type-safe.

## 📝 Part 2: Custom Utility Types and Generics

| File                                                        | Challenge                                                                                                |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `2-custom-utility-types-and-generics/2-custom-utilities.ts` | Six exercises: recreate `Readonly` and `ReturnType`, and build `OmitByType`, `If`, `MyAwaited`, and more |
| `2-custom-utility-types-and-generics/1-deep-clone.ts`       | A generic function that deep-clones any value                                                            |

Each utility-type exercise asks for two things: the type itself, and an example
showing it works. The example is how you prove it — write one that would fail to
compile if the type were wrong.

## ✅ Checking your work

Type-check everything without emitting any files:

```bash
npx tsc --noEmit
```

> Run it with `--noEmit`. The `tsconfig.json` has no `outDir`, so a bare `tsc`
> drops compiled `.js` files next to your sources.

Type-checking is your main feedback loop — there's no `ts-node` here. If you
want to actually execute a file to print something, Node runs TypeScript
directly:

```bash
node --experimental-strip-types 3-typescript/1-ecommerce/2-products.ts   # Node 22
node 3-typescript/1-ecommerce/2-products.ts                             # Node 23+
```

Note the exercise files don't call their own functions, so add a call at the
bottom if you want to see output.

## 💡 Tips

- **Don't use `any` or `unknown` in your solutions.** The stubs ship with them
  as placeholders — replacing them with real types is part of the exercise.
- `strict` mode is on. If the compiler is complaining, it has usually found
  something genuine.
- Let inference do the work. Annotate the inputs and outputs; you rarely need to
  annotate everything in between.
- A type error is feedback, not failure. Read the message all the way through —
  the useful part is often at the end.

## 📤 Submitting

See **[How to submit your work](../README.md#-how-to-submit-your-work)** in the
root README.
