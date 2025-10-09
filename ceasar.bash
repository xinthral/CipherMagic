#!/usr/bin/env bash
: '
  The Ceasar Cipher is a simple rotational cryptographic algorithm. However, it is 
  enhanced with the additions of Vigenère modifications.
'

declare -A matrix
CODE='H'
SALT="BABBAGE"
MESG="HAPPY BIRTHDAY"
###########################################################
get_encrypted() {
  local msg="$1"
  shift
  local -a matrix=("$@")
  local key_index=0
  local response=''

  for (( i = 0; i < ${#msg}; i++ )); do
    local ch="${msg:i:1}"
    case "$ch" in
      [[:space:]])
        response+=" "
        ;;
      [[:alnum:]])
        local idx="${SALT:key_index:1}"
        local fidx=$(get_index_of_letter "$idx")
        local sidx=$(get_index_of_letter "$ch")
        local row="${matrix[$fidx]}"
        local val="${row:sidx:1}"
        response+="$val"
        ;;
      *)
        response+="$ch"
        ;;
    esac
    key_index=$(( (key_index + 1) % ${#SALT} ))
  done

  # echo "PHXXF MQYBPKNJ"
  echo "$response"
}

get_decrypted() {
  local msg="${1^^}"
  shift
  local -a matrix=("$@")
  local key_index=0
  local response=''
  local letters
  letters="$(get_letters 0)"

  for ((i=0; i<${#msg}; i++)); do
    local ch="${msg:i:1}"

    case "$ch" in
      [[:space:]])
        response+=" "
        ;;
      [[:alnum:]])
      local key_letter="${SALT:key_index:1}"
      local fidx
      fidx=$(get_index_of_letter "$key_letter")

      local row="${matrix[$fidx]}"
      for ((j=0; j<${#row}; j++)); do
        if [[ "${row:j:1}" == "$ch" ]]; then
          response+="${letters:j:1}"
          break
        fi
      done
    esac

    key_index=$(( (key_index + 1) % ${#SALT} ))
  done

  # echo "$MESG"
  echo "$response"
}

get_letters () {
  local index=${1:-0}
  local letters="ABCDEFGHIJKLMNOPQRSTUVWXYZ";

  index=$(( index % ${#letters} ))
  if (( index < 0 )); then
    index=$(( index + ${#letters} ))
  fi

  local rotated="${letters:index}${letters:0:index}"

  echo "$rotated"
}

get_index_of_letter () {
  local letter="$1"
  local letters="$(get_letters)"
  local index=-1
  for (( i = 0; i < ${#letters}; i++ )); do
    if [[ ${letters:$i:1} == "$letter" ]]; then
      index=$i
    fi
  done
  echo "$index"
}

get_index_of_salt() {
  local letter="$1"
  local letters="$SALT"
  local index=-1
  for (( i = 0; i < ${#letters}; i++ )); do
    if [[ ${letters:$i:1} == "$letter" ]]; then
      index=$i
    fi
  done
  echo "$index"
}

generate_matrix () {
  local letter_index=$(get_index_of_letter "$1")
  local letters="$(get_letters "$letter_index")"
  local -a matrix=()

  for (( i = 0; i < ${#letters}; i++ )); do
    matrix+=("${letters:i}${letters:0:i}")
  done
  
  printf "%s\n" "${matrix[@]}"
}

display_matrix() {
  local -a matrix=("$@")
  local headers="$(get_letters 0)"
  local counter=0

  printf "[ ] "
  for (( i = 0; i < ${#headers}; i++ )); do
    printf " [%s]" "${headers:i:1}"
  done
  printf "\n"

  for row in "${matrix[@]}"; do
    printf "[%s] " "${headers:counter:1}"
    for (( j = 0; j < ${#row}; j++ )); do
      printf "| %s " "${row:j:1}"
    done
    printf "|\n"
    counter=$((counter + 1))
  done
}

declare -a MATRIX
if [[ $# -gt 0 ]]; then
  printf "Not Today Satan\n"
  # Convert input code to integer
  letter_index=$(get_index_of_letter "$1")
  letters="$(get_letters $letter_index)"
  printf "Letters: %s\n" $letters

  mapfile -t MATRIX < <(generate_matrix "H")
  display_matrix "${MATRIX[@]}"
else
  mapfile -t MATRIX < <(generate_matrix "${CODE^^}")
  encrypted="$(get_encrypted "$MESG" "${MATRIX[@]}")"
  decrypted="$(get_decrypted "${encrypted^^}" "${MATRIX[@]}")"
  # display_matrix "${MATRIX[@]}"
  printf "Input:     %s\n" "$MESG"
  printf "Encrypted: %s\n" "$encrypted"
  printf "Decrypted: %s\n" "$decrypted"
fi
