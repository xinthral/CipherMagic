#!/usr/bin/env bash

declare -A matrix
CODE='H'
SALT="BABBAGE"
MESG="HAPPY BIRTHDAY"
###########################################################
get_letters () {
  echo "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
}

get_index_of_letter () {
  local letter=$1;
  local letters=$(get_letters)
  local index=-1;
  for (( i=0; i<${#letters}; i++ )); do
    if [[ ${letters:$i:1} == "$letter" ]]; then
      index=$i;
    fi
  done;
  echo $index;
}

generate_matrix () {
  local letters=$(get_letters)
  local rows=${#letters};
  local cols=${#letters};
  for (( i=0; i<rows; i++ )); do
    local row_letters=$(echo $letters | cut -c $(seq -s'' $(($i+1)) $(($i+cols))))
    for (( j=0; j<cols; j++ )); do
      local letter=${row_letters:$j:1}
      local index=$(get_index_of_letter "$letter")
    done;
  done;
}

if [[ $# -gt 0 ]]; then
  printf "Not Today Satan\n";
  let index=$(get_index_of_letter "$1");
  printf "Index: %d\n" $index;
  let mat=$(generate_matrix);
else
  let letters=$(get_letters)
  printf "Letters: %s\n" $letters;
fi