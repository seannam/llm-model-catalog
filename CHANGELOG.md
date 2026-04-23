# Changelog

All notable changes to `@indiecraft/llm-model-catalog` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-04-22

### Added

- Initial public release.
- Core `CatalogEntry`, `ModelFamily`, and `CatalogStore` types.
- `inferFamily` / `defineFamily` with a default regex table covering Claude
  (Haiku / Sonnet / Opus), GPT-4o / GPT-4o-mini, and Qwen Coder.
- `resolveModel({ provider, catalog, preferences, envHint? })` for
  preference-walk model selection with an env hint short-circuit.
- `SEED_CATALOG` and `DEFAULT_TIER_PREFERENCES` exported as sensible
  defaults so consumers can boot without network access.
- `refreshCatalog({ store, fetchers })` orchestration routine that upserts
  fresh entries and stamps missing rows with `deprecatedAt`.
- Fetchers for Straico, OpenRouter, Anthropic (static fallback), and Ollama.
- Stores: `createMemoryStore()` and `createPostgresStore({ pool, schema })`
  (the latter as a lazy peer-dep on `pg`).
- `migrationSql({ schema, tableName? })` helper that emits an idempotent
  `CREATE TABLE IF NOT EXISTS` SQL string for any migration runner.
- ESM-only distribution with subpath exports for `./postgres`, `./memory`,
  and `./migration`.
