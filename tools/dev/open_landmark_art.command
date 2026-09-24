#!/bin/zsh
set -eu
cd "${0:A:h}/../.."
godot --headless --path . --script tools/dev/prepare_landmark_preview.gd > /tmp/sensen-landmark-prepare.log 2>&1
preview_folder="output/griffith-rebuild-2026-09-23/project"
preset_file="$preview_folder/export_presets.cfg"
preset_backup="$preview_folder/export_presets.android-qa.cfg"
mv "$preset_file" "$preset_backup"
trap 'mv "$preset_backup" "$preset_file"' EXIT
godot --headless --path "$preview_folder" --editor --import > /tmp/sensen-landmark-import.log 2>&1
mv "$preset_backup" "$preset_file"
trap - EXIT
exec godot --path "$preview_folder" --resolution 480x900
