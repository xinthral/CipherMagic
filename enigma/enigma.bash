#!/usr/bin/env bash
: '
  The Enigma machine is a rotor cipher: every key press steps the rotars, so the
  same letter comes out differently each time it is typed.
  This is a port of enigma.cpp, with the same parts, commands and output.

  Signal path for one key press:
    key -> Plugboard -> Rotar I -> II -> III -> Reflector -> III -> II -> I -> Plugboard -> lamp
  Every stage on the way back undoes its partner on the way in, with the Reflector pairs in
  the middle, so the same settings both encrypt and decrypt.

  Run from the repository root (see the Makefile):
    make bashEnigma                  starts the machine
    bash enigma/enigma.bash --test   fixed plugboard key and no screen clearing, for repeatable runs

  Starting settings (plugboard key, rotar start positions) come from enigma.ini, which sits
  beside this file and is shared with the other language versions. --test ignores it.

  Bash has no classes, so each part of the machine is a group of functions (rotar_*,
  reflector_*, plugboard_*, enigma_*) working on the globals below. Functions that
  hand back a value put it in RESULT rather than printing it: capturing output with
  $(...) runs the function in a subshell, which is slow and would throw away any
  change it made to the machine.
'

# Plain C locale: [A-Z] then means exactly A-Z, and strings are measured in bytes
LC_ALL=C

SYMBOL_COUNT=26
LETTERS="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
# 1941 key-sheet example; with it and positions AAA, HELLOWORLD -> TUBEYQMVQC
TEST_KEY="AV BS CG DL FU HZ IN KM OW RX"

# Historical rotar wirings: the letter in slot 1 is where A exits, slot 2 where B exits, and so on
ROTAR_WIRINGS=(
  "EKMFLGDQVZNTOWYHXUSPAIBRCJ"   # I
  "AJDKSIRUXBLHWTMCQGZNPYFVOE"   # II
  "BDFHJLCPRTXVZNYEIWGAKMUSQO"   # III
)
# Historical Reflector B
REFLECTOR_WIRING="YRUHQSLDPXNGOKMIEBFZCWVJAT"

# Letter -> contact index: A -> 0 ... Z -> 25
declare -A LETTER_INDEX
for (( i = 0; i < SYMBOL_COUNT; i++ )); do
  LETTER_INDEX[${LETTERS:i:1}]=$i
done

# Machine state. Every wiring table is a 26-letter string: the letter in slot n is
# where contact n leads. The rotar arrays hold one entry per rotar, rotar I first.
declare -a ROTAR_LABEL=()      # name shown in messages and rotar_display, e.g. "I"
declare -a ROTAR_START=()      # position the rotar begins at and resets to (0-25)
declare -a ROTAR_POSITION=()   # current position (0-25); a carry happens when it wraps to 0
declare -a ROTAR_INGRESS=()    # forward wiring: entry contact -> exit contact
declare -a ROTAR_ENGRESS=()    # inverse wiring: exit contact -> entry contact
REFLECTION=""                  # contact -> paired contact, same table both ways
PLUG_PAIRS=""                  # current cables as "AV BS CG ...", reusable as a key
PLUG_TABLE="$LETTERS"          # letter -> swapped letter (itself when no cable is plugged)
RESULT=""                      # value handed back by the last function that returns one

########################### Console ###########################
clear_screen() {
: '
  clear_screen()

  Clears the console (and its scrollback) and moves the cursor to the top-left.

  Parameters:
    None.

  Returns:
    Nothing.
'
  printf '\033[2J\033[3J\033[H'
}

