#!/usr/bin/env bash

get_letters () {
  echo "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
}

if [[ $# -gt 0 ]]; then
  letters=$(get_letters)
  echo "Letters: " $letters;
fi