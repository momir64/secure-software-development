#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")/../linux" && pwd)"
echo "export PATH=\"$DIR:\$PATH\"" >> ~/.profile
echo "Added $DIR to PATH in ~/.profile"
echo "Run 'source ~/.profile' or restart your terminal to apply"