# @indiecraft/llm-model-catalog

Dynamically discover and resolve Claude / Straico / OpenRouter / Ollama
models without hardcoding model IDs. Pulls each provider's current
model list via its `/models` endpoint, persists it in a pluggable
store, and lets your app resolve a model at call time from an ordered
list of family preferences.

Fixes the class of bug where a hardcoded `STRAICO_MODEL=...` or
`ANTHROPIC_MODEL=...` goes stale (or is typo'd on a Tuesday night) and
every LLM call starts returning `Model not found`.

## Install

```bash
npm install @indiecraft/llm-model-catalog
# only if you use the Postgres store:
npm install pg
```

## Quick start

```ts
import { Pool } from 'pg';
import {
  DEFAULT_TIER_PREFERENCES,
  refreshCatalog,
  resolveModel,
  straicoFetcher,
} from '@indiecraft/llm-model-catalog';
import { createPostgresStore } from '@indiecraft/llm-model-catalog/postgres';
import { migrationSql } from '@indiecraft/llm-model-catalog/migration';

// 1. One-time: apply the table via your migration runner of choice.
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
await pool.query(migrationSql({ schema: 'public' }));

// 2. On boot and on a cron: refresh the catalog.
const store = createPostgresStore({ pool, schema: 'public' });
await refreshCatalog({
  store,
  fetchers: [straicoFetcher({ apiKey: process.env.STRAICO_API_KEY! })],
});

// 3. At call time: pick a model from the catalog.
const catalog = await store.listByProvider('straico');
const model = resolveModel({
  provider: 'straico',
  catalog,
  preferences: DEFAULT_TIER_PREFERENCES.standard,
  envHint: process.env.STRAICO_MODEL,
});
// -> { modelId: 'anthropic/claude-sonnet-4-5', family: 'claude-sonnet', source: 'preference', ... }

if (!model) throw new Error('no Straico model satisfies standard-tier preferences');

// Pass `model.modelId` to the Straico chat completions call.
```

## Scheduling the refresh

Call `refreshCatalog` on app boot and on whatever scheduler the host
has (BullMQ, node-cron, a Lambda schedule, a Kubernetes CronJob). A
6-hour cadence is a reasonable default: `/models` endpoints return a
few hundred rows fast, and providers change their catalog on the order
of weeks.

The library ships the function; the scheduler is yours.

## Stores

- `@indiecraft/llm-model-catalog/postgres` — `pg`-backed, Postgres 14+.
  `pg` is a peer dep, loaded lazily.
- `@indiecraft/llm-model-catalog/memory` — in-memory, no persistence;
  useful for tests and one-shot scripts.
- Implement `CatalogStore` yourself for SQLite, MySQL, Redis, etc.

## Custom providers

Implement `ProviderFetcher` for any `/models`-style endpoint and pass
it to `refreshCatalog({ fetchers: [...] })`. Example:

```ts
import type { ProviderFetcher } from '@indiecraft/llm-model-catalog';
import { inferFamily } from '@indiecraft/llm-model-catalog';

const geminiFetcher: ProviderFetcher = {
  provider: 'gemini',
  async fetchModels() {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models?key=${process.env.GEMINI_API_KEY}`,
    );
    const json = (await res.json()) as { models: { name: string; displayName: string }[] };
    return json.models.map((m) => ({
      provider: 'gemini',
      modelId: m.name.replace(/^models\//, ''),
      family: inferFamily(m.name),
      displayName: m.displayName,
    }));
  },
};
```

## Custom families

The default family table covers Claude, GPT-4o, and Qwen Coder. Add
families for new providers with `defineFamily`:

```ts
import { defineFamily } from '@indiecraft/llm-model-catalog';

defineFamily(/gemini-.*pro/i, 'gemini-pro');
```

## Public API

| Export | Description |
| --- | --- |
| `CatalogEntry`, `CatalogUpsert` | Row shapes. |
| `CatalogStore` | Store interface. Implement to back onto your datastore of choice. |
| `ProviderFetcher` | Fetcher interface. |
| `ModelFamily` | Semantic family string. |
| `inferFamily(modelId)` | Classify a raw model ID. |
| `defineFamily(regex, family)` | Extend the family table. |
| `resolveModel(opts)` | Pick a model from a catalog given preferences. |
| `refreshCatalog(opts)` | Orchestrate one fetch-and-upsert pass. |
| `SEED_CATALOG` | Offline-safe fallback catalog. |
| `DEFAULT_TIER_PREFERENCES` | Sensible tier → preference map. |
| `migrationSql({ schema, tableName? })` | Render the table DDL. |
| `straicoFetcher`, `openRouterFetcher`, `anthropicFetcher`, `ollamaFetcher` | Built-in fetchers. |
| `createMemoryStore(seed?)` | In-memory store. |
| `createPostgresStore({ pool, schema })` | `pg`-backed store. |

## Versioning

Semantic versioning, independent of any consumer. Breaking changes to
the public API bump the major; new exports bump the minor; bug fixes
bump the patch.

## License

MIT.
