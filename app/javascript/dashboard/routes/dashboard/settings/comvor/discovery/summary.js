// Pure helper: builds the plain-language summary sentence for the sales
// flow, e.g. "Your bot answers product questions, checks stock, and
// prepares orders — then hands over to your team."
//
// `flow` is a resolved sales flow (stages carry display_name/on_complete).
// `t` is the i18n translate function (kept as a param so this stays pure
// and unit-testable without mounting a component).

function joinWithAnd(items, t) {
  if (items.length === 0) return '';
  if (items.length === 1) return items[0];
  if (items.length === 2) {
    return `${items[0]} ${t('COMVOR_SETTINGS.DISCOVERY.SUMMARY.AND')} ${items[1]}`;
  }
  const head = items.slice(0, -1).join(', ');
  const last = items[items.length - 1];
  return `${head}, ${t('COMVOR_SETTINGS.DISCOVERY.SUMMARY.AND')} ${last}`;
}

export function flowSummary(flow, t) {
  const stages = flow?.stages || [];
  const cutoffIndex = stages.findIndex(s => s.on_complete !== 'continue');
  const botStages =
    cutoffIndex === -1 ? stages : stages.slice(0, cutoffIndex + 1);
  const cutoffStage = cutoffIndex === -1 ? null : stages[cutoffIndex];

  const actions = botStages
    .map(s => s.display_name || s.stage_key)
    .filter(Boolean);

  if (actions.length === 0) {
    return t('COMVOR_SETTINGS.DISCOVERY.SUMMARY.NO_STAGES');
  }

  const finish =
    cutoffStage?.on_complete === 'resolve'
      ? t('COMVOR_SETTINGS.DISCOVERY.SUMMARY.FINISH_RESOLVE')
      : t('COMVOR_SETTINGS.DISCOVERY.SUMMARY.FINISH_HANDOFF');

  const actionsPhrase = joinWithAnd(actions, t);
  return t('COMVOR_SETTINGS.DISCOVERY.SUMMARY.TEMPLATE', {
    actions: actionsPhrase,
    finish,
  });
}

export default flowSummary;
