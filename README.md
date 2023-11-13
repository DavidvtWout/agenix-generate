### secrets.nix
For `agenix`, `secrets.nix` only defines a set with paths to secret files as keys and a
publicKeys attribute per secret that defines the keys with which the secret must be encrypted.
`agenix-generate` looks for an additional `generator` attribute in each secret in `secrets.nix`.

The following attributes can be defined for secrets;
- `generator.name`: The name of the generator as defined in `generators.nix`.
- `generator.args`: Arguments that are passed to the generator function. Can be almost anything.
    The only reserved keywords are `decrypt` and `deps`.
- `generator.dependencies`: This is a list of secrets names that this secret depends on. The names 
    in this list are extracted from the set of all secrets and passed as the `deps` argument to the
    generator function. The secrets in `deps` list are sets with a `name` and a `meta` attribute.
    `meta` contains the attributes of the secret as defined in `secrets.nix`.
- `generator.followArgs`: Defaults to false. Regenerate secret if args changes. Only taken into account when meta file is used.
- `generator.followDeps`: Defaults to true. Regenerate secret if dependencies changes. Only taken into account when meta file is used.

All other attributes under `generator` are ignored.

If no `generator` attribute is found, the secret is ignored by `agenix-generate`. This way,
`agenix-generate` is fully backwards-compatible with `agenix`.


### generators.nix
`agenix-generate` does not only need definitions for the secrets but also for the generators.
The generators are defined in a nix file and define scripts that are executed to generate the secret.
This is an example of a `generators.nix` file;

##### Example

Example `secrets.nix` for a htpasswd secret;

```nix
{
  "password.age" = {
    publicKeys = [ "..." ];
    username = "john";
    generator.name = "base64";
    generator.args.length = 24;
  };
  "htpasswd.age" = {
    publicKeys = [ "..." ];
    generator.name = "htpasswd";
    generator.dependencies = [ "password.age" ];
  };
}
```

`generators.nix`;
```nix
let
  pkgs = import ../pkgs.nix { };
  inherit (pkgs) lib;
in {
  base64 = { length ? 32, ... }:
    "${pkgs.openssl}/bin/openssl rand -base64 ${toString length}";
    
  htpasswd = { decrypt, deps, ... }:
    lib.concatMapStrings ({ path, meta }: ''
      echo "# htpasswd for secret ${path}"
      ${decrypt} ${lib.escapeShellArg path} | \
      ${pkgs.apacheHttpd}/bin/htpasswd -niBC 10 ${lib.escapeShellArg meta.username}
    '') deps;
}
```

The file can't be a function and must evaluate to a set (just like `secrets.nix`) so `pkgs` must be imported.

The `htpasswd.age` secret defines `generator.dependencies`. Each item in the list is the name of another secret.
The dependencies are not directly passed to the generator but converted to a `{ path; meta; }` set where path is
the secret name and meta is the full definition for the secret in `secrets.nix`. Since the `password.age` secret
defines a username, this username is now available as `meta.username` in the htpasswd generator.

Because a dependency must be decrypted before use, a `decrypt` function is passed to generators.
Everything defined below `generator.args` is also passed to the generator function.

Because of the dependencies, the order in which the secrets are generated matter. `agenix-generate` ensures
that the secrets are generated in the correct order.

WARNING: the script defined by the generator is directly evaluated so watch out what you put in it!


### meta.json
This is an optional feature that can be used to streamline re-generation and re-keying of secrets when needed.

If path is specified with the AGENIX_META env var or the --meta flag, `agenix-generate` will use
this file to read and store metadata about the secrets. This file contains the generator name, args, 
and dependencies that where used to generate the secret. It also contains the public keys that the
secret file is currently encrypted with.


### rekeying
`agenix` has a rekey option. This rekeys all secrets. Selective rekeying is not possible because the pubkeys that
where used to generate the secret can't be determined from the .age file. If the meta file is used, `agenix-generate`
will do selective rekeying (only rekey if the publicKeys change).
