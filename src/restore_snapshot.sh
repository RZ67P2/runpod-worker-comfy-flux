#!/usr/bin/env bash

set -e

# Ensure typer is installed and show debug info
echo "Installing/verifying typer..."
pip install typer==0.15.1
echo "Python environment:"
which python
python --version
echo "Typer location:"
python -c "import typer; print(f'Using typer from: {typer.__file__}')"

SNAPSHOT_FILE=$(ls /*snapshot*.json 2>/dev/null | head -n 1)

if [ -z "$SNAPSHOT_FILE" ]; then
    echo "runpod-worker-comfy: No snapshot file found. Exiting..."
    exit 0
fi

echo "runpod-worker-comfy: restoring snapshot: $SNAPSHOT_FILE"

#comfy --workspace /comfyui node restore-snapshot "$SNAPSHOT_FILE" --pip-non-url

python /comfyui/custom_nodes/ComfyUI-Manager/cm-cli.py restore-snapshot "$SNAPSHOT_FILE"

echo "runpod-worker-comfy: restored snapshot file: $SNAPSHOT_FILE"