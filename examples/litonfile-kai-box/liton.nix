# A Kai box's liton: the daemon, with the setup Litonfile.roc evaluates to,
# behind Caddy at the box's name on the client's tailnet, which gives the
# browser HTTPS and is the site the box's passkeys are for (rpId, by
# default the first of allowedHosts). Once deployed, `liton pair` on the
# box prints the owner's link, which makes their passkey. The box's Kaifile imports it beside the daemon's module:
#
#   Input("liton", "github:thebrandonlucas/liton"),
#   ...
#   Machine("box", [..., InputModules("liton", ["nix/module.nix"]), Modules(["liton.nix"])])
{ ... }:
let
  name = "box.example.ts.net";
in
{
  services.liton = {
    enable = true;
    allowedHosts = [ name ];
    rpId = name;
    setupFile = ./liton.setup.json;
    # Rooms are the box's alone, without the mock's scripted ones.
    extraEnvironment.LITON_MOCK = "off";
  };

  services.caddy = {
    enable = true;
    virtualHosts.${name}.extraConfig = ''
      reverse_proxy 127.0.0.1:8095
    '';
  };
  # Caddy asks tailscaled for the name's certificate.
  services.tailscale.permitCertUid = "caddy";
}
