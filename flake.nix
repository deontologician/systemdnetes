{
  description = "systemdnetes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    {
      nixosModules = {
        orchestrator = import ./nix/modules/orchestrator.nix;
        worker = import ./nix/modules/worker.nix;
      };
    }
    //
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        haskellPackages = pkgs.haskellPackages.override {
          overrides = hself: hsuper: {
            systemdnetes = hself.callCabal2nix "systemdnetes" ./. { };
          };
        };
        systemdnetes = haskellPackages.systemdnetes;
        staticFiles = pkgs.runCommand "systemdnetes-static" { } ''
          mkdir -p $out/static
          cp ${./static}/* $out/static/
        '';
      in
      {
        packages = {
          default = systemdnetes;
          container = pkgs.dockerTools.buildImage {
            name = "systemdnetes";
            tag = "latest";
            copyToRoot = [ staticFiles ];
            config = {
              Cmd = [ "${pkgs.lib.getBin systemdnetes}/bin/systemdnetes" ];
              WorkingDir = "/";
              ExposedPorts = { "8080/tcp" = { }; };
            };
          };
        };

        devShells.default = haskellPackages.shellFor {
          packages = p: [ p.systemdnetes ];
          nativeBuildInputs = [
            pkgs.cabal-install
            pkgs.haskellPackages.haskell-language-server
            pkgs.ormolu
            pkgs.hlint
            pkgs.ghcid
          ];
        };
      });
}
