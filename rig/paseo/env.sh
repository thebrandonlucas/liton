# Settings shared by the rig's scripts; each can be overridden from the
# environment. Sourced, not run. Without Node on PATH, the script that
# sources this runs again with nixpkgs' Node.
command -v node >/dev/null || exec nix shell nixpkgs#nodejs -c "$0" "$@"
# Forget any Paseo settings this shell inherited, such as those Paseo gives
# the agents it runs: they would point the rig at another daemon or agent.
for name in $(compgen -e | grep '^PASEO_'); do unset "$name"; done
rig=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The throwaway home: HOME and PASEO_HOME both point here, so the daemon and
# its agents read no real credentials or history. `rm -rf home` resets it.
RIG_HOME=${RIG_HOME:-$rig/home}
RIG_PORT=${RIG_PORT:-16767}
RIG_PASSWORD=${RIG_PASSWORD:-liton-rig-password}
RIG_RELAY_PORT=${RIG_RELAY_PORT:-18787}
