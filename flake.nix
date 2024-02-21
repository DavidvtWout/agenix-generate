{
  description = "agenix secret generator extension";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        formatter = nixpkgs.legacyPackages.${system}.nixfmt;

        packages.agenix-check = pkgs.callPackage ./pkgs/agenix-check { };
        packages.agenix-generate = pkgs.callPackage ./pkgs/agenix-generate { };
        packages.default = self.packages.${system}.agenix-generate;
      });
}
