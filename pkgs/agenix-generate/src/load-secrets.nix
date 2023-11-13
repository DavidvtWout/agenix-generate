{ secretsPath, generatorsPath, metaPath, decrypt }:

let
  generators = import generatorsPath;

  useMeta = metaPath != "" && metaPath != null;
  meta =
    if useMeta then builtins.fromJSON (builtins.readFile metaPath) else { };

  setDefaults = name: secret:
    let
      publicKeys = secret.publicKeys or [ ];

      g = secret.generator or { };
      generator = {
        name = g.name or null;
        args = g.args or { };
        dependencies = g.dependencies or [ ];
        followArgs = g.followArgs or false;
        followDeps = g.followDeps or true;
      };

      script = let
        generatorFunction = generators.${generator.name};
        deps = map (name: {
          path = name;
          meta = builtins.getAttr name secrets;
        }) generator.dependencies;
        args = { inherit decrypt deps; } // generator.args;
      in if generator.name != null then generatorFunction args else null;

      # Derived from other values
      extraAttributes = let
        secretMeta = meta.${name} or { };
        metaPublicKeys = secretMeta.publicKeys or [ ];
        g = secretMeta.generator or { };
        metaGenerator = {
          name = g.name or null;
          args = g.args or { };
          dependencies = g.dependencies or [ ];
        };
      in rec {
        needRekey = useMeta && (!inMeta || pubkeysChanged);
        needRegen = useMeta && (regenBecauseArgs || regenBecauseDeps);

        hasGenerator = generator.name != null;
        inMeta = builtins.hasAttr name meta;

        pubkeysChanged = publicKeys != metaPublicKeys;
        nameChanged = generator.name != metaGenerator.name;
        argsChanged = generator.args != metaGenerator.args;
        depsChanged = generator.dependencies != metaGenerator.dependencies;

        regenBecauseArgs = useMeta && hasGenerator && (!inMeta
          || (generator.followArgs && (argsChanged || nameChanged)));
        regenBecauseDeps = useMeta && hasGenerator
          && (!inMeta || (generator.followDeps && depsChanged));
      };
    in secret // {
      inherit publicKeys;
      generator = generator // extraAttributes // { inherit script; };
    };

  checkDependencies = secrets:
    let secretNames = builtins.attrNames secrets;
    in builtins.mapAttrs (name: secret:
      let
        dependencies = secret.generator.dependencies;
        nonExistingDeps =
          builtins.filter (dep: !(builtins.elem dep secretNames)) dependencies;
      in if builtins.elem name dependencies then
        throw "${name}.generator.dependencies contains reference to self"
      else if nonExistingDeps != [ ] then
        throw
        "${name}.generator.dependencies contains references to the following non-existing secrets: ${
          builtins.concatStringsSep ", " nonExistingDeps
        }"
      else
        secret) secrets;

  secrets = let
    secretsWithDefaults = builtins.mapAttrs setDefaults (import secretsPath);
  in checkDependencies secretsWithDefaults;

  sortSecrets = secrets':
    let
      secretNames' = builtins.attrNames secrets';

      selectedSecret = let
        # TODO: this is O(n) while avg case O(1) is possible.
        selectedSecret' = builtins.foldl' (picked: name:
          let
            secret = secrets'.${name};
            deps = secret.generator.dependencies;
          in if picked == null && deps == [ ] then {
            inherit name;
            value = secret;
          } else
            picked) null secretNames';

        checkSelected = s:
          if s == null then
            throw ''
              The following secrets have circular generator.dependencies: ${
                builtins.concatStringsSep ", " (builtins.attrNames secrets')
              }
            ''
          else
            s;
      in checkSelected selectedSecret';

      newSecrets = let
        selectedName = selectedSecret.name;
        newSecretsNames =
          builtins.filter (name: name != selectedName) secretNames';
        mkNewSecrets = names:
          builtins.listToAttrs (map (name:
            let
              secret = secrets'.${name};
              newDependencies = builtins.filter (dep: dep != selectedName)
                secret.generator.dependencies;
              generator = secret.generator // {
                dependencies = newDependencies;
              };
            in {
              inherit name;
              value = secret // { inherit generator; };
            }) names);
      in mkNewSecrets newSecretsNames;
    in if secrets' != { } then
      [ selectedSecret ] ++ (sortSecrets newSecrets)
    else
      [ ];

in sortSecrets secrets
