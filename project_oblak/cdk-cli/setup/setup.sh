#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")/../linux" && pwd)"
echo "export PATH=\"$DIR:\$PATH\"" >> ~/.bashrc
echo "Added $DIR to PATH in ~/.bashrc"
echo "Run 'source ~/.bashrc' or restart your terminal to apply"
