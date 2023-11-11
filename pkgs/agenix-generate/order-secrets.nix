{ secretsPath }:

let
  secrets = import secretsPath;
  secretNames = builtins.attrNames secrets;

  checkDependencies = dependencies:
    builtins.mapAttrs (name: deps:
      let
        nonExistingDeps =
          builtins.filter (dep: !(builtins.elem dep secretNames)) deps;
      in if builtins.elem name deps then
        throw "ERROR: ${name}.generator.dependencies references self!"
      else if nonExistingDeps != [ ] then
        throw
        "ERROR: ${name}.generator.dependencies references non-existing secrets!"
      else
        deps) dependencies;

  dependencies = checkDependencies
    (builtins.mapAttrs (_: secret: secret.generator.dependencies or [ ])
      secrets);

  sortSecrets = deps:
    let
      select = deps:
        builtins.foldl' (best: name:
          if deps.${name} != [ ] then
            best
          else if best == null || name < best then
            name
          else
            best) null (builtins.attrNames deps);

      selectedName = let selectedName' = select deps;
      in if selectedName' == null then
        throw ''
          The following secrets have circular generator.dependencies: ${
            builtins.concatStringsSep ", "
            (builtins.sort (a: b: a < b) (builtins.attrNames deps))
          }
        ''
      else
        selectedName';

      newDeps = builtins.mapAttrs
        (_: deps: builtins.filter (dep: dep != selectedName) deps)
        (builtins.removeAttrs deps [ selectedName ]);

    in if deps == { } then [ ] else [ selectedName ] ++ (sortSecrets newDeps);

in sortSecrets dependencies
