# source this first:  UEVR_PROFILE=MyGame-Win64-Shipping UEVR_PROCESS=MyGame-Win64-Shipping DBG_PREFIX=mod_ . env.sh
: "${UEVR_PROFILE:?set UEVR_PROFILE (UnrealVRMod folder name, e.g. Scorn-Win64-Shipping)}"
export UEVR_PROCESS="${UEVR_PROCESS:-$UEVR_PROFILE}"
export DBG_PREFIX="${DBG_PREFIX:-mod_}"
export UEVR_DATA="$APPDATA/UnrealVRMod/$UEVR_PROFILE/data"
export SHOTS_DIR="${SHOTS_DIR:-$PWD/shots}"
mkdir -p "$SHOTS_DIR"
export SKILL_TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
