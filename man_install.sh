#!/bin/bash

URL="https://raw.githubusercontent.com/ps81frt/sauvegarde/refs/heads/main/sauvegarde_automatique.man"; NAME="sauvegarde_automatique"; FILE="$NAME.1"; LOCAL="./$FILE"; TMP="/tmp/$FILE"

find_man_dir() { for d in $(man --path | tr ':' '\n'); do [[ "$d" == */man ]] && echo "$d" && return; done; }

install() { D="$1/man1"; [[ -d $D ]] || sudo mkdir -p "$D"; SRC="$LOCAL"; [[ -f "$SRC" ]] || { curl -fsSL "$URL" -o "$TMP" || return 1; SRC="$TMP"; }; sudo cp "$SRC" "$D/$FILE" && sudo mandb "$1"; }

check() { man "$NAME" > /dev/null 2>&1; }

main() { DIR=$(find_man_dir); [[ -z $DIR ]] && echo "no manpath" && exit 1; install "$DIR" || { echo "install failed"; exit 1; }; check && echo "ok" || echo "not found"; }

main
