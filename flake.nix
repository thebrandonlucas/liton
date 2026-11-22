# liton's release, for `nix run github:thebrandonlucas/liton` and a NixOS
# machine's daemon: nix/package.nix fetches the archive `zig build release`
# makes for each Linux system RELEASE_SHA256SUMS records one of, for the
# version build.zig.zon gives. liton's own development environment is
# Kaifile.roc.
{
  description = "A modular, capability-driven UI for working with AI agents across daemon backends";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      inherit (import ./nix/release.nix { inherit lib; }) archives;
    in
    {
      packages = lib.mapAttrs (
        system: _:
        let
          liton = nixpkgs.legacyPackages.${system}.callPackage ./nix/package.nix { };
        in
        {
          inherit liton;
          default = liton;
        }
      ) archives;

      apps = lib.mapAttrs (system: _: {
        default = {
          type = "app";
          program = lib.getExe self.packages.${system}.default;
          meta.description = "Run liton's command line";
        };
      }) archives;

      # services.liton, liton's daemon as a system service. Kai imports it
      # with InputModules("liton", ["nix/module.nix"]).
      nixosModules = {
        liton = ./nix/module.nix;
        default = self.nixosModules.liton;
      };
    };
}
