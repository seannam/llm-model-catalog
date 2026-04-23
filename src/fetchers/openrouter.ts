/**
 * OpenRouter fetcher.
 *
 * Hits `GET {baseURL}/models` with bearer auth. OpenRouter's shape is
 * `{ data: [{ id, name }, ...] }`.
 */

import type { CatalogUpsert, FetchLike, ProviderFetcher } from '../types.js';
import { inferFamily } from '../families.js';

const DEFAULT_BASE_URL = 'https://openrouter.ai/api/v1';

export interface OpenRouterFetcherOptions {
  apiKey: string;
  baseURL?: string;
  /** Override provider name (default `'openrouter'`). */
  provider?: string;
}

interface RawModel {
  id?: unknown;
  name?: unknown;
}

export function openRouterFetcher(
  options: OpenRouterFetcherOptions,
): ProviderFetcher {
  const provider = options.provider ?? 'openrouter';
  const baseURL = (options.baseURL ?? DEFAULT_BASE_URL).replace(/\/+$/, '');
  const apiKey = options.apiKey;

  return {
    provider,
    async fetchModels(opts): Promise<CatalogUpsert[]> {
      const fetchImpl: FetchLike =
        opts?.fetchImpl ??
        ((input, init) => fetch(input, init) as unknown as ReturnType<FetchLike>);

      const res = await fetchImpl(`${baseURL}/models`, {
        headers: {
          Authorization: `Bearer ${apiKey}`,
          Accept: 'application/json',
        },
      });

      if (!res.ok) {
        throw new Error(
          `openrouter /models request failed: ${res.status} ${await res.text().catch(() => '')}`.trim(),
        );
      }

      const json = (await res.json()) as { data?: RawModel[] } | RawModel[];
      const rows: RawModel[] = Array.isArray(json)
        ? json
        : Array.isArray(json.data)
          ? json.data
          : [];

      const out: CatalogUpsert[] = [];
      for (const row of rows) {
        if (typeof row.id !== 'string' || row.id.length === 0) continue;
        out.push({
          provider,
          modelId: row.id,
          family: inferFamily(row.id),
          displayName:
            typeof row.name === 'string' && row.name.length > 0 ? row.name : row.id,
        });
      }
      return out;
    },
  };
}
