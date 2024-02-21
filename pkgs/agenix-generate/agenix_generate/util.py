import argparse
import hashlib
import json
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

SecretName = str


@dataclass
class Secret:
    name: SecretName
    publicKeys: List[str]
    generator: Optional['Generator'] = field(default=None)

    @staticmethod
    def from_dict(name: SecretName, values: Dict) -> 'Secret':
        s = Secret(name, values["publicKeys"])
        if "generator" in values:
            s.generator = Generator.from_dict(values["generator"])
        return s

    def __eq__(self, other: 'Secret'):
        if isinstance(other, Secret):
            return self.name == other.name
        return NotImplemented

    def __hash__(self):
        return hash(self.name)


@dataclass
class Generator:
    name: SecretName
    args: Dict[str, Any] = field(default_factory=dict)
    dependencies: List[SecretName] = field(default_factory=list)
    followArgs: bool = field(default=False)
    followDeps: bool = field(default=True)

    @staticmethod
    def from_dict(values: Dict) -> 'Generator':
        g = Generator(values["name"])
        if "args" in values:
            g.args = values["args"]
        if "dependencies" in values:
            g.dependencies = values["dependencies"]
        if "followArgs" in values:
            g.followArgs = values["followArgs"]
        if "followDeps" in values:
            g.followDeps = values["followDeps"]
        return g


def _hash(data) -> str:
    m = hashlib.sha256(json.dumps(data, sort_keys=True).encode("utf-8"))
    return m.hexdigest()


def hash_dependencies(secret: Secret) -> Optional[str]:
    if secret.generator and secret.generator.dependencies:
        return _hash(secret.generator.dependencies)


def hash_pubicKeys(secret: Secret) -> str:
    return _hash(secret.publicKeys)


def get_generator_names(args: argparse.Namespace) -> List[str]:
    if not args.generators.exists():
        print(f"\033[1;95mwarning:\033[0m generators file '{args.generators}' does not exist")
        return []

    # TODO: error handling
    result = subprocess.run(
        ["nix", "eval", "--json", "--impure", "--expr",
         f"builtins.attrNames (import {args.generators.absolute()})"],
        capture_output=True, text=True
    )
    return json.loads(result.stdout)


def load_secrets(args: argparse.Namespace) -> List[Secret]:
    if not args.rules.exists():
        print(f"\033[1;91merror:\033[0m secrets file '{args.rules}' does not exist")
        exit(1)

    # TODO: error handling
    result = subprocess.run(["nix", "eval", "--json", "-f", args.rules], capture_output=True, text=True)

    secrets = list()
    secrets_raw = json.loads(result.stdout)
    for name, secret_dict in secrets_raw.items():
        secret = Secret.from_dict(name, secret_dict)
        secrets.append(secret)

    return secrets


def save_state(state_file: Path, state: Dict):
    with open(state_file, "w") as file:
        json.dump(state, file, sort_keys=True)


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
        choice = input().lower()
        if choice == "" and default is not None:
            print()
            return valid[default]
        elif choice in valid:
            return valid[choice]
        else:
            sys.stdout.write("Please respond with 'yes' or 'no' " "(or 'y' or 'n').\n")
