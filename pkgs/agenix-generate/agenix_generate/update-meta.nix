{ secretName, generated, metaPath, secretsPath, timestamp }:

let
  secrets = import secretsPath;
  meta = if builtins.pathExists metaPath then
    builtins.fromJSON (builtins.readFile metaPath)
  else
    throw "update-meta: META path ${metaPath} does not exist";

  hash = x: builtins.hashString "sha256" (builtins.toJSON x);

  secret = secrets.${secretName};
  metaSecret = meta.${secretName} or { modified = timestamp; };

  publicKeysHash = hash (secret.publicKeys or [ ]);
  metaPublicKeys = metaSecret.publicKeys or "";
  isModified = (publicKeysHash != metaPublicKeys) || generated;

  # If the secret is already in meta, all the existing fields are preserved when
  # making an updated meta set for the secret. This is a done deliberately because
  # then the meta file may also be used for other purposes by other programs.
  updatedMetaSecret = let
    g = secret.generator or { };
    metaG = metaSecret.generator or { };
    generator = if !generated && metaG != { } then {
      generator = metaG;
    } else if generated then {
      generator = let
        args =
          if builtins.hasAttr "args" g then { args = hash g.args; } else { };
        dependencies = if builtins.hasAttr "dependencies" g then {
          dependencies = hash g.dependencies;
        } else
          { };
      in metaG // { name = g.name; } // args // dependencies;
    } else
      { };
  in metaSecret // {
    publicKeys = publicKeysHash;
    modified = if isModified then timestamp else metaSecret.modified;
  } // generator;

in meta // { ${secretName} = updatedMetaSecret; }
