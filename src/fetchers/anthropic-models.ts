/**
 * Static fallback list for Anthropic's direct API, which does not
 * expose a `/models` endpoint. Update this list when Anthropic
 * announces a model add/remove/rename.
 *
 * Consumers who want a tighter update cadence can inject their own
 * list via `anthropicFetcher({ models: [...] })`.
 */

import type { CatalogUpsert } from '../types.js';
import { inferFamily } from '../families.js';

export interface AnthropicStaticModel {
  id: string;
  displayName: string;
}

export const ANTHROPIC_STATIC_MODELS: ReadonlyArray<AnthropicStaticModel> = [
  { id: 'claude-opus-4-5', displayName: 'Claude Opus 4.5' },
  { id: 'claude-sonnet-4-5', displayName: 'Claude Sonnet 4.5' },
  { id: 'claude-haiku-4-5', displayName: 'Claude Haiku 4.5' },
  { id: 'claude-opus-4-1', displayName: 'Claude Opus 4.1' },
  { id: 'claude-sonnet-4', displayName: 'Claude Sonnet 4' },
  { id: 'claude-haiku-3-5', displayName: 'Claude Haiku 3.5' },
];

/** Turn a static-list entry into a `CatalogUpsert`. */
export function staticToUpsert(
  provider: string,
  model: AnthropicStaticModel,
): CatalogUpsert {
  return {
    provider,
    modelId: model.id,
    family: inferFamily(model.id),
    displayName: model.displayName,
  };
}