########################### Helpers ###########################
wiring_line() {
: '
  wiring_line(wiring)

  Formats a wiring table the way every display function prints it.

  Parameters:
    wiring - A 26-letter wiring string.

  Returns:
    Sets RESULT to the 26 letters, each followed by a space.
'
  local wiring="$1"
  local i
  RESULT=''
  for (( i = 0; i < ${#wiring}; i++ )); do
    RESULT+="${wiring:i:1} "
  done
}

########################### Config ###########################
load_config() {
: '
  load_config(path)

  Loads the plugs and positions settings from the shared enigma.ini file.

  Parameters:
    path - The path to the ini file.

  Returns:
    Nothing. Sets the CONFIG_PLUGS and CONFIG_POSITIONS globals. Any setting missing
    from the file (or a missing file) keeps its default value: plugs is empty (random
    cables) and positions is AAA.

  Behavior:
    - Skips blank lines, comments (; or #), and [section] headers.
    - Splits each remaining line at the first "=" and trims both sides.
'
  local path="$1"
  local line key value
  CONFIG_PLUGS=''
  CONFIG_POSITIONS='AAA'
  [[ -r "$path" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == [\;\#\[]* || "$line" != *=* ]] && continue
    key="${line%%=*}"; key="${key%"${key##*[![:space:]]}"}"
    value="${line#*=}"; value="${value#"${value%%[![:space:]]*}"}"
    case "$key" in
      plugs)     CONFIG_PLUGS="$value" ;;
      positions) CONFIG_POSITIONS="$value" ;;
    esac
  done < "$path"
}

########################### Rotar ###########################
rotar_new() {
: '
  rotar_new(label, config)

  Builds a rotar with one of the historical wirings, starting at position 0, and adds
  it to the machine. Each rotar is a two-way translation table: the signal goes
  forward through it on the way to the reflector and backward on the way out. The
  wiring never changes; turning the rotar only moves its position, which the
  translate functions apply as an offset.

  Parameters:
    label  - Name shown in messages and rotar_display, e.g. "I".
    config - Which wiring: 0 = I, 1 = II, 2 = III.

  Returns:
    Nothing. Appends one entry to each ROTAR_* array.

  Behavior:
    - The inverse wiring is calculated from the forward wiring, so the two can
      never disagree.
    - Prints a message if the config number is unknown, in which case the rotar
      has no wiring and must not be used.
'
  local label="$1"
  local config="$2"
  local ingress=''
  local engress=''
  local -a inverse=()
  local i

  printf 'Rotar %s Loaded...\n' "$label"
  if [[ "$config" =~ ^[0-9]+$ ]] && (( config < ${#ROTAR_WIRINGS[@]} )); then
    ingress="${ROTAR_WIRINGS[config]}"
    for (( i = 0; i < SYMBOL_COUNT; i++ )); do
      inverse[LETTER_INDEX[${ingress:i:1}]]="${LETTERS:i:1}"
    done
    printf -v engress '%s' "${inverse[@]}"
  else
    printf 'Rotar %s: unknown config %s (expected 0-2)\n' "$label" "$config"
  fi

  ROTAR_LABEL+=("$label")
  ROTAR_START+=(0)
  ROTAR_POSITION+=(0)
  ROTAR_INGRESS+=("$ingress")
  ROTAR_ENGRESS+=("$engress")
}

rotar_display() {
: '
  rotar_display(rotar)

  Prints the forward wiring as 26 letters. The letter in slot 1 is where A exits,
  slot 2 where B exits, and so on. The wiring is shown as built; the current
  position is not applied.

  Parameters:
    rotar - Which rotar: 0 = the first (fast) rotar.

  Returns:
    Nothing.
'
  local rotar="$1"
  printf 'Rotary %s Configuration\n' "${ROTAR_LABEL[rotar]}"
  wiring_line "${ROTAR_INGRESS[rotar]}"
  printf '%s\n' "$RESULT"
}

rotar_step() {
: '
  rotar_step(rotar)

  Advances the rotar one position. Only the position changes; the wiring stays
  fixed, and the translate functions apply the position offset.

  Parameters:
    rotar - Which rotar: 0 = the first (fast) rotar.

  Returns:
    Success (0) when the rotar wraps from position 25 back to 0, which is the carry
    into the next rotar; failure (1) otherwise.
'
  local rotar="$1"
  ROTAR_POSITION[rotar]=$(( (ROTAR_POSITION[rotar] + 1) % SYMBOL_COUNT ))
  (( ROTAR_POSITION[rotar] == 0 ))
}

rotar_reset() {
: '
  rotar_reset(rotar)

  Turns the rotar back to its starting position. Decrypting needs the rotars where
  they were when encrypting began.

  Parameters:
    rotar - Which rotar: 0 = the first (fast) rotar.

  Returns:
    Nothing.
'
  local rotar="$1"
  ROTAR_POSITION[rotar]=${ROTAR_START[rotar]}
}

rotar_set_start() {
: '
  rotar_set_start(rotar, start)

  Sets the position the rotar begins at, and turns it there.

  Parameters:
    rotar - Which rotar: 0 = the first (fast) rotar.
    start - Start position, 0-25 (A = 0 ... Z = 25).

  Returns:
    Nothing.
'
  local rotar="$1"
  local start="$2"
  ROTAR_START[rotar]=$(( start % SYMBOL_COUNT ))
  ROTAR_POSITION[rotar]=${ROTAR_START[rotar]}
}

rotar_translate_character() {
: '
  rotar_translate_character(rotar, idx)

  Passes an index forward through the rotar at its current position.

  Parameters:
    rotar - Which rotar: 0 = the first (fast) rotar.
    idx   - Entry contact, 0-25.

  Returns:
    Sets RESULT to the exit contact, 0-25.

  Behavior:
    The disc turns but the wires do not: the signal enters wire (idx + p), and the
    exit end of that wire has turned p places too, so p is subtracted on the way
    out. The + SYMBOL_COUNT keeps the result from going negative before the %.
'
  local rotar="$1"
  local idx="$2"
  local position=${ROTAR_POSITION[rotar]}
  local wire="${ROTAR_INGRESS[rotar]:(idx + position) % SYMBOL_COUNT:1}"
  RESULT=$(( (LETTER_INDEX[$wire] - position + SYMBOL_COUNT) % SYMBOL_COUNT ))
}

rotar_reverse_character() {
: '
  rotar_reverse_character(rotar, idx)

  Passes an index backward through the rotar at its current position: the return
  trip after the reflector.

  Parameters:
    rotar - Which rotar: 0 = the first (fast) rotar.
    idx   - Contact the signal comes back in on (an exit contact of the forward pass), 0-25.

  Returns:
    Sets RESULT to the contact it leaves on (the matching entry contact of the
    forward pass), 0-25.

  Behavior:
    Same position offset as rotar_translate_character, but looked up in the inverse
    wiring, so at any position reversing a translated index gives the index back.
'
  local rotar="$1"
  local idx="$2"
  local position=${ROTAR_POSITION[rotar]}
  local wire="${ROTAR_ENGRESS[rotar]:(idx + position) % SYMBOL_COUNT:1}"
  RESULT=$(( (LETTER_INDEX[$wire] - position + SYMBOL_COUNT) % SYMBOL_COUNT ))
}

########################### Reflector ###########################
reflector_new() {
: '
  reflector_new()

  Loads the historical Reflector B wiring and checks it. The reflector sits after the
  last rotar and sends the signal back through the rotars in reverse. Its wiring is
  13 swapped pairs, so it is its own inverse and no letter maps to itself. It never
  steps and is applied once per key press.

  Parameters:
    None.

  Returns:
    Nothing. Sets the REFLECTION global.

  Behavior:
    Prints a message for any letter that breaks the two reflector rules: pairs only,
    and no letter to itself.
'
  local i letter partner
  printf 'Reflector Loaded...\n'
  REFLECTION="$REFLECTOR_WIRING"
  # A valid reflector is made of pairs (applying it twice gets you back) and never maps a letter to itself
  for (( i = 0; i < SYMBOL_COUNT; i++ )); do
    letter="${LETTERS:i:1}"
    partner="${REFLECTION:i:1}"
    if [[ "${REFLECTION:LETTER_INDEX[$partner]:1}" != "$letter" || "$partner" == "$letter" ]]; then
      printf 'Reflector: invalid wiring at %s\n' "$letter"
    fi
  done
}

reflector_display() {
: '
  reflector_display()

  Prints the reflector wiring as 26 letters. The letter in slot 1 is the partner of
  A, slot 2 the partner of B, and so on.

  Parameters:
    None.

  Returns:
    Nothing.
'
  printf 'Reflector Configuration\n'
  wiring_line "$REFLECTION"
  printf '%s\n' "$RESULT"
}

reflector_translate_character() {
: '
  reflector_translate_character(idx)

  Bounces an index back toward the rotars. No position offset: the reflector does
  not turn.

  Parameters:
    idx - Contact coming out of the last rotar, 0-25.

  Returns:
    Sets RESULT to the paired contact to send back through the rotars, 0-25.
'
  local idx="$1"
  RESULT=${LETTER_INDEX[${REFLECTION:idx:1}]}
}

########################### Plugboard ###########################
plugboard_new() {
: '
  plugboard_new()

  Builds a plugboard with 10 random cables. Each cable swaps two letters (A <-> V);
  letters without a cable pass through unchanged. Up to 13 cables, 10 was standard.
  Because it is built from pairs it is its own inverse, so the same table serves the
  pass in and the pass out. Use plugboard_set_pairs afterwards to plug in a known key
  instead.

  Parameters:
    None.

  Returns:
    Nothing. Sets the PLUG_TABLE and PLUG_PAIRS globals.
'
  printf 'Plugboard is Loaded...\n'
  PLUG_PAIRS=''
  PLUG_TABLE="$LETTERS"
  plugboard_random_config
}

plugboard_display() {
: '
  plugboard_display()

  Prints the key, then the full table as 26 letters. The letter in slot 1 is what A
  becomes, slot 2 what B becomes, and so on. Unplugged letters show as themselves.

  Parameters:
    None.

  Returns:
    Nothing.
'
  printf 'Plugboard Configuration (%s)\n' "$PLUG_PAIRS"
  wiring_line "$PLUG_TABLE"
  printf '%s\n' "$RESULT"
}

plugboard_set_pairs() {
: '
  plugboard_set_pairs(pairs)

  Plugs in cables from a key-sheet style string.

  Parameters:
    pairs - Letter pairs, spaces optional, any case: "AV BS CG" or "avbscg".

  Returns:
    Success (0) when the key was plugged in. Failure (1), with a message, on a
    non-letter, a letter paired with itself, a letter used twice, or a leftover
    letter with no partner.

  Behavior:
    Builds the table into a scratch copy and only keeps it if every pair is valid,
    so a typo leaves the previous cables in place.
'
  local pairs="$1"
  local -a table=()
  local -a cleaned=()
  local letters=''
  local i c a b ia ib

  for (( i = 0; i < SYMBOL_COUNT; i++ )); do
    table[i]="${LETTERS:i:1}"                # no cables: every letter maps to itself
  done

  for (( i = 0; i < ${#pairs}; i++ )); do
    c="${pairs:i:1}"
    [[ "$c" == [[:space:]] ]] && continue
    if [[ "$c" != [A-Za-z] ]]; then
      printf "Plugboard: '%s' is not a letter\n" "$c"
      return 1
    fi
    letters+="${c^^}"
  done
  if (( ${#letters} % 2 != 0 )); then
    printf 'Plugboard: %s has no partner\n' "${letters: -1}"
    return 1
  fi

  for (( i = 0; i < ${#letters}; i += 2 )); do
    a="${letters:i:1}"
    b="${letters:i+1:1}"
    ia=${LETTER_INDEX[$a]}
    ib=${LETTER_INDEX[$b]}
    if [[ "$a" == "$b" ]]; then
      printf "Plugboard: %s can't be plugged into itself\n" "$a"
      return 1
    fi
    if [[ "${table[ia]}" != "$a" || "${table[ib]}" != "$b" ]]; then   # already swapped by an earlier cable
      printf 'Plugboard: %s%s reuses a plugged letter\n' "$a" "$b"
      return 1
    fi
    table[ia]="$b"
    table[ib]="$a"
    cleaned+=("$a$b")
  done

  printf -v PLUG_TABLE '%s' "${table[@]}"
  PLUG_PAIRS="${cleaned[*]}"
  return 0
}

plugboard_random_config() {
: '
  plugboard_random_config([count])

  Plugs in random cables.

  Parameters:
    count - Optional number of cables, clamped to 0-13. Defaults to 10.

  Returns:
    Nothing. Sets the PLUG_TABLE and PLUG_PAIRS globals.

  Behavior:
    Shuffles the 26 letters and takes neighbours as pairs, (0,1), (2,3), ..., so no
    letter can land in two cables. Print PLUG_PAIRS to keep the key for decrypting.
'
  local count=${1:-10}
  local -a letters=()
  local i j swap key=''

  (( count < 0 )) && count=0
  (( count > SYMBOL_COUNT / 2 )) && count=$(( SYMBOL_COUNT / 2 ))
  for (( i = 0; i < SYMBOL_COUNT; i++ )); do
    letters[i]="${LETTERS:i:1}"
  done
  for (( i = SYMBOL_COUNT - 1; i > 0; i-- )); do   # Fisher-Yates shuffle
    j=$(( RANDOM % (i + 1) ))
    swap="${letters[i]}"
    letters[i]="${letters[j]}"
    letters[j]="$swap"
  done
  for (( i = 0; i < count * 2; i++ )); do
    key+="${letters[i]}"
  done
  plugboard_set_pairs "$key"
}

plugboard_translate_character() {
: '
  plugboard_translate_character(idx)

  Swaps an index for its cabled partner. Used for both passes, keyboard -> rotars and
  rotars -> lamp.

  Parameters:
    idx - Letter index, 0-25.

  Returns:
    Sets RESULT to the index of the partner, or to idx itself when the letter has no
    cable.
'
  local idx="$1"
  RESULT=${LETTER_INDEX[${PLUG_TABLE:idx:1}]}
}

########################### Enigma ###########################
enigma_new() {
: '
  enigma_new([key], [positions])

  Builds the machine: a plugboard, Reflector B and rotars I, II, III. Encrypting and
  decrypting are the same operation: put the machine back in the state it started in
  (same plugboard key, same start positions, rotars reset) and type the ciphertext.

  Parameters:
    key       - Optional plugboard pairs, e.g. "AV BS CG". Empty keeps the random cables
                the plugboard starts with; so does a key that plugboard_set_pairs rejects.
    positions - Optional start letter per rotar, rotar I first, e.g. "AAA". Empty, or a
                value enigma_set_positions rejects, leaves every rotar at A.

  Returns:
    Nothing.

  Behavior:
    - Prints the plugboard key and the rotar start positions once, after they are
      settled, so they can be written down and used later to decrypt.
    - Stepping is a plain odometer carry, and there are no ring settings or rotar
      order to choose, so output will not match a historical Enigma.
'
  local key="${1:-}"
  local positions="${2:-}"
  local -a names=("I" "II" "III")
  local i

  plugboard_new
  reflector_new
  printf 'Enigma is Loaded...\n'
  # Rotars I, II, III (rotar 0 is the fast rotar that steps on every key)
  ROTAR_LABEL=(); ROTAR_START=(); ROTAR_POSITION=(); ROTAR_INGRESS=(); ROTAR_ENGRESS=()
  for (( i = 0; i < ${#names[@]}; i++ )); do
    rotar_new "${names[i]}" "$i"
  done
  if [[ -n "$key" ]]; then
    enigma_set_plugs "$key"
  fi
  if [[ -n "$positions" ]]; then
    enigma_set_positions "$positions"
  fi
  printf 'Plugboard key: %s\n' "$PLUG_PAIRS"
  enigma_positions
  printf 'Rotar positions: %s\n' "$RESULT"
}

enigma_display() {
: '
  enigma_display()

  Prints the wiring of every part: plugboard, each rotar, then the reflector.

  Parameters:
    None.

  Returns:
    Nothing.
'
  local i
  plugboard_display
  for (( i = 0; i < ${#ROTAR_LABEL[@]}; i++ )); do
    rotar_display "$i"
  done
  reflector_display
}

enigma_process_input() {
: '
  enigma_process_input(input)

  Runs a line of text through the machine and prints the result.

  Parameters:
    input - Text to encrypt or decrypt, any case.

  Returns:
    Nothing.

  Behavior:
    - Each letter is one key press, so the rotars keep moving from wherever the
      last line left them.
    - Non-letters are skipped and do not step the rotars.
    - Prints one trace line per letter (see enigma_translate_character), then
      "Output:" with the result.
'
  local input="$1"
  local output=''
  local i c

  for (( i = 0; i < ${#input}; i++ )); do
    c="${input:i:1}"
    if [[ "$c" == [A-Za-z] ]]; then
      enigma_translate_character "$c"
      output+="$RESULT"
    fi
  done
  printf 'Output: %s\n' "$output"
}

enigma_run_cli() {
: '
  enigma_run_cli(clear)

  Reads lines until "exit" (or the end of input).

  Parameters:
    clear - 1 wipes the console once before the first prompt and prints the plugboard
            key and rotar positions again; results stay on screen after that. 0 leaves
            the console alone.

  Returns:
    Nothing.

  Commands:
    exit            quit
    reset           turn the rotars back to their start positions
    plugs           show the plugboard key
    plugs AV BS ..  set the plugboard (also resets the rotars)
    show            display the wiring of every part

  Behavior:
    - Any other line is run through the machine; non-letters are skipped.
    - To decrypt: reset (and set the same plugs), then type the ciphertext. In a new
      run the start positions must match too; those come from enigma.ini.
    - A line that starts with a command word is always taken as the command, so
      those four words cannot begin a message.
'
  local clear="$1"
  local prompt='>> '
  local line command args

  if (( clear )); then
    clear_screen                                   # once, so results stay on screen between prompts
    printf 'Plugboard key: %s\n' "$PLUG_PAIRS"     # the startup copy was just cleared
    enigma_positions
    printf 'Rotar positions: %s\n' "$RESULT"
  fi
  while true; do
    printf '%s' "$prompt"
    IFS= read -r line || [[ -n "$line" ]] || break   # end of input
    line="${line%$'\r'}"                             # drop the trailing carriage return
    command="${line%% *}"
    args=''
    [[ "$line" == *' '* ]] && args="${line#* }"

    case "$command" in
      exit)
        break
        ;;
      reset)
        enigma_reset
        printf 'Rotars reset\n'
        ;;
      plugs)
        if [[ -n "$args" ]] && enigma_set_plugs "$args"; then
          printf 'Rotars reset\n'
        fi
        printf 'Plugboard key: %s\n' "$PLUG_PAIRS"
        ;;
      show)
        enigma_display
        ;;
      *)
        enigma_process_input "$line"
        ;;
    esac
  done
}

enigma_step_rotors() {
: '
  enigma_step_rotors()

  Steps the rotars like an odometer. The first rotar steps on every key press; each
  rotar that completes a full turn carries one step into the next.

  Parameters:
    None.

  Returns:
    Nothing.
'
  local i
  for (( i = 0; i < ${#ROTAR_LABEL[@]}; i++ )); do
    rotar_step "$i" || break   # no full turn, so nothing carries further
  done
}

enigma_reset() {
: '
  enigma_reset()

  Turns every rotar back to its start position. The plugboard is left alone. Do this
  before typing ciphertext to decrypt it.

  Parameters:
    None.

  Returns:
    Nothing.
'
  local i
  for (( i = 0; i < ${#ROTAR_LABEL[@]}; i++ )); do
    rotar_reset "$i"
  done
}

enigma_set_plugs() {
: '
  enigma_set_plugs(pairs)

  Plugs in a new key and resets the rotars, so the machine starts from a known state.

  Parameters:
    pairs - Letter pairs, e.g. "AV BS CG".

  Returns:
    Success (0) when the key was plugged in. Failure (1) if the key was rejected; the
    previous cables and rotar positions stay as they were.
'
  plugboard_set_pairs "$1" || return 1
  enigma_reset
  return 0
}

enigma_set_positions() {
: '
  enigma_set_positions(positions)

  Sets where each rotar starts, and turns the rotars there.

  Parameters:
    positions - One letter per rotar, rotar I (the fast rotar) first, either case:
                "AAA" is all at 0, "BAA" starts rotar I one step on.

  Returns:
    Success (0) when the positions were set. Failure (1), with a message, unless it
    is exactly one letter per rotar; the rotars then stay as they were.
'
  local positions="$1"
  local i letter

  if (( ${#positions} != ${#ROTAR_LABEL[@]} )) || [[ "$positions" == *[!A-Za-z]* ]]; then
    printf 'Enigma: positions "%s" must be %d letters, one per rotar\n' "$positions" "${#ROTAR_LABEL[@]}"
    return 1
  fi
  for (( i = 0; i < ${#ROTAR_LABEL[@]}; i++ )); do
    letter="${positions:i:1}"
    rotar_set_start "$i" "${LETTER_INDEX[${letter^^}]}"
  done
  return 0
}

enigma_positions() {
: '
  enigma_positions()

  The rotar start positions as letters.

  Parameters:
    None.

  Returns:
    Sets RESULT to one uppercase letter per rotar, rotar I first, e.g. "AAA".
'
  local i
  RESULT=''
  for (( i = 0; i < ${#ROTAR_LABEL[@]}; i++ )); do
    RESULT+="${LETTERS:ROTAR_START[i]:1}"
  done
}

enigma_translate_character() {
: '
  enigma_translate_character(c)

  One key press: steps the rotars, then runs the full signal path.
    key -> plugboard -> I -> II -> III -> reflector -> III -> II -> I -> plugboard -> lamp

  Parameters:
    c - The key pressed; must be a letter, either case.

  Returns:
    Sets RESULT to the lit lamp (uppercase letter).

  Behavior:
    Prints each stage, so the line reads left to right along that path: ten letters,
    the first being the key typed and the last the lamp.
'
  local c="${1^^}"
  local idx=${LETTER_INDEX[$c]}
  local trace="$c"
  local i

  enigma_step_rotors                               # rotors move before the signal passes through
  plugboard_translate_character "$idx"; idx=$RESULT
  trace+=" => ${LETTERS:idx:1}"
  for (( i = 0; i < ${#ROTAR_LABEL[@]}; i++ )); do
    rotar_translate_character "$i" "$idx"; idx=$RESULT
    trace+=" => ${LETTERS:idx:1}"
  done
  reflector_translate_character "$idx"; idx=$RESULT
  trace+=" => ${LETTERS:idx:1}"
  for (( i = ${#ROTAR_LABEL[@]} - 1; i >= 0; i-- )); do
    rotar_reverse_character "$i" "$idx"; idx=$RESULT
    trace+=" => ${LETTERS:idx:1}"
  done
  plugboard_translate_character "$idx"; idx=$RESULT   # same cables on the way out
  trace+=" => ${LETTERS:idx:1}"
  printf '%s\n' "$trace"
  RESULT="${LETTERS:idx:1}"
}

########################### main ###########################
main() {
: '
  main([options])

  Starts the machine and its command line.

  Parameters:
    options - The command line options.

  Returns:
    0 normally, 1 on an unknown option.

  Usage: enigma.bash [--test]
    No option:  plugboard key and rotar start positions from enigma.ini (random key if
                the ini leaves plugs empty), console cleared once.
    --test:     ignores enigma.ini; fixed plugboard key, positions AAA and no clearing,
                so every run starts in the same state and its output can be compared
                with an earlier run.
    enigma.ini is looked for beside this script.
'
  local test_mode=0
  local option
  local key="$TEST_KEY"
  local positions='AAA'

  for option in "$@"; do
    if [[ "$option" == '--test' ]]; then
      test_mode=1
    else
      printf 'Unknown option: %s\nUsage: %s [--test]\n' "$option" "$0"
      return 1
    fi
  done

  printf 'Hello World\n'
  if (( ! test_mode )); then
    # The ini lives beside this script
    load_config "$(dirname "${BASH_SOURCE[0]}")/enigma.ini"
    key="$CONFIG_PLUGS"
    positions="$CONFIG_POSITIONS"
  fi
  enigma_new "$key" "$positions"
  enigma_run_cli $(( ! test_mode ))
  return 0
}

# Main Usage (only when run directly, not when sourced by another script)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi
