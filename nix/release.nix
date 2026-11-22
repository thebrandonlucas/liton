# liton's release: the version build.zig.zon gives, and the sha256 of each
# system's archive, from the lines of RELEASE_SHA256SUMS naming
# liton-VERSION-SYSTEM.tar.gz.
{ lib }:
let
  matches =
    pattern: text:
    lib.concatMap (
      line:
      let
        match = builtins.match pattern line;
      in
      lib.optional (match != null) match
    ) (lib.splitString "\n" text);
  version = lib.head (
    lib.head (matches " *\\.version = \"(.+)\",.*" (builtins.readFile ../build.zig.zon))
  );
in
{
  inherit version;
  archives = lib.listToAttrs (
    map (match: lib.nameValuePair (lib.elemAt match 1) (lib.elemAt match 0)) (
      matches "([0-9a-f]{64})  liton-${lib.escapeRegex version}-(.+)\\.tar\\.gz" (
        builtins.readFile ../RELEASE_SHA256SUMS
      )
    )
  );
}
