#!/usr/bin/env bash
# Headless rules tests. Does not need the Unity editor.
set -euo pipefail
cd "$(dirname "$0")/RulesTests"
dotnet test -v q --nologo
