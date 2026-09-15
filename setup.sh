#!/bin/bash

SCRIPT_DIR="."

if [ ! -d $SCRIPT_DIR/.venv ]; then
  python3 -m venv .venv
fi

source ./.venv/bin/activate
pip install --upgrade pip
pip install ansible passlib
