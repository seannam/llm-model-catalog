/**
 * Anthropic direct-API fetcher.
 *
 * Anthropic's direct API does not expose a `/models` endpoint, so this
 * fetcher returns a static list. The default list is
 * `ANTHROPIC_STATIC_MODELS`; consumers can inject a custom list.
 */

import type { CatalogUpsert, ProviderFetcher } from '../types.js';
import {
  ANTHROPIC_STATIC_MODELS,
  staticToUpsert,
  type AnthropicStaticModel,
} from './anthropic-models.js';

export interface AnthropicFetcherOptions {
  /** Override provider name (default `'anthropic'`). */
  provider?: string;
  /** Override the static list. Defaults to `ANTHROPIC_STATIC_MODELS`. */
  models?: ReadonlyArray<AnthropicStaticModel>;
}

export function anthropicFetcher(
  options: AnthropicFetcherOptions = {},
): ProviderFetcher {
  const provider = options.provider ?? 'anthropic';
  const models = options.models ?? ANTHROPIC_STATIC_MODELS;
  return {
    provider,
    async fetchModels(): Promise<CatalogUpsert[]> {
      return models.map((m) => staticToUpsert(provider, m));
    },
  };
}
