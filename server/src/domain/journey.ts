import type { Command } from './commands.js';
import type { Content, CropId, DishId, JourneyMaterial, JourneyProjectStage } from './content.js';
import { err, ok, type Result } from './errors.js';
import type { Ctx } from './reducer.js';
import type { FarmState, JourneyState } from './state.js';

export const hasFact = (s: FarmState, fact: string): boolean => s.journey?.facts.includes(fact) ?? false;
export const canUse = (s: FarmState, capability: string, legacyChapter: number): boolean =>
  s.journey ? s.journey.unlocks.includes(capability) : s.clock.chapter_index >= legacyChapter;

export function journeyContent(s: FarmState, content: Content): Content {
  if (!s.journey) return content;
  const crops = structuredClone(content.crops);
  for (const id of ['R', 'L', 'C', 'H'] as const) Object.assign(crops.crops[id], content.journey.crops[id]);
  const recipes = structuredClone(content.recipes);
  for (const id of ['salad', 'tea'] as const) recipes.recipes[id].stall_price = content.journey.dish_prices[id];
  return { ...content, crops, recipes };
}

export function startJourney(s: FarmState, content: Content): FarmState {
  if (s.journey) return s;
  const next = structuredClone(s);
  // Project reservations are labels on owned produce, not a separate inventory.
  next.engineering.reserved = {};
  next.journey = { version: 1, facts: [], completed: [], unlocks: [], wood: 0,
    exploration: { round: 0, collected: [] }, opportunities: Object.fromEntries(
      Object.keys(content.journey.opportunities).map(id => [id, { sequence: 0, variant: 0 }])) };
  // Old grants count as paid; preserve their access without minting the reward again.
  if (s.chapters[2]?.grants_issued) next.journey.completed.push('first_harvest');
  if (s.chapters[3]?.grants_issued) next.journey.completed.push('first_meal');
  if (s.tools.row_tool || s.beds_unlocked === 4) next.journey.unlocks.push('growth', 'decorations');
  if (s.residents.bistro_owner.shared_event_done && s.xp.first_recipes.includes('salad'))
    next.journey.facts.push('shared_meal');
  return reconcileJourney(next, content);
}

export function reconcileJourney(s: FarmState, content: Content): FarmState {
  if (!s.journey) return s;
  const next = structuredClone(s);
  const j = next.journey!;
  const add = (fact: string) => { if (!j.facts.includes(fact)) j.facts.push(fact); };
  if (next.xp.first_harvest_crops.length) add('first_harvest');
  if (next.residents.nursery_keeper.first_met_day !== null) add('met_nursery');
  if (next.residents.bistro_owner.first_met_day !== null) add('met_bistro');
  if (next.decorations?.some(p => p.prop_id === 'planter')) add('planter_placed');
  for (const milestone of content.journey.milestones) {
    if (!j.completed.includes(milestone.id) && milestone.facts.every(f => j.facts.includes(f))) {
      j.completed.push(milestone.id);
      for (const [crop, qty] of Object.entries(milestone.grants)) next.inventory.seeds[crop as CropId].bound += qty ?? 0;
    }
    if (j.completed.includes(milestone.id))
      for (const capability of milestone.unlocks)
        if (!j.unlocks.includes(capability)) j.unlocks.push(capability);
  }
  if (j.completed.includes('garden')) next.nursery.stage = 'built';
  else if (hasFact(next, 'side_path') && next.nursery.stage === 'derelict') next.nursery.stage = 'cleared';
  return next;
}

export function resourceNodes(s: FarmState, content: Content) {
  return content.journey.nodes.filter(n => (n.place !== 'bistro' || canUse(s, 'bistro', 1))
    && (!n.requires || hasFact(s, n.requires))).map(n => {
    const materials: Partial<Record<JourneyMaterial, number>> = { wood: n.wood };
    if (n.place === 'courtyard') materials.stone = 1;
    if (n.place === 'bistro') materials.fiber = 1;
    const exploration = s.journey?.exploration;
    const routeId = exploration?.routes_by_place
      ? exploration.routes_by_place[n.place] ?? 'neighbourhood' : exploration?.route ?? 'neighbourhood';
    const route = content.journey.routes[routeId];
    if (route && route.place === n.place) materials[route.material] = (materials[route.material] ?? 0) + route.bonus;
    return { ...n, materials };
  });
}

