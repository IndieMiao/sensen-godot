# Device serial for the Android scripts (C-212, C-216). Source this file, then e.g.
#   serial=$(run_serial JOURNEY_SERIAL DEV); serial=${serial:-emulator-5560}
# run_serial prints the first set variable among its arguments, else the Run's own device (ANDROID_SERIAL, then
# CARDIGAN_EMULATOR_SERIAL, then CARDIGAN_DEVICE_SERIAL), else nothing. When the host gave this Run a device
# (CARDIGAN_EMULATOR_SERIAL or CARDIGAN_DEVICE_SERIAL is set), a variable naming any other device is skipped with a
# warning: a JOURNEY_SERIAL or DEV left in the login environment must not move the Run to a device it does not hold.
# Command-line serials are not checked. Same rule as tools/dev/run_serial.mjs.
run_serial() {
    local name value
    for name in "$@"; do
        value=${!name:-}
        [[ -n $value ]] || continue
        if [[ -z ${CARDIGAN_EMULATOR_SERIAL:-}${CARDIGAN_DEVICE_SERIAL:-} || $value == "${ANDROID_SERIAL:-}" ||
              $value == "${CARDIGAN_EMULATOR_SERIAL:-}" || $value == "${CARDIGAN_DEVICE_SERIAL:-}" ]]; then
            printf '%s\n' "$value"; return
        fi
        printf '%s=%s is not a device of this Run; ignoring it.\n' "$name" "$value" >&2
    done
    printf '%s\n' "${ANDROID_SERIAL:-${CARDIGAN_EMULATOR_SERIAL:-${CARDIGAN_DEVICE_SERIAL:-}}}"
}
