{ lib, stdenv, rage, jq, nix, substituteAll, ageBin ? "${rage}/bin/rage"
, shellcheck, }:

stdenv.mkDerivation rec {
  pname = "agenix-generate";
  version = "0.0.0";
  src = substituteAll {
    src = ./src/agenix-generate.sh;
    loadSecretsNix = ./src/load-secrets.nix;
    updateMetaNix = ./src/update-meta.nix;

    inherit ageBin version;
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
    install -D $src ${placeholder "out"}/bin/agenix-generate
  '';

  meta.description = "agenix generator extension";
}
