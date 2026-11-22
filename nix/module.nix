# services.liton: liton's daemon as a system service, serving its UI and
# /liton/v1 on host:port behind a proxy such as Caddy, which gives the
# browser the secure context the microphone and crypto.subtle need. It
# runs as a user of its own, keeping its database, liton.db, which holds
# every room and the devices' tokens, in /var/lib/liton; `liton pair` run
# as root with LITON_DB=/var/lib/liton/liton.db pairs a device.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.liton;
in
{
  options.services.liton = {
    enable = lib.mkEnableOption "liton's daemon";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "liton's release for this system";
      description = "The liton release, whose daemon runs and whose command line is on PATH.";
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "The address the daemon listens on, LITON_HOST.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8095;
      description = "The port the daemon listens on, LITON_PORT.";
    };
    allowedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "liton.example.ts.net" ];
      description = "The names the daemon is reached by besides host and localhost, such as the proxy's, LITON_ALLOWED_HOSTS.";
    };
    auth = lib.mkOption {
      type = lib.types.enum [
        "on"
        "required"
        "off"
      ];
      default = "required";
      description = "When /liton/v1 answers only paired devices, LITON_AUTH: `required` always.";
    };
    setupFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./liton.setup.json";
      description = "The setup a Litonfile evaluates to (`liton setup`), LITON_SETUP; null for liton's own.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/agenix/liton.env";
      description = "A file of secret settings, such as PASEO_PASSWORD or LITON_PROVIDER_TOKENS, kept out of the Nix store.";
    };
    stt = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "sherpa=ws://127.0.0.1:6006";
      description = "The speech engine voice.v1 dictates with, LITON_STT; null offers no voice.v1.";
    };
    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        LITON_MOCK = "rooms";
      };
      description = "More of the daemon's settings, such as LITON_MOCK or LITON_PROVIDERS.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.services.liton = {
      description = "liton's daemon";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = {
        LITON_HOST = cfg.host;
        LITON_PORT = toString cfg.port;
        LITON_ALLOWED_HOSTS = lib.concatStringsSep "," cfg.allowedHosts;
        LITON_AUTH = cfg.auth;
        LITON_DB = "/var/lib/liton/liton.db";
        LITON_UI = "${cfg.package}/share/liton/www";
      }
      // lib.optionalAttrs (cfg.setupFile != null) { LITON_SETUP = "${cfg.setupFile}"; }
      // lib.optionalAttrs (cfg.stt != null) { LITON_STT = cfg.stt; }
      // cfg.extraEnvironment;
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/liton-daemon";
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        DynamicUser = true;
        StateDirectory = "liton";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/liton";
        UMask = "0077";
        Restart = "always";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
    };
  };
}
