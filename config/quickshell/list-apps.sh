#!/bin/bash
# Read the catalog in one process instead of spawning helpers for each field.
exec python3 "$(dirname -- "${BASH_SOURCE[0]}")/scripts/list_apps.py"
