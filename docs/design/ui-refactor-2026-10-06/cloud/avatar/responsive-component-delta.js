const KIT={},LEDGER={checks:{}};const INPUT={"pageId":"481:53","masters":{"Dismiss":"483:220","Tab":"483:322","NavigationRow":"483:217"}};
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

const page=await figma.getNodeByIdAsync(INPUT.pageId);await figma.setCurrentPageAsync(page);for(const [key,id]of Object.entries(INPUT.masters))KIT[key]=await figma.getNodeByIdAsync(id);const result=await applyResponsiveLabelSizing();return {kind:'avatar-responsive-master-fix',...result};