export function projectStage(s: FarmState, id: string, content: Content): number {
  const project = content.journey.projects[id];
  if (!project) return 0;
  return project.stages.filter((_, index) => hasFact(s, `project_${id}_${index}`)).length;
}

function materialCount(s: FarmState, id: JourneyMaterial): number {
  return id === 'wood' ? s.journey!.wood : s.journey!.materials?.[id] ?? 0;
}

function clearDisplayPlan(j: JourneyState): void {
  if (!j.workshop?.planned) return;
  delete j.workshop.planned;
  j.workshop.sequence += 1;
}

function payStage(s: FarmState, cost: JourneyProjectStage): Result<FarmState> {
  for (const [id, qty] of Object.entries(cost.materials))
    if (materialCount(s, id as JourneyMaterial) < qty!) return err('INSUFFICIENT_ITEMS', id);
  for (const [id, qty] of Object.entries(cost.produce))
    if (s.inventory.produce[id as CropId] - (s.engineering.reserved[id as CropId] ?? 0) < qty!)
      return err('INSUFFICIENT_ITEMS', id);
  for (const [id, qty] of Object.entries(cost.dishes))
    if (s.inventory.dishes[id as DishId] < qty!) return err('INSUFFICIENT_ITEMS', id);
  for (const [id, qty] of Object.entries(cost.materials)) {
    if (id === 'wood') s.journey!.wood -= qty!;
    else s.journey!.materials![id as 'stone' | 'fiber'] -= qty!;
  }
  for (const [id, qty] of Object.entries(cost.produce)) s.inventory.produce[id as CropId] -= qty!;
  for (const [id, qty] of Object.entries(cost.dishes)) s.inventory.dishes[id as DishId] -= qty!;
  return ok(s);
}

