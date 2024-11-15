import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

from .secret import Secret


SecretName = str


def _hash(data) -> str:
    m = hashlib.sha256(json.dumps(data, sort_keys=True).encode("utf-8"))
    return m.hexdigest()


def hash_dependencies(secret: Secret) -> str | None:
    if secret.generator and secret.generator.dependencies:
        return _hash(sorted(secret.generator.dependencies))


def hash_publicKeys(secret: Secret) -> str:
    return _hash(sorted(secret.publicKeys))


def get_generator_names(args: argparse.Namespace) -> list[str]:
    if not args.generators.exists():
        print(f"\033[1;35mwarning:\033[0m generators file '{args.generators}' does not exist")
        return []

    # TODO: error handling
    result = subprocess.run(
        ["nix", "eval", "--json", "--impure", "--expr",
         f"builtins.attrNames (import {args.generators.absolute()})"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def make_generator_function(args: argparse.Namespace, secret: Secret) -> str:
    # TODO: also support generators that are simply a string instead of a function?
    expression = (
        f"let"
        f"  decrypt = \"age --decrypt -i {args.identity.expanduser()}\";"
        f"  secrets = import \"{args.rules.expanduser().absolute()}\";"
        f"  generators = import \"{args.generators.expanduser().absolute()}\";"
        f"  secret = secrets.\"{secret.path}\";"
        f"  generator = generators.${{secret.generator.name}};"
        f"  deps = map (name: {{"
        f"    path = name;"
        f"    meta = secrets.${{name}};"
        f"  }}) secret.generator.dependencies;"
        f""
        f"in generator {{ inherit decrypt deps; }}"
    )
    result = subprocess.run(["nix", "eval", "--impure", "--raw", "--expr", expression],
                            capture_output=True, text=True, check=True)
    return result.stdout


def load_secrets(args: argparse.Namespace) -> list[Secret]:
    if not args.rules.exists():
        print(f"\033[1;91merror:\033[0m secrets file '{args.rules}' does not exist")
        exit(1)

    # TODO: error handling
    result = subprocess.run(["nix", "eval", "--json", "-f", args.rules],
                            capture_output=True, text=True, check=True)

    secrets = list()
    for path, secret_dict in json.loads(result.stdout).items():
        secret = Secret.from_dict(path, secret_dict)
        secrets.append(secret)
    return secrets


def save_states(state_file: Path, state: dict):
    with open(state_file, "w") as file:
        json.dump(state, file, sort_keys=True, indent=2)


def input_yes_no(question, default="yes") -> bool:
    """Ask a yes/no question via input() and return the answer as either True or False.

    "question" is a string that is presented to the user.
    "default" is the presumed answer if the user just hits <Enter>.
            It must be "yes" (the default), "no" or None (meaning
            an answer is required of the user).
    """
    valid = {"yes": True, "y": True, "no": False, "n": False}
    if default is None:
        prompt = " [y/n] "
    elif default in ("y", "yes"):
        prompt = " [Y/n] "
    elif default in ("n", "no"):
        prompt = " [y/N] "
    else:
        raise ValueError(f"invalid default answer: '{default}'")

    while True:
        print(question + prompt, end="")
        try:
            choice = input().lower()
        except KeyboardInterrupt:
            return False
        if choice == "" and default is not None:
            print()
            return valid[default]
        elif choice in valid:
            return valid[choice]
        else:
            sys.stdout.write("Please respond with 'yes' or 'no' " "(or 'y' or 'n').\n")
