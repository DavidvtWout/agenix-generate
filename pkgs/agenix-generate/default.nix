{ python3Packages, rage }:

python3Packages.buildPythonPackage rec {
  pname = "agenix-generate";
  version = "0.0.0";
  format = "pyproject";

  src = ./.;

  nativeBuildInputs = with python3Packages; [ setuptools ];
  propagatedBuildInputs = [ rage ];

  meta = {
    description = "agenix extension tool that automates generation of secrets";
    maintainers = [ "David van 't Wout" ];
  };
}
