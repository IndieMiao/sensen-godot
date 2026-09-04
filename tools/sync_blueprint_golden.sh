#!/usr/bin/env bash
# golden corpus 的单一来源是 packages/blueprint-core/golden/corpus.json；Godot 读不到
# res:// 之外的路径，所以拷一份到 tests/fixtures/。改了那边就跑这个脚本。
set -e
cd "$(dirname "$0")/.."
cp packages/blueprint-core/golden/corpus.json tests/fixtures/blueprint_golden_corpus.json
echo "synced -> tests/fixtures/blueprint_golden_corpus.json"
