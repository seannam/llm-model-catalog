# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `npm run build` — emit ESM + `.d.ts` to `dist/` via `tsconfig.build.json`.
- `npm run typecheck` — type-only pass over `src/**` and `tests/**` (`tsc --noEmit`).
- `npm test` — run the full Vitest suite (`vitest run`).
- `npx vitest run tests/resolve.test.ts` — run a single file.
- `npx vitest run -t "resolveModel returns the env hint"` — run a single named test.

Node `>=22.11.0` is required (see `package.json` engines).

## Architecture

This is a published library (`@indiecraft/llm-model-catalog`) that turns each LLM provider's `/models` endpoint into a queryable, persisted catalog so downstream apps can resolve model IDs at call time instead of hardcoding them. There is no runtime, server, or scheduler in the package — the library exposes pure functions and a store interface; consumers wire in their own scheduler and DB pool.

The data flow is **fetcher → store → resolver**:

1. **Fetchers** (`src/fetchers/`) implement `ProviderFetcher` (`{ provider, fetchModels() }`) and return `CatalogUpsert[]`. Each one is independently exported (`straicoFetcher`, `openRouterFetcher`, `anthropicFetcher`, `ollamaFetcher`). Anthropic has no public `/models` endpoint, so its fetcher returns `ANTHROPIC_STATIC_MODELS` instead. Every fetcher accepts an injected `FetchLike` impl for tests.
2. **`refreshCatalog`** (`src/refresh.ts`) runs all fetchers concurrently with `Promise.all`, upserts the union, then stamps `deprecatedAt` on rows that (a) belong to a provider whose fetch *succeeded* and (b) did not appear in this run. A failing fetcher is isolated: its rows are skipped for both upsert and deprecation, so a single provider outage cannot mass-deprecate the catalog.
3. **Stores** (`src/stores/`) implement `CatalogStore`. `createMemoryStore()` is for tests and one-shot scripts; `createPostgresStore({ pool, schema })` is the production path. `pg` is an **optional peer dep** — it is never imported at the top level, only inside the postgres subpath export, so consumers using only the memory store don't need it installed.
4. **`resolveModel`** (`src/resolve.ts`) is the call-site entry point. It filters out `deprecatedAt != null` rows, then walks: env-hint exact match → ordered `preferences` family walk → first remaining row as `fallback`. The `source` field on the result records which path won, for boot-log diagnostics.

### Cross-cutting pieces

- **`families.ts`** maps model IDs to a `ModelFamily` via a regex table. User rules registered with `defineFamily` are checked **before** defaults so consumers can override. There is a private `__resetUserFamilies()` for tests — not part of the public surface.
- **`migration.ts`** ships only the SQL string for the catalog table, not a migration runner. Both it and `createPostgresStore` validate `schema` / `tableName` against `^[a-zA-Z_][a-zA-Z0-9_]*$` because identifiers cannot be parameterized in pg; values always go through `$N` placeholders.
- **`seed.ts`** exports `SEED_CATALOG` (offline-safe one-Sonnet-per-provider rows) and `DEFAULT_TIER_PREFERENCES` (`routine` / `standard` / `complex` family lists). The library has no built-in tier concept; this map is a default consumers can copy.

### Public surface

`src/index.ts` is the single root entry. Subpath exports are declared in `package.json#exports` and must stay in sync:

- `.` → `src/index.ts` (types, resolver, refresher, fetchers, family helpers, seed, memory store helper)
- `./postgres` → `src/stores/postgres.ts`
- `./memory` → `src/stores/memory.ts`
- `./migration` → `src/migration.ts`

Adding a new subpath export requires updating both `package.json#exports` and the `files` allowlist if needed.

### Test layout

`tests/` mirrors `src/` one-to-one (`tests/fetchers/*.test.ts`, `tests/stores/*.test.ts`). Fetcher tests inject a `FetchLike` mock; the postgres store test uses a fake `PgPoolLike`. Vitest has `globals: false`, so import `describe` / `it` / `expect` from `vitest` explicitly.

## Conventions

- ESM-only: every relative import ends in `.js` (TypeScript `moduleResolution: "bundler"` plus emitted ESM). Do not drop the extension.
- `noUncheckedIndexedAccess` is on — array/object index access yields `T | undefined` and must be narrowed.
- Keep the public type surface in `src/types.ts` structural and dependency-free so consumers never import an implementation class.
- The package is versioned independently of any consumer; follow SemVer per the README and update `CHANGELOG.md` for any user-visible change.
