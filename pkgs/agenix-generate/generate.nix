{ secretName, decrypt, generatorsPath, secretsPath }:

let
  secrets = import secretsPath;
  generators = import generatorsPath;

  secret = secrets.${secretName};
  generator = generators.${secret.generator.name};

  deps = if (builtins.hasAttr "dependencies" secret.generator) then
    map (name: {
      path = name;
      meta = builtins.getAttr name secrets;
    }) secret.generator.dependencies
  else
    [ ];

  args = { inherit decrypt deps; } // (secret.generator.args or { });

in generator args
