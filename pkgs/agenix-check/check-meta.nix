{ secretName, metaPath, secretsPath }:

let
  secrets = import secretsPath;
  meta = if builtins.pathExists metaPath then
    builtins.fromJSON (builtins.readFile metaPath)
  else
    throw "check-meta: ${metaPath} does not exist!";

  secretWithDefaults = s:
    let g = s.generator or { };
    in s // {
      publicKeys = s.publicKeys or [ ];
      generator = {
        args = { };
        dependencies = [ ];
        followArgs = false;
        followDeps = true;
      } // g;
    };

  secret = secretWithDefaults secrets.${secretName};
  secretMeta = secretWithDefaults (meta.${secretName} or { });
in rec {
  needRekey = !inMeta || pubkeysChanged;
  needRegen = regenBecauseArgs || regenBecauseDeps;

  hasGenerator = builtins.hasAttr "name" secret.generator;
  inMeta = builtins.hasAttr secretName meta;
  pubkeysChanged = secret.publicKeys != secretMeta.publicKeys;
  regenBecauseArgs = inMeta && hasGenerator && secret.generator.followArgs
    && (secret.generator.args != secretMeta.generator.args);
  regenBecauseDeps = inMeta && hasGenerator && secret.generator.followDeps
    && (secret.generator.dependencies != secretMeta.generator.dependencies);
}
