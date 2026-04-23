/**
 * Catalog-refresh orchestration.
 *
 * `refreshCatalog` calls every fetcher concurrently, upserts the fresh
 * rows, then stamps `deprecatedAt` on any row that stopped appearing
 * in the provider's `/models` endpoint. One failing fetcher does not
 * abort the run; the remaining providers' rows are still upserted and
 * only their own rows are considered for deprecation.
 *
 * Idempotent by construction: safe to run on boot, on a cron, and on a
 * manual trigger.
 */

import type {
  CatalogStore,
  CatalogUpsert,
  Logger,
  ProviderFetcher,
} from './types.js';

export interface RefreshCatalogOptions {
  store: CatalogStore;
  fetchers: ReadonlyArray<ProviderFetcher>;
  /** Override the clock in tests. Defaults to `() => new Date()`. */
  now?: () => Date;
  /** Optional logger; defaults to a silent no-op. */
  logger?: Logger;
  /** Optional fetch impl forwarded to each fetcher. */
  fetchImpl?: Parameters<ProviderFetcher['fetchModels']>[0] extends
    | { fetchImpl?: infer F }
    | undefined
    ? F
    : never;
}

export interface RefreshCatalogResult {
  fetched: Record<string, number>;
  errors: Record<string, string>;
  deprecated: number;
}

const SILENT_LOGGER: Logger = {
  info: () => {},
  warn: () => {},
};

/**
 * Run one pass over every fetcher, upsert the fresh rows, and stamp
 * deprecation on missing rows.
 */
export async function refreshCatalog(
  options: RefreshCatalogOptions,
): Promise<RefreshCatalogResult> {
  const now = options.now ?? (() => new Date());
  const logger = options.logger ?? SILENT_LOGGER;
  const runStartedAt = now();

  const fetchPromises = options.fetchers.map(async (fetcher) => {
    try {
      const entries = await fetcher.fetchModels(
        options.fetchImpl ? { fetchImpl: options.fetchImpl } : undefined,
      );
      return { provider: fetcher.provider, entries, error: null as string | null };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.warn(
        `[llm-model-catalog] fetcher ${fetcher.provider} failed: ${msg}`,
      );
      return { provider: fetcher.provider, entries: [] as CatalogUpsert[], error: msg };
    }
  });

  const results = await Promise.all(fetchPromises);

  const allFresh: CatalogUpsert[] = [];
  const freshCounts: Record<string, number> = {};
  const errors: Record<string, string> = {};
  const succeededProviders = new Set<string>();
  for (const result of results) {
    freshCounts[result.provider] = result.entries.length;
    if (result.error) {
      errors[result.provider] = result.error;
    } else {
      succeededProviders.add(result.provider);
    }
    allFresh.push(...result.entries);
  }

  if (allFresh.length > 0) {
    await options.store.upsert(allFresh, now());
  }

  const allRows = await options.store.list();
  const freshKeys = new Set(
    allFresh.map((e) => `${e.provider}:${e.modelId}`),
  );
  const toDeprecate = allRows.filter(
    (row) =>
      succeededProviders.has(row.provider) &&
      row.deprecatedAt === null &&
      row.lastSeenAt < runStartedAt &&
      !freshKeys.has(`${row.provider}:${row.modelId}`),
  );

  if (toDeprecate.length > 0) {
    await options.store.markDeprecated(
      toDeprecate.map((r) => ({ provider: r.provider, modelId: r.modelId })),
      now(),
    );
  }

  logger.info(
    `[llm-model-catalog] refresh complete: fetched=${JSON.stringify(freshCounts)} deprecated=${toDeprecate.length}`,
  );

  return {
    fetched: freshCounts,
    errors,
    deprecated: toDeprecate.length,
  };
}
