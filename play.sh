#!/usr/bin/env bash
# Prefer the discrete GPU on NVIDIA hybrid laptops; change no desktop settings.
# GRAVEFLAME_GPU=default keeps the caller's normal renderer selection.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if [[ "${GRAVEFLAME_GPU:-auto}" == auto ]] \
    && command -v nvidia-smi >/dev/null 2>&1 \
    && nvidia-smi -L >/dev/null 2>&1; then
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi

exec "${GODOT_BIN:-godot4}" --path . "$@"
