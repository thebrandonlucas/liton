# Settings shared by the rig's scripts; each can be overridden from the
# environment. Sourced, not run.
rig=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Where models.sh puts the models, which git ignores.
RIG_MODELS=${RIG_MODELS:-$rig/models}
RIG_SHERPA_PORT=${RIG_SHERPA_PORT:-6006}
RIG_WHISPER_PORT=${RIG_WHISPER_PORT:-8178}
RIG_THREADS=${RIG_THREADS:-4}
