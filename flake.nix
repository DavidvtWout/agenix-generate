{
  description = "agenix secret generator extension";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: {
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;
      packages.${system}.agenix-generate =
        nixpkgs.legacyPackages.${system}.callPackage ./pkgs/agenix-generate { };
      packages.${system}.default = self.packages.${system}.agenix-generate;
    });
}
