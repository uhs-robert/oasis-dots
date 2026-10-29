#!/usr/bin/env bash
# Runs the Python tests for plain_writing_lint.py.
set -u
python3 -I "$(dirname "$0")/plain_writing_lint_test.py"
