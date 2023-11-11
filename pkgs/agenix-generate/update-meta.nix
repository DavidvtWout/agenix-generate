{ secretName, regenerated, metaPath, secretsPath, timestamp }:

let
  secrets = import secretsPath;
  meta = if builtins.pathExists metaPath then
    builtins.fromJSON (builtins.readFile metaPath)
  else
    throw "update-meta: ${metaPath} does not exist!";

  # Copied from attrsets.nix and converted to builtins.
  filterAttrs = pred: set:
    builtins.listToAttrs (builtins.concatMap (name:
      let value = set.${name};
      in if pred name value then [{ inherit name value; }] else [ ])
      (builtins.attrNames set));

  # Create a generator with empty values if it did not exist and filter out all
  # values that are not added to the meta file.
  sanitizeGenerator = secret:
    let
      generator = {
        name = null;
        args = { };
        dependencies = [ ];
      } // (if (builtins.hasAttr "generator" secret) && secret.generator
      != null then
        filterAttrs
        (name: _: builtins.elem name [ "name" "args" "dependencies" ])
        secret.generator
      else
        { });
    in secret // { inherit generator; };

  secret =
    filterAttrs (name: _: builtins.elem name [ "publicKeys" "generator" ])
    (sanitizeGenerator secrets.${secretName});

  metaSecret = if builtins.hasAttr secretName meta then
    filterAttrs (name: _:
      builtins.elem name [ "publicKeys" "generator" "created" "modified" ])
    (sanitizeGenerator meta.${secretName})
  else {
    inherit (secret) publicKeys generator;
    created = timestamp;
    modified = timestamp;
  };

  newMeta = let
    isModified = (metaSecret.publicKeys != secret.publicKeys) || regenerated;

    newMetaSecret = (meta.${secretName} or metaSecret) // {
      publicKeys = secret.publicKeys;
      generator =
        let g = if regenerated then secret.generator else metaSecret.generator;
        in if g.name == null then
          null
        else
          filterAttrs (_: value: value != [ ] && value != { }) g;
      modified = if isModified then timestamp else metaSecret.modified;
    };

  in meta // { ${secretName} = newMetaSecret; };

in newMeta
