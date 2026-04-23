/**
 * Model-selection resolver.
 *
 * `resolveModel` picks a provider-native model ID from a catalog given
 * an ordered preference list. It accepts an optional `envHint` which
 * short-circuits the walk when the hint matches a live catalog entry
 * (the operator stays in control when they set an env var that is
 * still valid). When the hint misses or the env is unset, the walk
 * falls back to the first catalog entry whose `family` is in
 * `preferences`.
 *
 * Rows with `deprecatedAt != null` are excluded unconditionally.
 */

import type { CatalogEntry, ModelFamily } from './types.js';

export interface ResolveModelOptions {
  /** Provider whose catalog we're resolving for (e.g. 'straico'). */
  provider: string;
  /**
   * The caller's view of the catalog. Usually `store.listByProvider(provider)`,
   * but can be any pre-filtered list for testing.
   */
  catalog: ReadonlyArray<CatalogEntry>;
  /**
   * Ordered family preferences. The resolver returns the first catalog
   * row whose family appears in this list. Earlier entries win.
   */
  preferences: ReadonlyArray<ModelFamily>;
  /**
   * Optional operator-supplied hint. When the catalog contains this
   * exact `modelId` (and it is not deprecated), the resolver returns
   * it verbatim. Otherwise the hint is ignored and the preference walk
   * runs as normal.
   */
  envHint?: string;
}

export interface ResolveModelResult {
  modelId: string;
  family: ModelFamily;
  source: 'env-hint' | 'preference' | 'fallback';
  entry: CatalogEntry;
}

/**
 * Resolve a model ID from a catalog.
 *
 * Returns `null` when the filtered catalog is empty. Otherwise returns
 * a `ResolveModelResult` describing both the chosen model and how the
 * resolver reached it (useful for boot-log diagnostics).
 */
export function resolveModel(options: ResolveModelOptions): ResolveModelResult | null {
  const live = options.catalog.filter(
    (e) => e.provider === options.provider && e.deprecatedAt === null,
  );
  if (live.length === 0) return null;

  const hint = options.envHint?.trim();
  if (hint) {
    const hit = live.find((e) => e.modelId === hint);
    if (hit) {
      return {
        modelId: hit.modelId,
        family: hit.family,
        source: 'env-hint',
        entry: hit,
      };
    }
  }

  for (const family of options.preferences) {
    const hit = live.find((e) => e.family === family);
    if (hit) {
      return {
        modelId: hit.modelId,
        family: hit.family,
        source: 'preference',
        entry: hit,
      };
    }
  }

  const fallback = live[0];
  if (!fallback) return null;
  return {
    modelId: fallback.modelId,
    family: fallback.family,
    source: 'fallback',
    entry: fallback,
  };
}
