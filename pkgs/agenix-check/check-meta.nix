{ secretName, metaPath, secretsPath }:

let
  secrets = import secretsPath;
  meta = if builtins.pathExists metaPath then
    builtins.fromJSON (builtins.readFile metaPath)
  else
    throw "check-meta: ${metaPath} does not exist!";

  hash = x: builtins.hashString "sha256" (builtins.toJSON x);

  secret = let
    s = secrets.${secretName};
    g = s.generator or { };
  in s // {
    publicKeys = hash (s.publicKeys or [ ]);
    generator = {
      name = g.name or null;
      args = hash (g.args or { });
      dependencies = hash (g.dependencies or [ ]);
      followArgs = g.followArgs or false;
      followDeps = g.followDeps or true;
    };
  };

  secretMeta = let
    s = meta.${secretName} or { };
    g = s.generator or { };
  in s // {
    publicKeys = s.publicKeys or (hash [ ]);
    generator = {
      name = g.name or null;
      args = g.args or (hash { });
      dependencies = g.dependencies or (hash [ ]);
      followArgs = g.followArgs or false;
      followDeps = g.followDeps or true;
    };
  };

in rec {
  needRekey = !inMeta || pubkeysChanged;
  needRegen = regenBecauseArgs || regenBecauseDeps;

  hasGenerator = builtins.hasAttr "name" secret.generator;
  inMeta = builtins.hasAttr secretName meta;
  pubkeysChanged = secret.publicKeys != secretMeta.publicKeys;
  regenBecauseArgs = inMeta && hasGenerator && secret.generator.followArgs
    && (secret.generator.name != secretMeta.generator.name
      || (secret.generator.args != secretMeta.generator.args));
  regenBecauseDeps = inMeta && hasGenerator && secret.generator.followDeps
    && (secret.generator.dependencies != secretMeta.generator.dependencies);
}
