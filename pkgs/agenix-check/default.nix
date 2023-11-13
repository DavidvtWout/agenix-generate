{ lib, stdenv, rage, jq, nix, substituteAll, shellcheck, }:

stdenv.mkDerivation rec {
  pname = "agenix-check";
  version = "0.0.0";
  src = substituteAll {
    src = ./src/agenix-check.sh;
    checkMetaNix = ./src/check-meta.nix;
    inherit version;
    jqBin = "${jq}/bin/jq";
    nixEval = "${nix}/bin/nix eval";
  };
  dontUnpack = true;

  doCheck = true;
  checkInputs = [ shellcheck ];
  postCheck = ''
    shellcheck $src
  '';

  installPhase = ''
    install -D $src ${placeholder "out"}/bin/agenix-check
  '';

  meta.description = "agenix check extension";
}
