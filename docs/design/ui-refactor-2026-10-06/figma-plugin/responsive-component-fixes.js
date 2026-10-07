/* Verified responsive label correction. Scope is deliberately only Dismiss,
 * Tab and NavigationRow; keep all other reviewed component geometry unchanged.
 * Instance-internal text resize overrides do not persist in this MCP runtime.
 */
async function applyResponsiveLabelSizing(){
 const mutated=[];const checks=[];
 for(const key of ['Dismiss','Tab','NavigationRow']){
  const main=KIT[key];if(!main||main.type!=='COMPONENT')throw Error('Responsive master missing: '+key);
  const labels=main.findAllWithCriteria({types:['TEXT']}).filter(n=>n.name==='Label');
  if(labels.length!==1)throw Error('Expected one semantic Label in '+key);
  for(const label of labels){for(const segment of label.getStyledTextSegments(['fontName']))await figma.loadFontAsync(segment.fontName);label.layoutSizingHorizontal='FILL';label.textAutoResize='HEIGHT';mutated.push(label.id);}
  const chevron=key==='NavigationRow'?main.findAllWithCriteria({types:['TEXT']}).find(n=>n.name==='Chevron'):null;
  checks.push({key,id:main.id,labelIds:labels.map(n=>n.id),labelSizing:labels.map(n=>n.layoutSizingHorizontal),chevronFixed:chevron?chevron.layoutSizingHorizontal==='FIXED':null});
 }
 LEDGER.checks.responsiveLabels={verifiedApproach:'Set FILL on shared master Label, not instance geometry overrides',masters:checks};
 return {createdNodeIds:[],mutatedNodeIds:[...new Set(mutated)],checks:{responsiveLabels:checks}};
}
const RESPONSIVE_LABEL_LIBRARY_BASE=library;
library=async function(){await RESPONSIVE_LABEL_LIBRARY_BASE();await applyResponsiveLabelSizing();};
