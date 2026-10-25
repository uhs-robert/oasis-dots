"""The action manifest reader shared by `act` and the `registry` check step: load, resolve an id, check params.

Standard library only and quick to import, since a key press starts `act`. It trusts the shape the schemas in
specs/schema/ guarantee (the `registry` step runs them) and fails cleanly, not with a traceback, on anything else.
"""

import json
import os


BINDING_FILE = "bindings/quickshell.json"
ACTIONS_FILE = "actions.json"


class ActionError(Exception):
    """A request or manifest problem the caller reports as one line."""


def config_dir():
    """The manifest folder; ACT_CONFIG_DIR is for tests and for running from a checkout."""
    return os.environ.get("ACT_CONFIG_DIR") or os.path.join(
        os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "actions"
    )


def read_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except OSError as error:
        raise ActionError(f"cannot read {path}: {error.strerror}") from None
    except ValueError as error:
        raise ActionError(f"{path} is not valid JSON: {error}") from None


def load(directory=None):
    """(actions by id, bindings by id) from the manifest folder."""
    directory = directory or config_dir()
    actions = read_json(os.path.join(directory, ACTIONS_FILE)).get("actions", [])
    bindings = read_json(os.path.join(directory, BINDING_FILE)).get("bindings", {})
    return {action["id"]: action for action in actions}, bindings


def convert(param, text):
    """The typed value of one command-line word for a param spec, or ActionError naming the param."""
    name, kind = param["name"], param["type"]
    try:
        if kind == "int":
            return int(text)
        if kind == "float":
            return float(text)
        if kind == "bool":
            if text not in ("true", "false"):
                raise ValueError
            return text == "true"
    except ValueError:
        raise ActionError(f"param {name}: {text!r} is not a valid {kind}") from None
    if kind == "enum" and text not in param["values"]:
        raise ActionError(f"param {name}: {text!r} is not one of {', '.join(param['values'])}")
    return text


def bind_params(action, words):
    """{param name: value} for the words given after the id; a param with a default may be left out."""
    params = action.get("params", [])
    if len(words) > len(params):
        raise ActionError(f"{action['id']} takes {len(params)} param(s), got {len(words)}")
    values = {}
    for index, param in enumerate(params):
        if index < len(words):
            values[param["name"]] = convert(param, words[index])
        elif "default" in param:
            values[param["name"]] = param["default"]
        else:
            raise ActionError(f"{action['id']} needs param {param['name']}")
    return values


def render(word, values):
    """A binding word with each {param} replaced; booleans read true/false."""
    for name, value in values.items():
        text = ("true" if value else "false") if isinstance(value, bool) else str(value)
        word = word.replace("{" + name + "}", text)
    return word


def command_line(binding, values, qs_ipc):
    """The argv that performs a binding; `~/` starts a home-relative path."""
    if binding["kind"] == "ipc":
        words = ["call", binding["target"], binding["function"], *binding.get("args", [])]
        argv = [qs_ipc, *[render(word, values) for word in words]]
    else:
        argv = [render(word, values) for word in binding["argv"]]
    return [os.path.expanduser(word) if word.startswith("~/") else word for word in argv]
