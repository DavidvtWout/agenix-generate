rec {
  description = "agenix secret generator extension";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      inherit (builtins) substring;
      inherit (nixpkgs) lib;

      mtime = self.lastModifiedDate;
      date =
        "${substring 0 4 mtime}-${substring 4 2 mtime}-${substring 6 2 mtime}";
      # rev = self.rev or (throw "Git changes are not committed");

      mkAgenixGenerate = { rustPlatform, nixUnstable, ... }:
        rustPlatform.buildRustPackage {
          pname = "agenix-generate";
          version = "unstable-${date}";
          src = self;

          cargoLock = {
            lockFile = ./Cargo.lock;
            allowBuiltinFetchGit = false;
          };

          nativeBuildInputs = [ nixUnstable.out ];

          meta = {
            inherit description;
            homepage = "https://github.com/DavidvtWout/agenix-generate";
            license = [ lib.licenses.cc0 ];
            mainProgram = "agenix-generate";
          };
        };

    in flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        formatter = pkgs.nixfmt;

        packages = rec {
          default = agenix-generate;
          agenix-generate = pkgs.callPackage mkAgenixGenerate { };
          # agenix-check = pkgs.callPackage ./pkgs/agenix-check { };
        };
      });
}
