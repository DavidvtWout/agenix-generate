{ lib, stdenv, rage, jq, nix, mktemp, diffutils, substituteAll
, ageBin ? "${rage}/bin/rage", shellcheck, }:

stdenv.mkDerivation rec {
  pname = "agenix-generate";
  version = "0.0.0";
  src = substituteAll {
    inherit ageBin version;
    jqBin = "${jq}/bin/jq";
    nixEval = "${nix}/bin/nix eval";
    src = ./agenix-generate.sh;
    generateNix = ./generate.nix;
    orderSecretsNix = ./order-secrets.nix;
    checkMetaNix = ./check-meta.nix;
    updateMetaNix = ./update-meta.nix;
  };
  dontUnpack = true;

  doCheck = true;
  checkInputs = [ shellcheck ];
  postCheck = ''
    shellcheck $src
  '';

  installPhase = ''
    install -D $src ${placeholder "out"}/bin/agenix-generate
  '';

  meta.description = "agenix generator extension";
}
