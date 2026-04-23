/**
 * Offline-safe defaults.
 *
 * `SEED_CATALOG` is a minimal one-Sonnet-per-provider catalog used when
 * the backing store is empty and the `/models` endpoints are
 * unreachable. It lets a fresh boot survive a network partition.
 *
 * `DEFAULT_TIER_PREFERENCES` is a reasonable map of tier-name to
 * ordered family preferences. The library has no built-in tier concept;
 * this export is just a default consumers can copy or override.
 */

import type { CatalogUpsert, ModelFamily } from './types.js';

const EPOCH = new Date('2026-04-22T00:00:00Z');

function seedEntry(
  provider: string,
  modelId: string,
  family: ModelFamily,
  displayName: string,
): CatalogUpsert & { firstSeenAt: Date; lastSeenAt: Date; deprecatedAt: null } {
  return {
    provider,
    modelId,
    family,
    displayName,
    firstSeenAt: EPOCH,
    lastSeenAt: EPOCH,
    deprecatedAt: null,
  };
}

/**
 * Minimal fallback catalog. Used when the store is empty and the
 * network is unreachable so boot-time model resolution still succeeds.
 */
export const SEED_CATALOG: ReadonlyArray<
  CatalogUpsert & { firstSeenAt: Date; lastSeenAt: Date; deprecatedAt: null }
> = [
  seedEntry('max', 'claude-sonnet-4-5', 'claude-sonnet', 'Claude Sonnet 4.5 (Max)'),
  seedEntry('straico', 'anthropic/claude-sonnet-4-5', 'claude-sonnet', 'Claude Sonnet 4.5'),
  seedEntry('openrouter', 'anthropic/claude-sonnet-4.5', 'claude-sonnet', 'Claude Sonnet 4.5'),
  seedEntry('anthropic', 'claude-sonnet-4-5', 'claude-sonnet', 'Claude Sonnet 4.5'),
  seedEntry('ollama', 'qwen2.5-coder:32b', 'qwen-coder', 'Qwen 2.5 Coder 32B'),
  seedEntry('stub', 'stub-canned', 'stub', 'Stub canned responses'),
];

/**
 * Reasonable default family preferences for a three-tier consumer
 * (routine / standard / complex). Consumers can copy this map, tweak
 * an individual tier, or ignore it entirely and supply their own
 * preferences array to `resolveModel`.
 */
export const DEFAULT_TIER_PREFERENCES: Record<
  'routine' | 'standard' | 'complex',
  ReadonlyArray<ModelFamily>
> = {
  routine: ['qwen-coder', 'claude-haiku', 'gpt-4o-mini', 'claude-sonnet'],
  standard: ['claude-sonnet', 'gpt-4o', 'claude-haiku'],
  complex: ['claude-opus', 'claude-sonnet', 'gpt-4o'],
};
