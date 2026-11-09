"""Writes the Python listener's per-frame scores and triggers for raw s16 takes, as the goldens of wake_parity.rs.

  python3 -I home/voxcmd/tests/wake_goldens.py <takes dir> <golden dir>

Every `<take>.s16` in the takes dir gets `<take>.json` in the golden dir: the score of each 80 ms frame and, for each
named level, the frames where the Python TriggerDecider fires on the file's own clock. Needs the downloaded feature
models and the Python listener's openwakeword; nothing opens a microphone.
"""

import importlib.machinery
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WAKE_PATH = os.path.join(os.path.dirname(HERE), ".local", "bin", "voxcmd-wake")
FRAME_BYTES = 1280 * 2
FRAME_SECS = 0.08

sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("voxcmd_wake", WAKE_PATH)
wake = importlib.util.module_from_spec(importlib.util.spec_from_loader("voxcmd_wake", loader))
loader.exec_module(wake)


def golden(take_path):
    # A fresh model per take, as a fresh `voxcmd wake listen --pcm` process is.
    scorer = wake.ModelScorer(wake.Settings({}).model_dir)
    data = open(take_path, "rb").read()
    scores = [
        scorer.score(data[start : start + FRAME_BYTES])
        for start in range(0, len(data) - FRAME_BYTES + 1, FRAME_BYTES)
    ]
    triggers = {}
    for level, (threshold, frames) in wake.SENSITIVITY_LEVELS[wake.WAKE_MODEL].items():
        decider = wake.TriggerDecider(threshold, frames, wake.DEFAULT_COOLDOWN_SECS)
        triggers[level] = [i for i, score in enumerate(scores) if decider.update(score, i * FRAME_SECS)]
    return {"scores": scores, "triggers": triggers}


def main(takes_dir, golden_dir):
    os.makedirs(golden_dir, exist_ok=True)
    for name in sorted(os.listdir(takes_dir)):
        if name.endswith(".s16"):
            result = golden(os.path.join(takes_dir, name))
            with open(os.path.join(golden_dir, name[:-4] + ".json"), "w") as out:
                json.dump(result, out)
            print(name, len(result["scores"]), result["triggers"])


if __name__ == "__main__":
    main(*sys.argv[1:])
