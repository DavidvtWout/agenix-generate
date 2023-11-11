{ lib, stdenv, rage, jq, nix, substituteAll, ageBin ? "${rage}/bin/rage"
, shellcheck, }:

stdenv.mkDerivation rec {
  pname = "agenix-check";
  version = "0.0.0";
  src = substituteAll {
    inherit ageBin version;
    jqBin = "${jq}/bin/jq";
    nixEval = "${nix}/bin/nix eval";
    src = ./agenix-check.sh;
    checkMetaNix = ./check-meta.nix;
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
