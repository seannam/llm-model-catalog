/**
 * Public entry point for `@indiecraft/llm-model-catalog`.
 *
 * Consumers import types, the resolver, the refresher, and the built-in
 * fetchers from this module. Store implementations live under subpath
 * exports (`./memory`, `./postgres`) so optional peer deps (`pg`) are
 * only loaded when asked for.
 */

export type {
  CatalogEntry,
  CatalogStore,
  CatalogUpsert,
  FetchLike,
  Logger,
  ModelFamily,
  ProviderFetcher,
} from './types.js';

export { inferFamily, defineFamily } from './families.js';

export {
  resolveModel,
  type ResolveModelOptions,
  type ResolveModelResult,
} from './resolve.js';

export { SEED_CATALOG, DEFAULT_TIER_PREFERENCES } from './seed.js';

export {
  refreshCatalog,
  type RefreshCatalogOptions,
  type RefreshCatalogResult,
} from './refresh.js';

export { migrationSql, type MigrationSqlOptions } from './migration.js';

export { straicoFetcher, type StraicoFetcherOptions } from './fetchers/straico.js';
export {
  openRouterFetcher,
  type OpenRouterFetcherOptions,
} from './fetchers/openrouter.js';
export {
  anthropicFetcher,
  type AnthropicFetcherOptions,
} from './fetchers/anthropic.js';
export { ollamaFetcher, type OllamaFetcherOptions } from './fetchers/ollama.js';
export {
  ANTHROPIC_STATIC_MODELS,
  type AnthropicStaticModel,
} from './fetchers/anthropic-models.js';

export { createMemoryStore } from './stores/memory.js';
export {
  createPostgresStore,
  type CreatePostgresStoreOptions,
} from './stores/postgres.js';
