/**
 * Model-family inference and extension.
 *
 * The default regex table covers the families this library ships with.
 * `defineFamily(regex, family)` appends to the table at runtime so
 * consumers can map additional provider IDs (Gemini, Mistral, custom
 * fine-tunes) to a family without forking.
 *
 * Rules are evaluated in insertion order; the first match wins. This
 * lets consumers shadow a default rule by inserting a more-specific one
 * before the default catches it.
 */

import type { ModelFamily } from './types.js';

interface FamilyRule {
  regex: RegExp;
  family: ModelFamily;
}

const DEFAULT_RULES: FamilyRule[] = [
  { regex: /claude-.*haiku/i, family: 'claude-haiku' },
  { regex: /claude-.*sonnet/i, family: 'claude-sonnet' },
  { regex: /claude-.*opus/i, family: 'claude-opus' },
  { regex: /gpt-4o-mini/i, family: 'gpt-4o-mini' },
  { regex: /gpt-4o/i, family: 'gpt-4o' },
  { regex: /qwen.*coder/i, family: 'qwen-coder' },
  { regex: /^stub/i, family: 'stub' },
];

const USER_RULES: FamilyRule[] = [];

/**
 * Infer a `ModelFamily` from a provider-native model ID.
 *
 * Walks user-defined rules first (so consumers can override defaults)
 * then the default table. Returns `'unknown'` when nothing matches.
 */
export function inferFamily(modelId: string): ModelFamily {
  for (const rule of USER_RULES) {
    if (rule.regex.test(modelId)) return rule.family;
  }
  for (const rule of DEFAULT_RULES) {
    if (rule.regex.test(modelId)) return rule.family;
  }
  return 'unknown';
}

/**
 * Register an additional family rule. User rules are checked before the
 * default table, so a user rule can override a default classification.
 */
export function defineFamily(regex: RegExp, family: ModelFamily): void {
  USER_RULES.push({ regex, family });
}

/** Test-only helper that wipes user-added rules. Not part of the public export surface. */
export function __resetUserFamilies(): void {
  USER_RULES.length = 0;
}
