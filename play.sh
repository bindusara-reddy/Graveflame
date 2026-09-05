#!/usr/bin/env bash
# Prefer the discrete GPU on NVIDIA hybrid laptops; change no desktop settings.
# GRAVEFLAME_GPU=default keeps the caller's normal renderer selection.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
presentation_args=()

if [[ "${GRAVEFLAME_GPU:-auto}" == auto ]] \
    && command -v nvidia-smi >/dev/null 2>&1 \
    && nvidia-smi -L >/dev/null 2>&1; then
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    # Hybrid NVIDIA presentation can stall on compositor V-Sync waits.
    # Keep this process-local and bound rendering rather than running uncapped.
    if [[ "${GRAVEFLAME_VSYNC:-auto}" != default ]]; then
        presentation_args=(--disable-vsync --max-fps 120)
    fi
fi

# A clean checkout ships no .godot/ cache, and class_name lookups (Content,
# Player, RunModel, ...) fail at boot without it. Import once, headless and
# without the caller's arguments, then refuse to start if the import broke.
class_cache=".godot/global_script_class_cache.cfg"
if [[ ! -f "$class_cache" ]]; then
    echo "graveflame: first launch, importing project resources..." >&2
    import_log="$(mktemp -t graveflame-import.XXXXXX)"
    import_status=0
    "${GODOT_BIN:-godot4}" --path . --headless --import >"$import_log" 2>&1 || import_status=$?
    if [[ "$import_status" -ne 0 ]] || grep -q "SCRIPT ERROR" "$import_log" || [[ ! -f "$class_cache" ]]; then
        echo "graveflame: project import failed (exit $import_status); engine output follows" >&2
        cat "$import_log" >&2
        rm -f "$import_log"
        exit 1
    fi
    rm -f "$import_log"
fi

exec "${GODOT_BIN:-godot4}" --path . "${presentation_args[@]}" "$@"
