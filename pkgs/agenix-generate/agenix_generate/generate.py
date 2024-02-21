import argparse
import json
import os
from pathlib import Path
from typing import Dict, List, Set

from .util import Secret, SecretName, load_secrets, save_state, hash_dependencies, hash_pubicKeys, input_yes_no


def check_secrets(secrets: List[Secret], generator_names: List[str]):
    pass


def sort_secrets(secrets: List[Secret]):
    """ In-place topological sort on generator dependencies.

    Also checks some conditions that would make topological sort impossible;
    - `generator.dependencies` may not refer to self
    - `generator.dependencies` must refer to existing secrets
    - dependencies may not be cyclic
    """

    secret_names = {secret.name for secret in secrets}
    dependencies: Dict[SecretName, Set[SecretName]] = {secret.name: set() for secret in secrets}
    inverse_dependencies: Dict[SecretName, Set[SecretName]] = {secret.name: set() for secret in secrets}
    for secret in secrets:
        if secret.generator is not None:
            for dep in secret.generator.dependencies:
                # This condition would also be caught by the cycle detection but this message is more clear.
                if dep == secret.name:
                    print(f"\033[1;91merror:\033[0m generator of '{secret.name}' contains self as dependency")
                    exit(1)
                if dep not in secret_names:
                    print(f"\033[1;91merror:\033[0m dependency '{dep}' of secret '{secret.name}' "
                          f"is not defined in secrets.nix file")
                    # TODO: print suggestions (did you mean ...?)
                    exit(1)
                dependencies[secret.name].add(dep)
                inverse_dependencies[dep].add(secret.name)

    sorted_secrets = list()
    secrets_todo = set(secrets)
    while secrets_todo:
        initial_size = len(secrets_todo)
        for secret in secrets_todo.copy():
            if not dependencies[secret.name]:
                sorted_secrets.append(secret)
                for dep in inverse_dependencies[secret.name]:
                    dependencies[dep].remove(secret.name)
                secrets_todo.remove(secret)
        if len(secrets_todo) == initial_size:
            lines = [f"\033[1;91merror:\033[0m generator dependency cycle detected with the following secrets:"]
            for secret in secrets_todo:
                lines.append(f"  - {secret.name}")
            print("\n".join(lines))
            exit(1)

    # repopulate the old secrets list
    secrets.clear()
    for secret in sorted_secrets:
        secrets.append(secret)


def make_plan(args: argparse.Namespace, states: Dict, secrets: List[Secret]):
    jobs = list()

    for secret in secrets:
        path = Path(secret.name)
        state = states.get(secret.name)

        # Secret file does not exist.
        if not path.exists():
            # Secret does not exist and can't be generated. Should be generated manually.
            if not secret.generator:
                print(f"\033[1;95mwarning:\033[0m {secret.name} does not exist on disk and has no generator.")
            else:
                jobs.append((secret, "generate"))
            continue

        # Secret file exists but is not in state file. Rekey or generate to update state file.
        if state is None:
            print(
                f"\033[1;95mwarning:\033[0m {secret.name} exists but is not in the state file. This should never happen.")
            if secret.generator and secret.generator.dependencies:
                jobs.append((secret, "regenerate"))
            else:
                jobs.append((secret, "rekey"))
            continue

        # Secret file exists and is in the state file.

        # Check if secret needs to be regenerated.
        dependencies_state = state.get("generator", dict()).get("dependencies")
        dependencies_hash = hash_dependencies(secret)
        if dependencies_state == dependencies_hash and dependencies_hash is not None:
            jobs.append((secret, "regenerate"))
            continue

        publicKeys_state = state.get("publicKeys")
        publicKeys_hash = hash_pubicKeys(secret)
        if publicKeys_state != publicKeys_hash:
            jobs.append((secret, "rekey"))
            continue

    # TODO: check for secrets on disk that should be removed
    # TODO: regenerate secrets depending on (re)generated secrets

    return jobs


def main():
    parser = argparse.ArgumentParser(description="agenix-generate tool")

    group = parser.add_mutually_exclusive_group()
    group.add_argument("secret", nargs='?', help="name of the secret to generate")
    group.add_argument("-a", "--all", action="store_true", help="generate all secrets")

    parser.add_argument("--init", type=Path, help="initialize a directory")
    parser.add_argument("-y", "--yes", type=Path, help="don't ask for confirmation")

    parser.add_argument("-i", "--identity", type=Path, default=os.environ.get("AGENIX_IDENTITY"),
                        help="identity to use when rekeying or decrypting a dependency")
    parser.add_argument("-r", "--rules", type=Path, default=os.environ.get("AGENIX_RULES", "secrets.nix"),
                        help="location of the secret definitions (default: secrets.nix)")
    parser.add_argument("-g", "--generators", type=Path,
                        default=os.environ.get("AGENIX_GENERATORS", "generators.nix"),
                        help="location of the generators definitions (default: generators.nix)")

    args = parser.parse_args()

    # Mainly for debugging. Will probably be removed in the future.
    print(f"Running agenix-generate from directory {Path('.').absolute()} with;")
    print(f"  secrets file:    {args.rules.absolute()}")
    print(f"  generators file: {args.generators.absolute()}")

    # Initialize agenix-generate if --init argument is set
    if args.init:
        state_file: Path = args.init / "agenix-generate.state"
        if state_file.exists():
            print(f"\033[1;91merror:\033[0m Directory has already been initialized by agenix-generate")
            exit(1)

        secrets = load_secrets(args)
        state = {secret.name: dict() for secret in secrets}
        save_state(state_file, state)
        exit(0)

    # Check if secret name or --all is set
    if not args.secret and not args.all:
        print(f"\033[1;91merror:\033[0m Either the --all argument must be used or a secret name must be provided")
        parser.print_usage()
        exit(1)

    # Load state file
    state_file = Path("agenix-generate.state")
    if not state_file.exists():
        print(f"\033[1;91merror:\033[0m Directory has not been initialized. First run;\n"
              f"  agenix-generate --init .")
        exit(1)
    with open(state_file, "r") as file:
        state = json.load(file)

    if not args.identity:
        print("\033[1;95mwarning:\033[0m No identity file provided. This makes rekeying secrets or "
              "generating secrets with dependencies impossible.")

    secrets = load_secrets(args)

    # Generate a single secret
    if args.secret:
        generate(secrets, args.secret)
        exit(0)

    # TODO: make sure generators exist before continuing

    # Generate all secrets
    if args.all:
        jobs = make_plan(args, state, secrets)

        print("The following operations will be performed:")
        colours = {"rekey": "92", "generate": "92", "regenerate": "95", "delete": "91"}
        for secret, operation in jobs:
            print(f"- \033[1;{colours[operation]}m{operation: <10}\033[0m {secret.name}")
        if not args.yes and not input_yes_no("Do you want to continue?"):
            exit(0)
        print()

        # TODO: generate/rekey secrets


if __name__ == '__main__':
    main()
