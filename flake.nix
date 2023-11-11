{
  description = "agenix secret generator extension";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: {
      formatter = nixpkgs.legacyPackages.${system}.nixfmt;

      packages.agenix-check =
        nixpkgs.legacyPackages.${system}.callPackage ./pkgs/agenix-check { };
      packages.agenix-generate =
        nixpkgs.legacyPackages.${system}.callPackage ./pkgs/agenix-generate { };
      packages.default = self.packages.${system}.agenix-generate;
    });
}
