/**
 * Straico fetcher.
 *
 * Hits `GET {baseURL}/models` with bearer auth and accepts either a
 * `{ data: [...] }` envelope or a bare array. Each row is normalized
 * to a `CatalogUpsert` with a family inferred from the model ID.
 */

import type { CatalogUpsert, FetchLike, ProviderFetcher } from '../types.js';
import { inferFamily } from '../families.js';

const DEFAULT_BASE_URL = 'https://api.straico.com/v0';

export interface StraicoFetcherOptions {
  apiKey: string;
  baseURL?: string;
  /** Override provider name (default `'straico'`). */
  provider?: string;
}

interface RawModel {
  id?: unknown;
  model?: unknown;
  name?: unknown;
  display_name?: unknown;
  displayName?: unknown;
}

function toRawArray(json: unknown): RawModel[] {
  if (Array.isArray(json)) return json as RawModel[];
  if (json && typeof json === 'object') {
    const obj = json as { data?: unknown; models?: unknown };
    if (Array.isArray(obj.data)) return obj.data as RawModel[];
    if (Array.isArray(obj.models)) return obj.models as RawModel[];
  }
  return [];
}

function pickId(row: RawModel): string | null {
  if (typeof row.id === 'string' && row.id.length > 0) return row.id;
  if (typeof row.model === 'string' && row.model.length > 0) return row.model;
  return null;
}

function pickDisplayName(row: RawModel): string | null {
  if (typeof row.display_name === 'string' && row.display_name.length > 0) {
    return row.display_name;
  }
  if (typeof row.displayName === 'string' && row.displayName.length > 0) {
    return row.displayName;
  }
  if (typeof row.name === 'string' && row.name.length > 0) return row.name;
  return null;
}

export function straicoFetcher(
  options: StraicoFetcherOptions,
): ProviderFetcher {
  const provider = options.provider ?? 'straico';
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
          `straico /models request failed: ${res.status} ${await res.text().catch(() => '')}`.trim(),
        );
      }

      const json = await res.json();
      const raws = toRawArray(json);
      const out: CatalogUpsert[] = [];
      for (const row of raws) {
        const id = pickId(row);
        if (!id) continue;
        out.push({
          provider,
          modelId: id,
          family: inferFamily(id),
          displayName: pickDisplayName(row) ?? id,
        });
      }
      return out;
    },
  };
}
