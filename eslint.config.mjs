import { defineConfig } from "eslint/config";
import globals from "globals";
import tseslint from "typescript-eslint";
import pluginJest from "eslint-plugin-jest";
import eslintConfigPrettier from "eslint-config-prettier/flat";

export default defineConfig([
  {
    plugins: {
      jest: pluginJest, prettier: eslintConfigPrettier, "@typescript-eslint": tseslint.plugin,
    },
    languageOptions: {
      globals: {
        ...globals.commonjs,
        ...globals.node,
        ...globals.jest,
      },
    },
    rules: {
      "no-unused-vars": [
        "warn",
        { args: "after-used", ignoreRestSiblings: true },
      ],
    },
  },
]);
