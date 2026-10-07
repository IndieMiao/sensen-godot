/* Exact known assets replace question/nearby-type fallbacks in legacy UI.
 * Variant Icon properties must be explicit: combineAsVariants shares defaults.
 */
const LEGACY_ICON_BASE={inst,inferIcon};
const LEGACY_EXACT_ICONS={'quartz':'i-quartz','clay':'i-clay','hardwood':'i-hardwood','worm bait':'i-worm','spinner lure':'i-lure','sprinkler':'i-sprinkler','rock salt':'i-salt','rest':'i-rest','tea':'i-pot','hot tea':'i-pot','tea table':'i-pot','skills':'i-star','skills total':'i-star','farming + fishing':'i-star','plots':'i-radish','willow pond':'i-pond','bite board':'i-board','market board':'i-board','stamp desk':'i-stamp'};
inferIcon=function(item){if(item.icon&&ICON[item.icon])return item.icon;const key=String(item.title||item.name||'').toLowerCase(),exact=LEGACY_EXACT_ICONS[key];return exact&&ICON[exact]?exact:LEGACY_ICON_BASE.inferIcon(item);};
const LEGACY_STATUS_GLYPHS={Available:'i-pot',Ready:'i-check',Countdown:'i-clock',Cooling:'i-clock','Used today':'i-check',Locked:'i-lock',Insufficient:'i-energy',Full:'i-bag',New:'i-star',Request:'i-question',Deliverable:'i-check',Event:'i-star',Gift:'i-parcel',Blocked:'i-close'};
inst=function(parent,name,properties={},width){if(name.startsWith('ReferenceBadge/')){const key=LEGACY_STATUS_GLYPHS[name.slice('ReferenceBadge/'.length)];if(key&&ICON[key])properties={Icon:ICON[key].id,...properties};}return LEGACY_ICON_BASE.inst(parent,name,properties,width);};
