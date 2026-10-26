#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# The pinned NumPy and SciPy releases require Python 3.12 or later.
proofcam_python=""
for candidate in "${PROOFCAM_PYTHON:-}" python3 python3.14 python3.13 python3.12; do
    [[ -n "$candidate" ]] || continue
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 12))'; then
        proofcam_python="$candidate"
        break
    fi
done
if [[ -z "$proofcam_python" ]]; then
    echo "Python 3.12+ is required. Install it, or set PROOFCAM_PYTHON to its executable path." >&2
    exit 2
fi
if [[ ! -d .venv ]]; then
    "$proofcam_python" -m venv .venv
fi
if ! .venv/bin/python -c 'import sys; sys.exit(sys.version_info < (3, 12))'; then
    echo "The existing .venv needs Python 3.12+. Move it aside and rerun this script." >&2
    exit 2
fi
.venv/bin/python -m pip install -r benchmark/requirements.txt -r provenance/requirements.txt
.venv/bin/python -m pip check
