{
  inputs.nix-home.url = "path:/home/colinxs/nix-home";
  # inputs.nix-home.url = "git+ssh://git@github.com/colinxs/home?dir=nix-home";

  inputs.nixpkgs.follows = "nix-home/nixpkgs";
  inputs.flake-utils.follows = "nix-home/flake-utils";
  inputs.flake-compat.follows = "nix-home/flake-compat";

  inputs.general-registry = {
    url = "github:JuliaRegistries/General";
    flake = false;
  };

  outputs = { self, nix-home, nixpkgs, flake-utils, ... }@inputs:
    let
      name = "JuNix";

      outputs = { };

      systemOutputs = flake-utils.lib.eachDefaultSystem (system:
        let
          dev = nix-home.lib;
          pkgs = nix-home.legacyPackages."${system}";
          inherit (pkgs) mur;
          inherit (mur) julia buildJuliaApplication;

          buildJuliaDepot = pkgs.pkgsUnstable.callPackage ./buildJuliaDepot.nix { };
          depot = buildJuliaDepot { depotFile = ./Depot.json; };
        in
        {
          legacyPackages = {
            inherit depot;
          };

          # defaultApp = apps."junix";
          # apps."junix" = flake-utils.lib.mkApp { drv = junix; };

          devShell = pkgs.mkShell {
            buildInputs = with pkgs; [
              mur.julia-latest
            ];
          };
        });
    in
    outputs // systemOutputs;
}
