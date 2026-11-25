#!/usr/bin/env bash
# Static and behavioural checks for the scoped-check inputs of
# .github/workflows/cardigan-check.yml (merge_tier, scope, affected_paths, skip_checks).
#
# 1. Static: the dispatch inputs, the host's step contract (names, order, count) and that
#    inputs reach "Verify candidate" only through env.
# 2. Behaviour: runs the real "Verify candidate" script, extracted from the workflow, in a
#    throwaway git repository with missing, valid, invalid and injection-style inputs and
#    compares the step outputs. Injection cases also check that no marker file appears and
#    that GITHUB_OUTPUT holds exactly the five normalized keys.
#
# Needs bash, git and python3 with PyYAML. Does not touch the repository or the network.
set -euo pipefail
src=$(cd "$(dirname "$0")/../.." && pwd)
workflow=$src/.github/workflows/cardigan-check.yml
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

python3 -c 'import yaml' 2>/dev/null || { echo "FAIL: python3 with PyYAML is required" >&2; exit 1; }

# ---- 1. static checks; also writes the extracted script and the step conditions ----
python3 - "$workflow" "$root" <<'PY'
import pathlib, re, sys, yaml

workflow, root = sys.argv[1], pathlib.Path(sys.argv[2])
doc = yaml.safe_load(pathlib.Path(workflow).read_text())
on = doc.get('on', doc.get(True))  # PyYAML reads the bare key `on` as True
inputs = on['workflow_dispatch']['inputs']
fail = []

for name in ('sha', 'tree', 'card', 'delivery', 'attempt', 'kind'):
    spec = inputs.get(name) or {}
    if spec.get('required') is not True or spec.get('type') != 'string':
        fail.append(f'input {name}: must stay required string, got {spec}')
for name, default in (('merge_tier', 'single'), ('scope', 'full'), ('affected_paths', ''), ('skip_checks', '')):
    spec = inputs.get(name)
    if spec is None:
        fail.append(f'input {name}: missing')
        continue
    # string, not choice: an unknown value must still dispatch and fall back to full.
    if spec.get('required') is not False or spec.get('type') != 'string' or spec.get('default') != default:
        fail.append(f'input {name}: want required=false type=string default={default!r}, got {spec}')
if len(inputs) != 10:
    fail.append(f'expected 10 inputs, got {sorted(inputs)}')

jobs = doc['jobs']
if list(jobs) != ['check']:
    fail.append(f'expected the single job "check", got {list(jobs)}')
job = jobs['check']
if not job.get('services'):
    fail.append('job lost its services ("Initialize containers" step)')
steps = job['steps']
label = lambda s: s.get('name') or s['uses'].split('@')[0]
contract = ['actions/checkout', 'Verify candidate', 'actions/setup-node', 'pnpm/action-setup', 'install',
            'build', 'test', 'lint', 'dynamic_farm', 'deps', 'e2e']
got = [label(s) for s in steps]
if got != contract:
    fail.append(f'step contract changed:\n  want {contract}\n  got  {got}')
    print('\n'.join('FAIL: ' + f for f in fail), file=sys.stderr)
    sys.exit(1)

by = {label(s): s for s in steps}
verify = by['Verify candidate']
if verify.get('id') != 'verify':
    fail.append('Verify candidate needs id: verify')
for key, expr in (('MERGE_TIER', 'inputs.merge_tier'), ('CHECK_SCOPE', 'inputs.scope'),
                  ('AFFECTED_PATHS', 'inputs.affected_paths'), ('SKIP_CHECKS', 'inputs.skip_checks')):
    if verify['env'].get(key) != '${{ ' + expr + ' }}':
        fail.append(f'Verify candidate env {key} must be ${{{{ {expr} }}}}')
# No step may splice an expression into a shell script.
for s in steps:
    if '${{' in s.get('run', ''):
        fail.append(f'step {label(s)}: run script contains ${{{{ }}}}; pass values through env')
    if re.search(r'inputs\.(merge_tier|scope|affected_paths|skip_checks)', str(s.get('with', ''))):
        fail.append(f'step {label(s)}: scoped inputs must not reach "with"')
# Only test and e2e depend on the scope; everything else keeps its previous condition.
want_if = {
    'test': "${{ steps.verify.outputs.skip_test != 'true' }}",
    'lint': "${{ !cancelled() && steps.build.outcome == 'success' }}",
    'dynamic_farm': "${{ !cancelled() && steps.build.outcome == 'success' }}",
    'deps': "${{ !cancelled() && steps.install.outcome == 'success' }}",
    'e2e': "${{ !cancelled() && steps.deps.outcome == 'success' && steps.verify.outputs.skip_e2e != 'true' }}",
}
for name, cond in want_if.items():
    if by[name].get('if') != cond:
        fail.append(f'step {name}: if is {by[name].get("if")!r}, want {cond!r}')
