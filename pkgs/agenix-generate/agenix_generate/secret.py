from dataclasses import dataclass, field, fields, is_dataclass


@dataclass
class Generator:
    name: str | None = field(default=None)
    args: dict = field(default_factory=dict)
    dependencies: list[str] = field(default_factory=str)
    optional: bool = field(default=False)
    persistent: bool = field(default=False)


@dataclass
class Secret:
    path: str = field()
    publicKeys: list[str] = field(default_factory=list)
    encrypted: bool = field(default=True)
    meta: dict = field(default_factory=dict)
    generator: Generator = field(default_factory=Generator)

    @classmethod
    def from_dict(cls, path: str, data: dict):
        data["path"] = path
        return dict_to_dataclass(cls, data)


def dict_to_dataclass(cls, data: dict):
    if not is_dataclass(cls):
        raise ValueError(f"{cls} is not a dataclass")

    fields_by_name = {f.name: f for f in fields(cls)}
    init_args = {}
    for key, value in data.items():
        if key in fields_by_name:
            f = fields_by_name[key]
            if is_dataclass(f.type) and isinstance(value, dict):
                init_args[key] = dict_to_dataclass(f.type, value)
            else:
                init_args[key] = value

    return cls(**init_args)
