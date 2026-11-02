export * from './types';
export * from './constants';
export { haversine, bearing, destination, headingDelta } from './geo';
export { scoreTrip, computeXp, sortBySeverity } from './score';
export { buildFeedback, roastEvent, formatDuration, formatSaved } from './roast';
export { TEMPLATES } from './roast/templates';
export type { TemplateKey, TemplateLibrary } from './roast/templates';
export { buildSyntheticTrip, cleanCommute, messyCommute } from './synthetic';
export type { LegSpec, SyntheticSpec } from './synthetic';