for name in ('install', 'build'):
    if 'if' in by[name]:
        fail.append(f'step {name}: must not gain a condition')

if fail:
    print('\n'.join('FAIL: ' + f for f in fail), file=sys.stderr)
    sys.exit(1)
(root / 'verify.sh').write_text(verify['run'])
(root / 'lc_all').write_text(verify['env'].get('LC_ALL', ''))
print(f'static: 10 inputs, {len(steps)} steps in contract order, inputs only via env')
PY

# ---- 2. behaviour of the extracted "Verify candidate" script ----
repo=$root/repo
git init -q "$repo"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m candidate
sha=$(git -C "$repo" rev-parse HEAD)
marker=$root/pwned
lc_all=$(cat "$root/lc_all")
pass=0

# run <expected outputs> <env assignments...>
#   unset NAME in the assignments removes the variable (an input GitHub did not pass).
run() {
  local want=$1 rc=0 envs=(CANDIDATE_SHA="$sha" CHECK_KIND=merge_check MERGE_TIER=single CHECK_SCOPE=full
                          AFFECTED_PATHS= SKIP_CHECKS=) unsets=()
  shift
  while (($#)); do
    if [[ $1 == unset ]]; then unsets+=(-u "$2"); shift 2; else envs+=("$1"); shift; fi
  done
  : >"$root/out" && : >"$root/summary"
  (cd "$repo" && env "${unsets[@]}" "${envs[@]}" LC_ALL="$lc_all" GITHUB_OUTPUT="$root/out" \
    GITHUB_STEP_SUMMARY="$root/summary" bash -eo pipefail "$root/verify.sh") >"$root/log" 2>&1 || rc=$?
  local got
  got=$(paste -sd' ' "$root/out")
  if [[ $rc != 0 || $got != "$want" || -e $marker || $(wc -l <"$root/out") != 5 ]]; then
    cat "$root/log" >&2
    echo "FAIL: rc=$rc marker=$([[ -e $marker ]] && echo yes || echo no) for: ${envs[*]:6} ${unsets[*]}" >&2
    echo "  want: $want" >&2
    echo "  got:  $got" >&2
    exit 1
  fi
  pass=$((pass + 1))
}
full() { echo "merge_tier=$1 scope=full affected_paths= skip_test=false skip_e2e=false"; }
FULL=$(full single)

# Missing / default inputs: full.
run "$FULL"
run "$FULL" unset MERGE_TIER unset CHECK_SCOPE unset AFFECTED_PATHS unset SKIP_CHECKS
run "$FULL" MERGE_TIER= CHECK_SCOPE=affected AFFECTED_PATHS=packages/blueprint-core
run "$FULL" CHECK_SCOPE= SKIP_CHECKS=test

# Valid scopes.
run "merge_tier=single scope=affected affected_paths=packages/blueprint-core skip_test=false skip_e2e=false" \
  CHECK_SCOPE=affected AFFECTED_PATHS=packages/blueprint-core
run "merge_tier=card scope=affected affected_paths=packages/a apps/b-2 skip_test=false skip_e2e=false" \
  MERGE_TIER=card CHECK_SCOPE=affected "AFFECTED_PATHS=packages/a apps/b-2"
run "merge_tier=single scope=docs_only affected_paths= skip_test=true skip_e2e=false" CHECK_SCOPE=docs_only SKIP_CHECKS=test
run "merge_tier=single scope=docs_only affected_paths= skip_test=false skip_e2e=true" CHECK_SCOPE=docs_only SKIP_CHECKS=e2e
run "merge_tier=card scope=docs_only affected_paths= skip_test=true skip_e2e=true" \
  MERGE_TIER=card CHECK_SCOPE=docs_only SKIP_CHECKS=test,e2e
# Card tier alone does not skip e2e.
run "$(full card)" MERGE_TIER=card
# 64 paths is the limit.
paths64=$(printf 'packages/p%s ' $(seq 1 64)); paths64=${paths64% }
run "merge_tier=single scope=affected affected_paths=$paths64 skip_test=false skip_e2e=false" \
  CHECK_SCOPE=affected "AFFECTED_PATHS=$paths64"

# Batch always runs the full check, whatever else is passed.
run "$(full batch)" MERGE_TIER=batch CHECK_SCOPE=docs_only SKIP_CHECKS=test,e2e
run "$(full batch)" MERGE_TIER=batch CHECK_SCOPE=affected AFFECTED_PATHS=packages/blueprint-core

# Unknown or invalid values and combinations: full.
for tier in Single BATCH cards 'single ' ' single' 'card,batch'; do
  run "$FULL" "MERGE_TIER=$tier" CHECK_SCOPE=docs_only SKIP_CHECKS=test
done
for scope in Full affected_only docs DOCS_ONLY 'docs_only ' none; do
  run "$FULL" "CHECK_SCOPE=$scope" SKIP_CHECKS=test AFFECTED_PATHS=packages/a
done
run "$FULL" CHECK_SCOPE=affected                                     # no paths
run "$FULL" CHECK_SCOPE=affected AFFECTED_PATHS=packages/a SKIP_CHECKS=test
run "$FULL" CHECK_SCOPE=docs_only                                    # nothing to skip
run "$FULL" CHECK_SCOPE=docs_only SKIP_CHECKS=lint
run "$FULL" CHECK_SCOPE=docs_only SKIP_CHECKS=e2e,test
run "$FULL" CHECK_SCOPE=docs_only SKIP_CHECKS=test,e2e,deps
run "$FULL" CHECK_SCOPE=docs_only "SKIP_CHECKS=test, e2e"
run "$FULL" CHECK_SCOPE=docs_only SKIP_CHECKS=test AFFECTED_PATHS=packages/a
run "$FULL" CHECK_SCOPE=full SKIP_CHECKS=test,e2e
for bad in server tools/geo_blueprint packages/Blueprint packages/a/b packages/ apps 'packages/a  packages/b' \
           ' packages/a' 'packages/a ' packages/a_b packages/../x 'packages/a,packages/b' packages/é \
           "$(printf 'packages/a\tpackages/b')"; do
  run "$FULL" CHECK_SCOPE=affected "AFFECTED_PATHS=$bad"
done
paths65="$paths64 packages/p65"
run "$FULL" CHECK_SCOPE=affected "AFFECTED_PATHS=$paths65"
long="packages/$(printf 'a%.0s' $(seq 1 4100))"
run "$FULL" CHECK_SCOPE=affected "AFFECTED_PATHS=$long"

# Injection-style values: never executed, never leak into the outputs, give full.
inj=(
  "packages/a; touch $marker"
  "packages/a && touch $marker"
  "\$(touch $marker)"
  "\`touch $marker\`"
  "packages/a\$(touch $marker)"
  "\${IFS}touch\${IFS}$marker"
  "$(printf 'packages/a\nskip_test=true')"
  "$(printf 'packages/a\nscope=docs_only\nskip_e2e=true')"
  "$(printf 'packages/a\r\nskip_test=true')"
  "x' ; touch $marker ; '"
  "x\" ; touch $marker ; \""
  "\${{ inputs.sha }}"
)
for v in "${inj[@]}"; do
  run "$FULL" CHECK_SCOPE=affected "AFFECTED_PATHS=$v"
  run "$FULL" CHECK_SCOPE=docs_only "SKIP_CHECKS=$v"
  run "$FULL" "CHECK_SCOPE=$v" SKIP_CHECKS=test
  run "$FULL" "MERGE_TIER=$v" CHECK_SCOPE=docs_only SKIP_CHECKS=test
done
run "$FULL" CHECK_SCOPE=docs_only "SKIP_CHECKS=$(printf 'test\nskip_e2e=true')"
run "$FULL" "MERGE_TIER=$(printf 'single\nscope=docs_only')" CHECK_SCOPE=docs_only SKIP_CHECKS=test

# The existing candidate and kind checks still fail the step.
for bad in "CANDIDATE_SHA=0000000000000000000000000000000000000000" CHECK_KIND=deploy "CHECK_KIND=merge_check;x"; do
  rc=0
  (cd "$repo" && env CANDIDATE_SHA="$sha" CHECK_KIND=merge_check "$bad" GITHUB_OUTPUT="$root/out" \
    GITHUB_STEP_SUMMARY="$root/summary" bash -eo pipefail "$root/verify.sh") >/dev/null 2>&1 || rc=$?
  [[ $rc != 0 ]] || { echo "FAIL: $bad was accepted" >&2; exit 1; }
  pass=$((pass + 1))
done

echo "behaviour: $pass cases passed"