export function applyJourney(s: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  if (cmd.type === 'start_journey') return ok(startJourney(s, ctx.content));
  if (!['collect_resource', 'next_exploration', 'journey_action', 'fulfill_opportunity', 'decline_opportunity',
    'build_journey_project', 'use_journey_facility', 'craft_journey_item', 'deliver_journey_item',
    'display_journey_item', 'plan_journey_display', 'complete_journey_story', 'track_journey_discovery', 'track_journey_project', 'track_journey_opportunity',
    'install_journey_discovery', 'harvest_journey_discovery', 'plan_journey_gathering',
    'host_journey_gathering', 'pack_journey_gathering'].includes(cmd.type)) return null;
  if (!s.journey) return err('NOT_AVAILABLE', 'Start your neighbourhood journey first');
  const next = structuredClone(s);
  const j = next.journey!;
  j.materials ??= { stone: 0, fiber: 0 };
  j.facility_uses ??= {};
  const config = ctx.content.journey;
  switch (cmd.type) {
    case 'plan_journey_gathering':
    case 'host_journey_gathering':
    case 'pack_journey_gathering': {
      if (!config.gatherings.requires.every(f => hasFact(s, f))) return err('NOT_AVAILABLE', 'Bring the neighbours together first');
      const gathering = j.gathering ??= { sequence: 0, memories: [] };
      if (!Number.isSafeInteger(cmd.sequence) || cmd.sequence !== gathering.sequence)
        return err('ALREADY_CLAIMED', 'The gathering has changed');
      const themes = config.gatherings.themes;
      const current = gathering.current ? themes[gathering.current] : undefined;
      if (cmd.type === 'pack_journey_gathering') {
        if (!current) return err('ALREADY_CLAIMED');
        const workshop = j.workshop ??= { sequence: 0, stock: {}, displays: {} };
        workshop.stock[current.item] = (workshop.stock[current.item] ?? 0) + 1;
        workshop.sequence += 1;
        delete gathering.current;
      } else {
        if (typeof cmd.theme !== 'string' || (cmd.theme !== '' && !Object.hasOwn(themes, cmd.theme)))
          return err('NOT_AVAILABLE', 'Unknown gathering');
        if (cmd.type === 'plan_journey_gathering') {
          if ((gathering.planned ?? '') === cmd.theme) return err('ALREADY_CLAIMED');
          if (cmd.theme) {
            gathering.planned = cmd.theme;
            delete j.tracked_project;
            delete j.tracked_discovery;
            delete j.tracked_opportunity;
            clearDisplayPlan(j);
          } else delete gathering.planned;
        } else {
          if (!cmd.theme || gathering.planned !== cmd.theme) return err('NOT_AVAILABLE', 'Choose this gathering first');
          const theme = themes[cmd.theme];
          const workshop = j.workshop ??= { sequence: 0, stock: {}, displays: {} };
          const reuse = current?.item === theme.item;
          if ((!reuse && !(workshop.stock[theme.item] > 0)) || next.inventory.dishes[theme.dish] < 1)
            return err('INSUFFICIENT_ITEMS', 'Bring the handmade piece and the meal');
          if (!reuse) {
            workshop.stock[theme.item] -= 1;
            if (current) workshop.stock[current.item] = (workshop.stock[current.item] ?? 0) + 1;
            workshop.sequence += 1;
          }
          next.inventory.dishes[theme.dish] -= 1;
          next.wallet += theme.coins;
          gathering.current = cmd.theme;
          delete gathering.planned;
          if (!gathering.memories.includes(cmd.theme)) gathering.memories.push(cmd.theme);
        }
      }
      gathering.sequence += 1;
      return ok(next, [{ type: 'gathering_changed', action: cmd.type, theme: gathering.current ?? '', planned: gathering.planned ?? '' }]);
    }
    case 'track_journey_project': {
      if (cmd.project === '') {
        delete j.tracked_project;
        return ok(next);
      }
      if (typeof cmd.project !== 'string' || !Object.hasOwn(config.projects, cmd.project))
        return err('NOT_AVAILABLE', 'Unknown project');
      const project = config.projects[cmd.project];
      if (!hasFact(s, project.requires) || (project.place === 'bistro' && !canUse(s, 'bistro', 1)))
        return err('NOT_AVAILABLE', 'Discover this project first');
      if (projectStage(s, cmd.project, ctx.content) === project.stages.length) return err('ALREADY_CLAIMED');
      j.tracked_project = cmd.project;
      delete j.tracked_discovery;
      delete j.tracked_opportunity;
      if (j.gathering) delete j.gathering.planned;
      clearDisplayPlan(j);
      return ok(next);
    }
    case 'track_journey_discovery':
    case 'install_journey_discovery':
    case 'harvest_journey_discovery': {
      if (cmd.type === 'track_journey_discovery' && cmd.discovery === '') {
        delete j.tracked_discovery;
        return ok(next);
      }
      if (typeof cmd.discovery !== 'string' || !Object.hasOwn(config.discoveries, cmd.discovery))
        return err('NOT_AVAILABLE', 'Unknown discovery');
      const discovery = config.discoveries[cmd.discovery];
      const fact = `discovery_${cmd.discovery}`;
      if ((discovery.place === 'bistro' && !canUse(s, 'bistro', 1))
        || !discovery.requires.every(f => hasFact(s, f))) return err('NOT_AVAILABLE', 'Discover this corner first');
      if (cmd.type === 'track_journey_discovery') {
        if (hasFact(s, fact)) return err('ALREADY_CLAIMED');
        j.tracked_discovery = cmd.discovery;
        delete j.tracked_project;
        delete j.tracked_opportunity;
        if (j.gathering) delete j.gathering.planned;
        clearDisplayPlan(j);
        return ok(next);
      }
      if (cmd.type === 'install_journey_discovery') {
        if (hasFact(s, fact)) return err('ALREADY_CLAIMED');
        const workshop = j.workshop;
        if (!Number.isSafeInteger(cmd.sequence) || cmd.sequence !== (workshop?.sequence ?? 0))
          return err('ALREADY_CLAIMED', 'Your workshop has changed');
        if (!workshop || !(workshop.stock[discovery.item] > 0)) return err('INSUFFICIENT_ITEMS', 'Bring a handmade piece');
        workshop.stock[discovery.item] -= 1;
        workshop.sequence += 1;
        j.facts.push(fact);
        if (j.tracked_discovery === cmd.discovery) delete j.tracked_discovery;
        return ok(next, [{ type: 'world_changed', fact }]);
      }
      if (!hasFact(s, fact)) return err('NOT_AVAILABLE', 'Restore this corner first');
      if (!Number.isSafeInteger(cmd.round) || cmd.round !== j.exploration.round)
        return err('NOT_AVAILABLE', 'This exploration has changed');
      if (j.exploration.collected.includes(fact)) return err('ALREADY_CLAIMED');
      if (typeof cmd.choice !== 'string' || !Object.hasOwn(discovery.choices, cmd.choice))
        return err('NOT_AVAILABLE', 'Unknown harvest');
      const choice = discovery.choices[cmd.choice];
      if (choice.requires && !canUse(s, choice.requires, 99)) return err('NOT_AVAILABLE', 'Discover this crop first');
      for (const [id, qty] of Object.entries(choice.materials)) {
        if (id === 'wood') j.wood += qty!;
        else j.materials[id as 'stone' | 'fiber'] += qty!;
      }
      for (const [id, qty] of Object.entries(choice.produce)) next.inventory.produce[id as CropId] += qty!;
      for (const [id, qty] of Object.entries(choice.seeds)) next.inventory.seeds[id as CropId].bound += qty!;
      j.exploration.collected.push(fact);
      (j.discovery_choices ??= {})[cmd.discovery] = cmd.choice;
      return ok(next, [{ type: 'discovery_harvested', discovery: cmd.discovery, choice: cmd.choice }]);
    }
    case 'collect_resource': {
      if (!Number.isSafeInteger(cmd.round) || cmd.round !== j.exploration.round) return err('NOT_AVAILABLE', 'This exploration has changed');
      const node = resourceNodes(s, ctx.content).find(n => n.id === cmd.node_id);
      if (!node) return err('NOT_AVAILABLE', 'This resource is not reachable yet');
      if (j.exploration.collected.includes(node.id)) return err('ALREADY_CLAIMED');
      const choice = cmd.choice ?? 'primary';
      if (choice !== 'primary' && choice !== 'alternate') return err('NOT_AVAILABLE', 'Unknown resource bundle');
      const alternative = node.alternative;
      if (choice === 'alternate' && (!alternative || !j.exploration.branching_places?.includes(node.place)
        || !hasFact(s, alternative.requires))) return err('NOT_AVAILABLE', 'This bundle is not available on this trail');
      const materials = choice === 'alternate' ? alternative!.materials : node.materials;
      j.exploration.collected.push(node.id);
      if (j.exploration.branching_places?.includes(node.place)) (j.exploration.choices ??= {})[node.id] = choice;
      for (const [id, qty] of Object.entries(materials)) {
        if (id === 'wood') j.wood += qty!;
        else j.materials[id as 'stone' | 'fiber'] += qty!;
      }
      return ok(next, [{ type: 'resource_collected', node_id: node.id, choice, wood: materials.wood ?? 0, materials }]);
    }
    case 'next_exploration': {
      if (!Number.isSafeInteger(cmd.round) || cmd.round !== j.exploration.round) return err('NOT_AVAILABLE', 'This exploration has changed');
      const routeId = cmd.route ?? 'neighbourhood';
      if (typeof routeId !== 'string' || !Object.hasOwn(config.routes, routeId)) return err('NOT_AVAILABLE', 'Unknown route');
      const route = config.routes[routeId];
      if (route.requires && !canUse(s, route.requires, 99)) return err('NOT_AVAILABLE', 'Discover this path first');
      const nodes = resourceNodes(s, ctx.content).filter(n => routeId === 'neighbourhood' || n.place === route.place);
      if (!nodes.length || !nodes.every(n => j.exploration.collected.includes(n.id)))
        return err('NOT_AVAILABLE', 'There are still supplies at this destination');
      // Refresh one destination while preserving other nodes and their original rewards.
      const previousRoute = j.exploration.route ?? 'neighbourhood';
      const routes = j.exploration.routes_by_place ?? { [config.routes[previousRoute].place]: previousRoute };
      const refreshed = new Set(nodes.map(n => n.id));
      if (routeId === 'neighbourhood' || route.place === 'nursery') refreshed.add('seedbeds');
      for (const [id, discovery] of Object.entries(config.discoveries))
        if (routeId === 'neighbourhood' || discovery.place === route.place) refreshed.add(`discovery_${id}`);
      const branching = new Set(j.exploration.branching_places ?? []);
      if (hasFact(s, 'workbench')) for (const node of nodes) branching.add(node.place);
      const choices = Object.fromEntries(Object.entries(j.exploration.choices ?? {}).filter(([id]) => !refreshed.has(id)));
      j.exploration = { round: j.exploration.round + 1,
        collected: j.exploration.collected.filter(id => !refreshed.has(id)), route: routeId,
        routes_by_place: routeId === 'neighbourhood' ? {} : { ...routes, [route.place]: routeId },
        ...(branching.size ? { branching_places: [...branching], choices } : {}) };
      return ok(next, [{ type: 'exploration_started', round: j.exploration.round }]);
    }
    case 'plan_journey_display': {
      const workshop = j.workshop ??= { sequence: 0, stock: {}, displays: {} };
      if (!Number.isSafeInteger(cmd.sequence) || cmd.sequence !== workshop.sequence)
        return err('ALREADY_CLAIMED', 'Your workshop has changed');
      if (typeof cmd.project !== 'string' || !Object.hasOwn(config.projects, cmd.project)
        || projectStage(s, cmd.project, ctx.content) !== config.projects[cmd.project].stages.length)
        return err('NOT_AVAILABLE', 'Finish this project first');
      if (!Number.isSafeInteger(cmd.slot) || cmd.slot < 0 || cmd.slot >= config.workshop.display_slots)
        return err('NOT_AVAILABLE', 'Unknown display position');
      if (typeof cmd.item !== 'string' || (cmd.item !== '' && !Object.hasOwn(config.workshop.recipes, cmd.item)))
        return err('NOT_AVAILABLE', 'Unknown workshop item');
      const planned = workshop.planned;
      if (!cmd.item) {
        if (!planned || planned.project !== cmd.project || planned.slot !== cmd.slot) return err('ALREADY_CLAIMED');
        delete workshop.planned;
      } else {
        const recipe = config.workshop.recipes[cmd.item];
        if (!hasFact(s, 'workbench') || !recipe.requires.every(f => hasFact(s, f)))
          return err('NOT_AVAILABLE', 'Discover this recipe first');
        if (workshop.displays[cmd.project]?.[cmd.slot]) return err('NOT_AVAILABLE', 'Choose an empty position');
        if (planned?.project === cmd.project && planned.slot === cmd.slot && planned.item === cmd.item)
          return err('ALREADY_CLAIMED');
        workshop.planned = { project: cmd.project, slot: cmd.slot, item: cmd.item };
        delete j.tracked_project;
        delete j.tracked_discovery;
        delete j.tracked_opportunity;
        if (j.gathering) delete j.gathering.planned;
      }
      workshop.sequence += 1;
      return ok(next, [{ type: 'display_planned', project: cmd.project, slot: cmd.slot, item: cmd.item }]);
    }
    case 'craft_journey_item':
    case 'deliver_journey_item':
    case 'display_journey_item': {
      const workshop = j.workshop ??= { sequence: 0, stock: {}, displays: {} };
      if (!Number.isSafeInteger(cmd.sequence) || cmd.sequence !== workshop.sequence)
        return err('ALREADY_CLAIMED', 'Your workshop has changed');
      if (typeof cmd.item !== 'string' || (cmd.item !== '' && !Object.hasOwn(config.workshop.recipes, cmd.item)))
        return err('NOT_AVAILABLE', 'Unknown workshop item');
      const recipe = config.workshop.recipes[cmd.item];
      if (cmd.type === 'craft_journey_item') {
        if (!recipe || !hasFact(s, 'workbench') || !recipe.requires.every(f => hasFact(s, f)))
          return err('NOT_AVAILABLE', 'Discover this recipe first');
        const paid = payStage(next, recipe);
        if (!paid.ok) return paid;
        workshop.stock[cmd.item] = (workshop.stock[cmd.item] ?? 0) + 1;
        if (!hasFact(next, `crafted_${cmd.item}`)) j.facts.push(`crafted_${cmd.item}`);
      } else if (cmd.type === 'deliver_journey_item') {
        if (!recipe || !(workshop.stock[cmd.item] > 0)) return err('INSUFFICIENT_ITEMS', 'Make this piece first');
        workshop.stock[cmd.item] -= 1;
        next.wallet += recipe.coins;
      } else {
        if (typeof cmd.project !== 'string' || !Object.hasOwn(config.projects, cmd.project)
          || projectStage(s, cmd.project, ctx.content) !== config.projects[cmd.project].stages.length)
          return err('NOT_AVAILABLE', 'Finish this project first');
        if (!Number.isSafeInteger(cmd.slot) || cmd.slot < 0 || cmd.slot >= config.workshop.display_slots)
          return err('NOT_AVAILABLE', 'Unknown display position');
        const display = workshop.displays[cmd.project] ??= Array<string>(config.workshop.display_slots).fill('');
        const previous = display[cmd.slot];
        if (previous === cmd.item) return err('ALREADY_CLAIMED');
        if (cmd.item && !(workshop.stock[cmd.item] > 0)) return err('INSUFFICIENT_ITEMS', 'Make this piece first');
        if (cmd.item) workshop.stock[cmd.item] -= 1;
        if (previous) workshop.stock[previous] = (workshop.stock[previous] ?? 0) + 1;
        display[cmd.slot] = cmd.item;
        if (cmd.item && workshop.planned?.project === cmd.project && workshop.planned.slot === cmd.slot)
          delete workshop.planned;
        if (cmd.item && !hasFact(next, 'workshop_displayed')) j.facts.push('workshop_displayed');
      }
      workshop.sequence += 1;
      return ok(next, [{ type: 'workshop_changed', item: cmd.item, action: cmd.type }]);
    }
    case 'complete_journey_story': {
      if (typeof cmd.resident_id !== 'string' || !Object.hasOwn(config.stories, cmd.resident_id))
        return err('NOT_AVAILABLE', 'Unknown resident');
      const story = config.stories[cmd.resident_id].find(entry => entry.id === cmd.story);
      if (!story || !story.requires.every(f => hasFact(s, f))) return err('NOT_AVAILABLE', 'This moment is not ready yet');
      const fact = `story_${story.id}`;
      if (hasFact(s, fact)) return err('ALREADY_CLAIMED');
      const paid = payStage(next, story);
      if (!paid.ok) return paid;
      const resident = next.residents[cmd.resident_id];
      resident.first_met_day ??= next.clock.player_day_id;
      resident.request_done = true;
      resident.shared_event_done ||= story.shared;
      resident.points += story.points;
      j.facts.push(fact);
      return ok(next, [{ type: 'relationship', amount: story.points, reason: fact }]);
    }
    case 'build_journey_project': {
      if (typeof cmd.project !== 'string' || !Object.hasOwn(config.projects, cmd.project)) return err('NOT_AVAILABLE');
      const project = config.projects[cmd.project];
      const index = projectStage(s, cmd.project, ctx.content);
      if (!Number.isSafeInteger(cmd.stage) || cmd.stage !== index || index >= project.stages.length)
        return err('ALREADY_CLAIMED', 'This project has changed');
      if (!hasFact(s, project.requires)) return err('NOT_AVAILABLE', 'Discover this project first');
      const paid = payStage(next, project.stages[index]);
      if (!paid.ok) return paid;
      const fact = `project_${cmd.project}_${index}`;
      j.facts.push(fact);
      if (index + 1 < project.stages.length && !j.tracked_project && !j.tracked_discovery && !j.tracked_opportunity
        && !j.workshop?.planned && !j.gathering?.planned)
        j.tracked_project = cmd.project;
      if (index + 1 === project.stages.length && j.tracked_project === cmd.project) delete j.tracked_project;
      return ok(next, [{ type: 'world_changed', fact, project: cmd.project, stage: index + 1 }]);
    }
    case 'use_journey_facility': {
      if (typeof cmd.project !== 'string' || !Object.hasOwn(config.projects, cmd.project)) return err('NOT_AVAILABLE');
      const project = config.projects[cmd.project];
      if (projectStage(s, cmd.project, ctx.content) !== project.stages.length) return err('NOT_AVAILABLE', 'Finish the project first');
      if (!Number.isSafeInteger(cmd.sequence) || cmd.sequence !== (j.facility_uses[cmd.project] ?? 0))
        return err('ALREADY_CLAIMED', 'This activity has changed');
      if (cmd.project === 'seedbeds') {
        const choices: Record<string, CropId> = { lettuce: 'L', carrots: 'C', flowers: 'H' };
        if (typeof cmd.choice !== 'string' || !Object.hasOwn(choices, cmd.choice)) return err('NOT_AVAILABLE');
        const crop = choices[cmd.choice];
        if (crop !== 'L' && !canUse(s, `crop_${crop}`, 99)) return err('NOT_AVAILABLE');
        if (j.exploration.collected.includes('seedbeds')) return err('ALREADY_CLAIMED', 'Start another exploration for a fresh basket');
        j.exploration.collected.push('seedbeds');
        if (crop === 'H') next.inventory.produce.H += 1;
        else next.inventory.seeds[crop].bound += 2;
      } else if (cmd.project === 'terrace') {
        if (cmd.choice !== 'salad' && cmd.choice !== 'tea') return err('NOT_AVAILABLE');
        if (next.inventory.dishes[cmd.choice] < 1) return err('INSUFFICIENT_ITEMS', cmd.choice);
        next.inventory.dishes[cmd.choice] -= 1;
        next.wallet += cmd.choice === 'salad' ? 30 : 24;
      } else if (cmd.project === 'waystation') {
        if (cmd.choice !== 'stone' && cmd.choice !== 'fiber') return err('NOT_AVAILABLE');
        if (j.wood < 2) return err('INSUFFICIENT_ITEMS', 'Wood');
        j.wood -= 2;
        j.materials[cmd.choice] += 2;
      } else return err('NOT_AVAILABLE');
      j.facility_uses[cmd.project] = cmd.sequence + 1;
      return ok(next, [{ type: 'facility_used', project: cmd.project, choice: cmd.choice, sequence: cmd.sequence }]);
    }
    case 'journey_action': {
      const action = cmd.action;
      const facts = { repair_workbench: 'workbench', craft_planter: 'planter_crafted',
        clear_side_path: 'side_path', share_meal: 'shared_meal', plant_planter: 'planter_planted' };
      if (typeof action !== 'string' || !Object.hasOwn(facts, action)) return err('NOT_AVAILABLE', 'Unknown activity');
      const fact = facts[action];
      if (hasFact(s, fact)) return err('ALREADY_CLAIMED');
      if (action === 'craft_planter' && !hasFact(s, 'workbench')) return err('NOT_AVAILABLE', 'Repair the workbench first');
      if (action === 'clear_side_path' && (!hasFact(s, 'planter_crafted') || !hasFact(s, 'shared_meal')))
        return err('NOT_AVAILABLE', 'Make a planter and share your first meal');
      if (action === 'share_meal') {
        if (!canUse(s, 'kitchen', 3) || !hasFact(s, 'met_bistro') || !s.xp.first_recipes.includes('salad'))
          return err('NOT_AVAILABLE', 'Meet the host and prepare a salad');
        if (next.inventory.dishes.salad < 1) return err('INSUFFICIENT_ITEMS', 'Bring a salad to the table');
        next.inventory.dishes.salad -= 1;
        next.residents.bistro_owner.shared_event_done = true;
        next.residents.bistro_owner.points += ctx.content.relationships.points.shared_event.points;
      } else if (action === 'plant_planter') {
        if (!hasFact(s, 'planter_placed') || !next.decorations?.some(p => p.prop_id === 'planter'))
          return err('NOT_AVAILABLE', 'Place your planter in the courtyard');
        if (next.inventory.produce.H - (next.engineering.reserved.H ?? 0) < 1) return err('INSUFFICIENT_ITEMS', 'Harvest a chamomile flower');
        next.inventory.produce.H -= 1;
      } else {
        const cost = config.costs[action];
        if (j.wood < cost) return err('INSUFFICIENT_ITEMS', `Gather ${cost} wood`);
        j.wood -= cost;
      }
      j.facts.push(fact);
      return ok(next, [{ type: 'world_changed', fact }]);
    }
    case 'track_journey_opportunity': {
      if (typeof cmd.slot !== 'string' || !Object.hasOwn(j.opportunities, cmd.slot)
        || !Object.hasOwn(config.opportunities, cmd.slot) || typeof cmd.tracking !== 'boolean')
        return err('NOT_AVAILABLE', 'Unknown request');
      const slot = j.opportunities[cmd.slot];
      if (!Number.isSafeInteger(cmd.sequence) || cmd.sequence !== slot.sequence) return err('REQUEST_DONE');
      const tracked = j.tracked_opportunity;
      if (!cmd.tracking) {
        if (tracked?.slot !== cmd.slot || tracked.sequence !== cmd.sequence) return err('REQUEST_DONE');
        delete j.tracked_opportunity;
      } else {
        const offer = config.opportunities[cmd.slot][slot.variant];
        if (!offer || (offer.requires && !canUse(s, offer.requires, 99))
          || (cmd.slot === 'bistro' && !hasFact(s, 'shared_meal')))
          return err('NOT_AVAILABLE', 'Discover this request first');
        if (tracked?.slot === cmd.slot && tracked.sequence === cmd.sequence) return err('ALREADY_CLAIMED');
        j.tracked_opportunity = { slot: cmd.slot, sequence: cmd.sequence };
        delete j.tracked_project;
        delete j.tracked_discovery;
        if (j.gathering) delete j.gathering.planned;
        clearDisplayPlan(j);
      }
      return ok(next);
    }
    case 'decline_opportunity':
    case 'fulfill_opportunity': {
      if (typeof cmd.slot !== 'string' || !Object.hasOwn(j.opportunities, cmd.slot)) return err('NOT_AVAILABLE');
      const slot = j.opportunities[cmd.slot];
      if (!Number.isSafeInteger(cmd.sequence) || cmd.sequence !== slot.sequence) return err('REQUEST_DONE');
      if (cmd.slot === 'bistro' && !canUse(s, 'bistro', 1)) return err('NOT_AVAILABLE');
      const variants = config.opportunities[cmd.slot];
      const offer = variants[slot.variant];
      if (!offer || (offer.requires && !canUse(s, offer.requires, 99))) return err('NOT_AVAILABLE');
      if (cmd.type === 'fulfill_opportunity') {
        if (j.wood < offer.wood) return err('INSUFFICIENT_ITEMS', 'Wood');
        for (const [id, qty] of Object.entries(offer.produce))
          if (next.inventory.produce[id as CropId] - (next.engineering.reserved[id as CropId] ?? 0) < (qty ?? 0)) return err('INSUFFICIENT_ITEMS', id);
        for (const [id, qty] of Object.entries(offer.dishes))
          if (next.inventory.dishes[id as DishId] < (qty ?? 0)) return err('INSUFFICIENT_ITEMS', id);
        j.wood -= offer.wood;
        for (const [id, qty] of Object.entries(offer.produce)) next.inventory.produce[id as CropId] -= qty ?? 0;
        for (const [id, qty] of Object.entries(offer.dishes)) next.inventory.dishes[id as DishId] -= qty ?? 0;
        next.wallet += offer.coins;
        j.contributions ??= {};
        j.contributions[offer.effect] = Math.min(config.contribution_steps, (j.contributions[offer.effect] ?? 0) + 1);
      }
      if (j.tracked_opportunity?.slot === cmd.slot && j.tracked_opportunity.sequence === cmd.sequence)
        delete j.tracked_opportunity;
      slot.sequence += 1;
      // Freeze the next visible offer; repeated requests cannot select a different reward.
      for (let offset = 1; offset <= variants.length; offset++) {
        const index = (slot.variant + offset) % variants.length;
        if (!variants[index].requires || canUse(next, variants[index].requires!, 99)) { slot.variant = index; break; }
      }
      return ok(next, [{ type: cmd.type === 'fulfill_opportunity' ? 'opportunity_completed' : 'opportunity_declined',
        slot: cmd.slot, sequence: cmd.sequence, coins: cmd.type === 'fulfill_opportunity' ? offer.coins : 0 }]);
    }
  }
  return err('NOT_AVAILABLE');
}
