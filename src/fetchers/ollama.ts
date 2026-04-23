/**
 * Ollama fetcher.
 *
 * Hits `GET {baseURL}/api/tags` which returns the models currently
 * pulled locally. Shape: `{ models: [{ name, model }, ...] }`.
 */

import type { CatalogUpsert, FetchLike, ProviderFetcher } from '../types.js';
import { inferFamily } from '../families.js';

const DEFAULT_BASE_URL = 'http://localhost:11434';

export interface OllamaFetcherOptions {
  baseURL?: string;
  /** Override provider name (default `'ollama'`). */
  provider?: string;
}

interface RawModel {
  name?: unknown;
  model?: unknown;
}

export function ollamaFetcher(
  options: OllamaFetcherOptions = {},
): ProviderFetcher {
  const provider = options.provider ?? 'ollama';
  const baseURL = (options.baseURL ?? DEFAULT_BASE_URL).replace(/\/+$/, '');

  return {
    provider,
    async fetchModels(opts): Promise<CatalogUpsert[]> {
      const fetchImpl: FetchLike =
        opts?.fetchImpl ??
        ((input, init) => fetch(input, init) as unknown as ReturnType<FetchLike>);

      const res = await fetchImpl(`${baseURL}/api/tags`, {
        headers: { Accept: 'application/json' },
      });

      if (!res.ok) {
        throw new Error(
          `ollama /api/tags request failed: ${res.status} ${await res.text().catch(() => '')}`.trim(),
        );
      }

      const json = (await res.json()) as { models?: RawModel[] };
      const rows: RawModel[] = Array.isArray(json.models) ? json.models : [];

      const out: CatalogUpsert[] = [];
      for (const row of rows) {
        const id =
          typeof row.model === 'string'
            ? row.model
            : typeof row.name === 'string'
              ? row.name
              : null;
        if (!id) continue;
        out.push({
          provider,
          modelId: id,
          family: inferFamily(id),
          displayName: id,
        });
      }
      return out;
    },
  };
}
