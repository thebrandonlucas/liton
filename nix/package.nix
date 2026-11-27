# liton's release archive for this system, `zig build release`'s, fetched by
# its sha256 in RELEASE_SHA256SUMS, since Roc can't build in the Nix sandbox:
# the daemon, the command line and the UI the daemon serves.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  inherit (import ./release.nix { inherit lib; }) version archives;
  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation {
  pname = "liton";
  inherit version;
  src = fetchurl {
    url = "https://github.com/thebrandonlucas/liton/releases/download/v${version}/liton-${version}-${system}.tar.gz";
    sha256 =
      archives.${system}
        or (throw "RELEASE_SHA256SUMS records no liton ${version} archive for ${system}");
  };
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r bin share "$out"
    runHook postInstall
  '';
  meta = {
    description = "A modular, capability-driven UI for working with AI agents across daemon backends";
    homepage = "https://github.com/thebrandonlucas/liton";
    license = [
      lib.licenses.mit
      lib.licenses.asl20
    ];
    mainProgram = "liton";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
