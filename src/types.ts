/**
 * Public type surface for `@indiecraft/llm-model-catalog`.
 *
 * The library deliberately speaks in plain structural types so consumers
 * never need to import implementation classes. Everything user-facing is
 * exported from `./index.js`.
 */

/**
 * Semantic family of an LLM. The default family table in `families.ts`
 * covers the families shipped by this library; consumers can extend it
 * at runtime via `defineFamily(regex, family)`.
 */
export type ModelFamily =
  | 'claude-haiku'
  | 'claude-sonnet'
  | 'claude-opus'
  | 'gpt-4o'
  | 'gpt-4o-mini'
  | 'qwen-coder'
  | 'stub'
  | 'unknown'
  | (string & { __modelFamily?: never });

/**
 * One row in the model catalog. `provider` + `modelId` is the primary
 * key. `firstSeenAt` / `lastSeenAt` are catalog-maintenance timestamps;
 * `deprecatedAt` is set by `refreshCatalog` when a model stops appearing
 * in its provider's `/models` endpoint.
 */
export interface CatalogEntry {
  provider: string;
  modelId: string;
  family: ModelFamily;
  displayName: string | null;
  firstSeenAt: Date;
  lastSeenAt: Date;
  deprecatedAt: Date | null;
}

/** Upsert payload shape: provider + modelId + family + displayName only. */
export type CatalogUpsert = Pick<
  CatalogEntry,
  'provider' | 'modelId' | 'family' | 'displayName'
>;

/**
 * Pluggable catalog store. The library ships a Postgres-backed store
 * and an in-memory store; any other backing (SQLite, Redis, Firestore)
 * is a matter of implementing this interface.
 */
export interface CatalogStore {
  list(): Promise<CatalogEntry[]>;
  listByProvider(provider: string): Promise<CatalogEntry[]>;
  upsert(entries: CatalogUpsert[], now?: Date): Promise<void>;
  markDeprecated(
    keys: { provider: string; modelId: string }[],
    at: Date,
  ): Promise<void>;
}

/** Minimal `fetch` shape accepted by every fetcher for test injection. */
export type FetchLike = (
  input: string,
  init?: { headers?: Record<string, string>; signal?: AbortSignal },
) => Promise<{ ok: boolean; status: number; json(): Promise<unknown>; text(): Promise<string> }>;

/** Minimal logger shape accepted by `refreshCatalog`. */
export interface Logger {
  info: (msg: string, ...rest: unknown[]) => void;
  warn: (msg: string, ...rest: unknown[]) => void;
}

/**
 * A fetcher pulls the current catalog for one provider. Every
 * first-party fetcher in this library (`straico`, `openrouter`,
 * `anthropic`, `ollama`) implements this shape; add a custom provider
 * by implementing one yourself and passing it to `refreshCatalog`.
 */
export interface ProviderFetcher {
  provider: string;
  fetchModels(opts?: { fetchImpl?: FetchLike }): Promise<CatalogUpsert[]>;
}
