#!/usr/bin/env bash
: '
  The Ceasar Cipher is a simple rotational cryptographic algorithm. However, it is 
  enhanced with the additions of Vigenère modifications.
'

CODE='H'
SALT="BABBAGE"
MESG="HAPPY BIRTHDAY"

###########################################################
get_encrypted() {
: '
  get_encrypted(msg, matrix)

  Encrypts a given message using a Caesar-style cipher enhanced with a Vigenère-like salt.

  Parameters:
    msg    - The plaintext string to be encrypted. Spaces are preserved.
    matrix - An array representing the cipher matrix. Each element corresponds
             to a shifted alphabet row.

  Returns:
    Prints the encrypted string to stdout.

  Behavior:
    - Converts msg to uppercase, then iterates over each character.
    - If the character is a space, it is copied to the output unchanged.
    - If the character is a letter (A-Z):
        1. Selects the corresponding salt character based on the current key index.
        2. Finds the row index in the matrix using the salt character.
        3. Finds the column index using the plaintext character.
        4. Appends the ciphered character from matrix[row][col] to the output.
    - Any other character is appended unchanged.
    - Key index cycles through the length of the salt.
'
  local msg="${1^^}"
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
      [A-Z])
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

  echo "$response"
}

get_decrypted() {
: '
  get_decrypted(encrypted, matrix)

  Decrypts a message that was encrypted using a Caesar/Vigenère-style matrix and a SALT string.

  Parameters:
    encrypted - The encrypted string to decrypt. Spaces and non-letter characters are preserved.
    matrix    - Array representing the 26x26 cipher matrix, used to reverse the encryption.

  Returns:
    Prints the decrypted string in uppercase.

  Algorithm:
    1. Convert the input message to uppercase.
    2. Iterate over each character in the message:
       a. If the character is a space, append it unchanged.
       b. If the character is a letter (A-Z):
          i. Determine the current SALT character based on key_index.
          ii. Find the row in the matrix corresponding to the SALT character.
          iii. Search the row for the encrypted character.
          iv. Append the corresponding letter from the standard alphabet to the output.
       c. Non-letter characters (including digits) are appended unchanged.
    3. Cycle key_index through the length of SALT to align with the encryption key.
'
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
      [A-Z])
        local key_letter="${SALT:key_index:1}"
        local fidx=$(get_index_of_letter "$key_letter")
        local row="${matrix[$fidx]}"
        for ((j=0; j<${#row}; j++)); do
          if [[ "${row:j:1}" == "$ch" ]]; then
            response+="${letters:j:1}"
            break
          fi
        done
        ;;
      *)
        response+="$ch"
        ;;
    esac

    key_index=$(( (key_index + 1) % ${#SALT} ))
  done

  echo "$response"
}

get_letters () {
: '
  get_letters([index])

  Returns a rotated alphabet starting from a specified index.

  Parameters:
    index - Optional integer. The rotation starting point in the alphabet (0 = A).
            Defaults to 0 if not provided.

  Returns:
    Prints the rotated alphabet as a string. Example:
      get_letters 7 => HIJKLMNOPQRSTUVWXYZABCDEFG
'
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
: '
  get_index_of_letter(letter)

  Finds the index of a letter in the standard (non-rotated) alphabet.

  Parameters:
    letter - Single character string to locate.

  Returns:
    Prints the zero-based index of the letter. Example:
      get_index_of_letter C => 2
'
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

generate_matrix () {
: '
  generate_matrix(start_letter)

  Generates a 26x26 Caesar/Vigenère matrix starting from a given letter.

  Parameters:
    start_letter - Single uppercase letter to start the first row of the matrix.

  Returns:
    Prints each row of the matrix as a string. Each row is a rotated alphabet
    starting from the corresponding shifted letter.
'
  local letter_index=$(get_index_of_letter "$1")
  local letters="$(get_letters "$letter_index")"
  local -a matrix=()

  for (( i = 0; i < ${#letters}; i++ )); do
    matrix+=("${letters:i}${letters:0:i}")
  done
  
  printf "%s\n" "${matrix[@]}"
}

display_matrix() {
: '
  display_matrix(matrix)

  Displays a Caesar/Vigenère matrix in a readable tabular format.

  Parameters:
    matrix - Array of strings representing each row of the matrix.

  Returns:
    Prints the matrix with row and column headers corresponding to letters A-Z.
'
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

load_config() {
: '
  load_config(path)

  Loads the code, mask, and msg settings from the shared ceasar.ini file.

  Parameters:
    path - The path to the ini file.

  Returns:
    Nothing. Sets the CODE, SALT, and MESG globals. Any setting missing from
    the file (or a missing file) keeps its default value.

  Behavior:
    - Skips blank lines, comments (; or #), and [section] headers.
    - Splits each remaining line at the first "=" and trims both sides.
'
  local path="$1"
  local line key value
  [[ -r "$path" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == [\;\#\[]* || "$line" != *=* ]] && continue
    key="${line%%=*}"; key="${key%"${key##*[![:space:]]}"}"
    value="${line#*=}"; value="${value#"${value%%[![:space:]]*}"}"
    case "$key" in
      code) CODE="$value" ;;
      mask) SALT="${value^^}" ;;
      msg)  MESG="$value" ;;
    esac
  done < "$path"
}

declare -a MATRIX
# The ini lives beside this script
load_config "$(dirname "${BASH_SOURCE[0]}")/ceasar.ini"
if [[ $# -gt 0 ]]; then
  printf "Not Today Satan\n"
  # Convert input code to integer
  letter_index=$(get_index_of_letter "$1")
  letters="$(get_letters $letter_index)"
  printf "Letters: %s\n" $letters

  mapfile -t MATRIX < <(generate_matrix "${1^^}")
  display_matrix "${MATRIX[@]}"
else
  mapfile -t MATRIX < <(generate_matrix "${CODE^^}")
  encrypted="$(get_encrypted "$MESG" "${MATRIX[@]}")"
  decrypted="$(get_decrypted "${encrypted^^}" "${MATRIX[@]}")"
  [[ "$decrypted" == "${MESG^^}" ]] || { printf "Round trip failed: %s\n" "$decrypted" >&2; exit 1; }
  # display_matrix "${MATRIX[@]}"
  printf "Input:     %s\n" "$MESG"
  printf "Encrypted: %s\n" "$encrypted"
  printf "Decrypted: %s\n" "$decrypted"
fi
