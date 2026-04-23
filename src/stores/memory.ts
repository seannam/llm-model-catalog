/**
 * In-memory `CatalogStore` for tests and ad-hoc scripts.
 *
 * Keyed on `provider:modelId`. No persistence, no IO.
 */

import type {
  CatalogEntry,
  CatalogStore,
  CatalogUpsert,
} from '../types.js';

function keyOf(provider: string, modelId: string): string {
  return `${provider}:${modelId}`;
}

export function createMemoryStore(
  seed: ReadonlyArray<CatalogEntry> = [],
): CatalogStore {
  const rows = new Map<string, CatalogEntry>();
  for (const row of seed) {
    rows.set(keyOf(row.provider, row.modelId), { ...row });
  }

  return {
    async list(): Promise<CatalogEntry[]> {
      return Array.from(rows.values()).map((r) => ({ ...r }));
    },
    async listByProvider(provider: string): Promise<CatalogEntry[]> {
      return Array.from(rows.values())
        .filter((r) => r.provider === provider)
        .map((r) => ({ ...r }));
    },
    async upsert(entries: CatalogUpsert[], now = new Date()): Promise<void> {
      for (const entry of entries) {
        const key = keyOf(entry.provider, entry.modelId);
        const existing = rows.get(key);
        if (existing) {
          rows.set(key, {
            ...existing,
            family: entry.family,
            displayName: entry.displayName,
            lastSeenAt: now,
            deprecatedAt: null,
          });
        } else {
          rows.set(key, {
            provider: entry.provider,
            modelId: entry.modelId,
            family: entry.family,
            displayName: entry.displayName,
            firstSeenAt: now,
            lastSeenAt: now,
            deprecatedAt: null,
          });
        }
      }
    },
    async markDeprecated(keys, at): Promise<void> {
      for (const { provider, modelId } of keys) {
        const key = keyOf(provider, modelId);
        const existing = rows.get(key);
        if (existing && existing.deprecatedAt === null) {
          rows.set(key, { ...existing, deprecatedAt: at });
        }
      }
    },
  };
}
