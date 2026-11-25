#!/bin/bash
set -euo pipefail

fps="${1:-}"
case "$fps" in
  30 | 60) shift ;;
  *)
    echo "Invalid FPS: $fps (expected 30 or 60)" >&2
    exit 2
    ;;
esac

# Defense-in-depth: only forward allowlisted omarchy-capture-screenrecording flags.
validated_args=()
for arg in "$@"; do
  case "$arg" in
    --fullscreen | --with-desktop-audio | --with-microphone-audio | --with-webcam | \
    --webcam-size=small | --webcam-size=medium | --webcam-size=large | \
    --resolution=854x480 | --resolution=1280x720 | --resolution=1920x1080)
      validated_args+=("$arg")
      ;;
    *)
      echo "Disallowed argument: $arg" >&2
      exit 2
      ;;
  esac
done

script_dir=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd -P)
plugin_dir=$(CDPATH='' cd -P -- "$script_dir/.." && pwd -P)

if [[ $fps != "60" ]]; then
  shim_path=""
  if command -v gpu-screen-recorder >/dev/null 2>&1; then
    shim_path="${shim_path:+$shim_path:}$plugin_dir/shims/gsr"
  fi
  if command -v wf-recorder >/dev/null 2>&1; then
    shim_path="${shim_path:+$shim_path:}$plugin_dir/shims/wfr"
  fi
  if [[ -n $shim_path ]]; then
    export PATH="$shim_path:$PATH"
    export CAPTURE_TOOLKIT_FPS="$fps"
  fi
fi

exec omarchy-capture-screenrecording "${validated_args[@]}"
