#!/usr/bin/env Rscript
#
#  The Enigma machine is a rotor cipher: every key press steps the rotars, so the
#  same letter comes out differently each time it is typed.
#  This is a port of enigma.cpp, with the same parts, commands and output.
#
#  Signal path for one key press:
#    key -> Plugboard -> Rotar I -> II -> III -> Reflector -> III -> II -> I -> Plugboard -> lamp
#  Every stage on the way back undoes its partner on the way in, with the Reflector's pairs in
#  the middle, so the same settings both encrypt and decrypt.
#
#  Run from the repository root (see the Makefile):
#    make rEnigma                     starts the machine
#    Rscript enigma/enigma.R --test   fixed plugboard key and no screen clearing, for repeatable runs
#
#  Starting settings (plugboard key, rotar start positions) come from enigma.ini, which sits
#  beside this file and is shared with the other language versions. --test ignores it.
#
#  Each part of the machine is an environment, which unlike a list can be changed in
#  place by the functions it is passed to. The functions are grouped by part: rotar_*,
#  reflector_*, plugboard_* and enigma_*.
#  Contact indexes run 0-25 (A = 0 ... Z = 25) as in the other versions; R vectors count
#  from 1, so every lookup in a wiring table adds 1.
#

SYMBOL_COUNT <- 26
# 1941 key-sheet example; with it and positions AAA, HELLOWORLD -> TUBEYQMVQC
TEST_KEY <- "AV BS CG DL FU HZ IN KM OW RX"

# Historical rotar wirings: the letter in slot 1 is where A exits, slot 2 where B exits, and so on
ROTAR_WIRINGS <- c(
  "EKMFLGDQVZNTOWYHXUSPAIBRCJ",   # I
  "AJDKSIRUXBLHWTMCQGZNPYFVOE",   # II
  "BDFHJLCPRTXVZNYEIWGAKMUSQO"    # III
)
# Historical Reflector B
REFLECTOR_WIRING <- "YRUHQSLDPXNGOKMIEBFZCWVJAT"

#' @brief Clears the console (and its scrollback) and moves the cursor to the top-left.
#'
#' @return void
#'
#' @note Needs a terminal that understands ANSI escape codes (Linux terminals and
#'       Windows Terminal do).
clear_screen <- function() {
  cat("\033[2J\033[3J\033[H")
}

#' @brief Splits text into its characters.
#'
#' @param text The text to split.
#' @return A character vector with one element per character (empty for empty text).
split_chars <- function(text) {
  strsplit(text, "", useBytes = TRUE)[[1]]
}

#' @brief Checks whether a character is a letter the machine has a key for (A-Z, either case).
#'
#' @param character The character to check.
#' @return TRUE if the character is between 'A' and 'Z' or 'a' and 'z'.
is_letter <- function(character) {
  character %in% c(LETTERS, letters)
}

#' @brief Converts a letter to its contact index.
#'
#' @param letter A single letter, either case (or a vector of them).
#' @return The index, 'A'/'a' -> 0 ... 'Z'/'z' -> 25.
to_index <- function(letter) {
  match(toupper(letter), LETTERS) - 1
}

#' @brief Converts a contact index back to its uppercase letter.
#'
#' @param idx The index, 0-25 (or a vector of them).
#' @return The letter, 0 -> 'A' ... 25 -> 'Z'.
to_letter <- function(idx) {
  LETTERS[idx + 1]
}

#' @brief Formats a wiring table the way every display function prints it.
#'
#' @param wiring A vector of 26 contact indexes.
#' @return The 26 letters, each followed by a space.
wiring_line <- function(wiring) {
  paste0(to_letter(wiring), " ", collapse = "")
}

#' @brief Loads the plugs and positions settings from the shared enigma.ini file.
#'
#' Reads simple key = value lines, skipping blank lines, comments (; or #), and
#' [section] headers. Any setting missing from the file keeps its default value:
#' plugs is empty (random cables) and positions is AAA. A missing file gives all defaults.
#'
#' @param path The path to the ini file.
#' @return A named list holding plugs and positions.
load_config <- function(path) {
  config <- list(plugs = "", positions = "AAA")
  if (!file.exists(path)) return(config)

  for (line in trimws(readLines(path, warn = FALSE, encoding = "UTF-8"))) {
    if (line == "" || grepl("^[;#[]", line) || !grepl("=", line, fixed = TRUE)) next
    key <- trimws(sub("=.*$", "", line))
    value <- trimws(sub("^[^=]*=", "", line))
    if (key %in% names(config)) config[[key]] <- value
  }

  config
}

#' @brief Builds a rotar with one of the historical wirings, starting at position 0.
#'
#' A rotar is a two-way translation table: receiving input from the Plugboard, each
#' rotar translates an input index and passes it along to the next rotar until it hits
#' the reflector; the rotars then translate the reflected index in reverse order until
#' it reaches the Plugboard again. The wiring never changes; turning the rotar only
#' moves position, which the translate functions apply as an offset.
#'
#' The inverse wiring is calculated from the forward wiring, so the two can never
#' disagree. Prints a message if the config number is unknown, in which case the
#' rotar has no wiring and must not be used.
#'
#' @param label  Name shown in messages and rotar_display, e.g. "I".
#' @param config Which wiring: 0 = I, 1 = II, 2 = III.
#' @return The new rotar: an environment holding label, start (position the rotar
#'         begins at and resets to), position (current position; a carry happens when
#'         it wraps to 0), ingress_array (forward wiring: entry contact -> exit
#'         contact) and engress_array (inverse wiring: exit contact -> entry contact).
rotar_new <- function(label, config) {
  cat("Rotar ", label, " Loaded...\n", sep = "")
  self <- new.env()
  self$label <- label
  self$start <- 0
  self$position <- 0
  self$ingress_array <- integer(0)
  self$engress_array <- integer(0)
  if (is.numeric(config) && config %in% (seq_along(ROTAR_WIRINGS) - 1)) {
    self$ingress_array <- to_index(split_chars(ROTAR_WIRINGS[config + 1]))
    self$engress_array <- integer(SYMBOL_COUNT)
    self$engress_array[self$ingress_array + 1] <- 0:(SYMBOL_COUNT - 1)
  } else {
    cat("Rotar ", label, ": unknown config ", config, " (expected 0-2)\n", sep = "")
  }
  self
}

#' @brief Prints the forward wiring as 26 letters.
#'
#' The letter in slot 1 is where A exits, slot 2 where B exits, and so on. The
#' wiring is shown as built; the current position is not applied.
#'
#' @param self The rotar.
#' @return void
rotar_display <- function(self) {
  cat("Rotary ", self$label, " Configuration\n", sep = "")
  cat(wiring_line(self$ingress_array), "\n", sep = "")
}

#' @brief Advances the rotar one position.
#'
#' Only the position changes; the wiring stays fixed, and the translate functions
#' apply the position offset.
#'
#' @param self The rotar.
#' @return TRUE when the rotar wraps from position 25 back to 0 (carry into the next rotar).
rotar_step <- function(self) {
  self$position <- (self$position + 1) %% SYMBOL_COUNT
  self$position == 0
}

#' @brief Turns the rotar back to its starting position.
#'
#' Decrypting needs the rotars where they were when encrypting began.
#'
#' @param self The rotar.
#' @return void
rotar_reset <- function(self) {
  self$position <- self$start
}

#' @brief Sets the position the rotar begins at, and turns it there.
#'
#' @param self  The rotar.
#' @param start Start position, 0-25 (A = 0 ... Z = 25).
#' @return void
rotar_set_start <- function(self, start) {
  self$start <- start %% SYMBOL_COUNT
  self$position <- self$start
}

#' @brief Passes an index forward through the rotar at its current position.
#'
#' The disc turns but the wires don't: the signal enters wire (idx + p), and the
#' wire's exit end has turned p places too, so p is subtracted on the way out.
#'
#' @param self The rotar.
#' @param idx  Entry contact, 0-25.
#' @return Exit contact, 0-25.
rotar_translate_character <- function(self, idx) {
  wire <- self$ingress_array[(idx + self$position) %% SYMBOL_COUNT + 1]
  (wire - self$position) %% SYMBOL_COUNT
}

#' @brief Passes an index backward through the rotar at its current position.
#'
#' The return trip after the reflector. Same position offset as
#' rotar_translate_character, but looked up in the inverse wiring, so for any position
#' reversing a translated index gives the index back.
#'
#' @param self The rotar.
#' @param idx  Contact the signal comes back in on (an exit contact of the forward pass), 0-25.
#' @return Contact it leaves on (the matching entry contact of the forward pass), 0-25.
rotar_reverse_character <- function(self, idx) {
  wire <- self$engress_array[(idx + self$position) %% SYMBOL_COUNT + 1]
  (wire - self$position) %% SYMBOL_COUNT
}

#' @brief Loads the historical Reflector B wiring and checks it.
#'
#' The reflector sits after the last rotar and sends the signal back through the
#' rotars in reverse. Its wiring is 13 swapped pairs, so it is its own inverse and no
#' letter maps to itself. It never steps and is applied once per key press.
#' Prints a message for any letter that breaks those two rules.
#'
#' @return The new reflector: an environment holding reflection (contact -> paired
#'         contact, the same table both ways).
reflector_new <- function() {
  cat("Reflector Loaded...\n")
  self <- new.env()
  self$reflection <- to_index(split_chars(REFLECTOR_WIRING))
  # A valid reflector is made of pairs (applying it twice gets you back) and never maps a letter to itself
  for (i in 0:(SYMBOL_COUNT - 1)) {
    partner <- self$reflection[i + 1]
    if (self$reflection[partner + 1] != i || partner == i) {
      cat("Reflector: invalid wiring at ", to_letter(i), "\n", sep = "")
    }
  }
  self
}

#' @brief Prints the reflector wiring as 26 letters.
#'
#' The letter in slot 1 is A's partner, slot 2 is B's partner, and so on.
#'
#' @param self The reflector.
#' @return void
reflector_display <- function(self) {
  cat("Reflector Configuration\n")
  cat(wiring_line(self$reflection), "\n", sep = "")
}

#' @brief Bounces an index back toward the rotars.
#'
#' No position offset: the reflector doesn't turn.
#'
#' @param self The reflector.
#' @param idx  Contact coming out of the last rotar, 0-25.
#' @return Paired contact to send back through the rotars, 0-25.
reflector_translate_character <- function(self, idx) {
  self$reflection[idx + 1]
}

#' @brief Builds a plugboard with 10 random cables.
#'
#' Each cable swaps two letters (A <-> V); letters without a cable pass through
#' unchanged. Up to 13 cables, 10 was standard. Because it is built from pairs it is
#' its own inverse, so the same table serves both passes. Use plugboard_set_pairs
#' afterwards to plug in a known key instead.
#'
#' @return The new plugboard: an environment holding pairs (the current cables as
#'         "AV BS CG ...", reusable as a key) and ingress_array (letter -> swapped
#'         letter, itself when no cable is plugged).
plugboard_new <- function() {
  cat("Plugboard is Loaded...\n")
  self <- new.env()
  self$pairs <- ""
  self$ingress_array <- 0:(SYMBOL_COUNT - 1)
  plugboard_random_config(self)
  self
}

#' @brief Prints the key, then the full table as 26 letters.
#'
#' The letter in slot 1 is what A becomes, slot 2 what B becomes, and so on.
#' Unplugged letters show as themselves.
#'
#' @param self The plugboard.
#' @return void
plugboard_display <- function(self) {
  cat("Plugboard Configuration (", self$pairs, ")\n", sep = "")
  cat(wiring_line(self$ingress_array), "\n", sep = "")
}

#' @brief Plugs in cables from a key-sheet style string.
#'
#' Builds the table into a scratch copy and only keeps it if every pair is valid,
#' so a typo leaves the previous cables in place.
#'
#' @param self  The plugboard.
#' @param pairs Letter pairs, spaces optional, any case: "AV BS CG" or "avbscg".
#' @return FALSE (with a message) on a non-letter, a letter paired with itself, a
#'         letter used twice, or a leftover letter with no partner.
plugboard_set_pairs <- function(self, pairs) {
  table <- 0:(SYMBOL_COUNT - 1)   # no cables: every letter maps to itself

  letters_kept <- character(0)
  for (character in split_chars(pairs)) {
    if (grepl("^[[:space:]]$", character)) next
    if (!is_letter(character)) {
      cat("Plugboard: '", character, "' is not a letter\n", sep = "")
      return(FALSE)
    }
    letters_kept <- c(letters_kept, toupper(character))
  }
  if (length(letters_kept) %% 2 != 0) {
    cat("Plugboard: ", letters_kept[length(letters_kept)], " has no partner\n", sep = "")
    return(FALSE)
  }

  cleaned <- character(0)
  for (i in seq_len(length(letters_kept) / 2) * 2 - 1) {   # 1, 3, 5, ...: the first letter of each pair
    first <- to_index(letters_kept[i])
    second <- to_index(letters_kept[i + 1])
    if (first == second) {
      cat("Plugboard: ", letters_kept[i], " can't be plugged into itself\n", sep = "")
      return(FALSE)
    }
    if (table[first + 1] != first || table[second + 1] != second) {   # already swapped by an earlier cable
      cat("Plugboard: ", letters_kept[i], letters_kept[i + 1], " reuses a plugged letter\n", sep = "")
      return(FALSE)
    }
    table[first + 1] <- second
    table[second + 1] <- first
    cleaned <- c(cleaned, paste0(letters_kept[i], letters_kept[i + 1]))
  }

  self$ingress_array <- table
  self$pairs <- paste(cleaned, collapse = " ")
  TRUE
}

#' @brief Plugs in random cables.
#'
#' Shuffles the 26 letters and takes neighbours as pairs, (1,2), (3,4), ..., so no
#' letter can land in two cables. Print the pairs field to keep the key for decrypting.
#'
#' @param self  The plugboard.
#' @param count Number of cables, clamped to 0-13. Defaults to 10.
#' @return void
plugboard_random_config <- function(self, count = 10) {
  count <- max(0, min(count, SYMBOL_COUNT / 2))
  shuffled <- sample(LETTERS)
  invisible(plugboard_set_pairs(self, paste(shuffled[seq_len(count * 2)], collapse = "")))
}

#' @brief Swaps an index for its cabled partner.
#'
#' Used for both passes, keyboard -> rotars and rotars -> lamp.
#'
#' @param self The plugboard.
#' @param idx  Letter index, 0-25.
#' @return The partner's index, or idx itself when the letter has no cable.
plugboard_translate_character <- function(self, idx) {
  self$ingress_array[idx + 1]
}

#' @brief Builds the machine: rotars I, II, III, Reflector B and a plugboard.
#'
#' The machine owns the parts, steps the rotars on each key press and runs the signal
#' through them. Encrypting and decrypting are the same operation: put the machine
#' back in the state it started in (same plugboard key, same start positions, rotars
#' reset) and type the ciphertext.
#' Prints the plugboard key and the rotar start positions once, after they are
#' settled, so they can be written down and used later to decrypt.
#'
#' @param key       Plugboard pairs, e.g. "AV BS CG". Empty (the default) keeps the random
#'                  cables the plugboard starts with; so does a key that
#'                  plugboard_set_pairs rejects.
#' @param positions One start letter per rotar, rotar I first, e.g. "AAA" (the default).
#'                  Empty, or a value enigma_set_positions rejects, leaves every rotar at A.
#' @return The new machine: an environment holding plugs, reflector and rotars (a list;
#'         the first is the fast rotar, stepped on every key press).
#'
#' @note Stepping is a plain odometer carry, and there are no ring settings or rotar
#'       order to choose, so output will not match a historical Enigma.
enigma_new <- function(key = "", positions = "AAA") {
  self <- new.env()
  self$plugs <- plugboard_new()
  self$reflector <- reflector_new()
  cat("Enigma is Loaded...\n")
  names <- c("I", "II", "III")
  self$rotars <- lapply(seq_along(names), function(i) rotar_new(names[i], i - 1))
  if (nzchar(key)) enigma_set_plugs(self, key)
  if (nzchar(positions)) enigma_set_positions(self, positions)
  cat("Plugboard key: ", self$plugs$pairs, "\n", sep = "")
  cat("Rotar positions: ", enigma_positions(self), "\n", sep = "")
  self
}

#' @brief Prints the wiring of every part: plugboard, each rotar, then the reflector.
#'
#' @param self The machine.
#' @return void
enigma_display <- function(self) {
  plugboard_display(self$plugs)
  for (rotar in self$rotars) rotar_display(rotar)
  reflector_display(self$reflector)
}

#' @brief Runs a line of text through the machine and prints the result.
#'
#' Each letter is one key press, so the rotars keep moving from wherever the last
#' line left them. Non-letters are skipped and do not step the rotars. Prints one
#' trace line per letter (see enigma_translate_character), then "Output:" with the result.
#'
#' @param self  The machine.
#' @param input Text to encrypt or decrypt, any case.
#' @return void
enigma_process_input <- function(self, input) {
  output <- character(0)
  for (character in split_chars(input)) {
    if (is_letter(character)) {
      output <- c(output, enigma_translate_character(self, character))
    }
  }
  cat("Output: ", paste(output, collapse = ""), "\n", sep = "")
}

#' @brief Reads lines until "exit" (or the end of input).
#'
#' Commands:   exit            quit
#'             reset           turn the rotars back to their start positions
#'             plugs           show the plugboard key
#'             plugs AV BS ..  set the plugboard (also resets the rotars)
#'             show            display every part's wiring
#' Any other line is run through the machine; non-letters are skipped.
#' To decrypt: reset (and set the same plugs), then type the ciphertext. In a new
#' run the start positions must match too; those come from enigma.ini.
#' A line that starts with a command word is always taken as the command, so
#' those four words can't begin a message.
#'
#' @param self  The machine.
#' @param clear TRUE (the default) wipes the console once before the first prompt and
#'              prints the plugboard key and rotar positions again; results stay on
#'              screen after that.
#' @return void
enigma_run_cli <- function(self, clear = TRUE) {
  prompt <- ">> "
  if (clear) {
    clear_screen()                                                       # once, so results stay on screen between prompts
    cat("Plugboard key: ", self$plugs$pairs, "\n", sep = "")             # the startup copy was just cleared
    cat("Rotar positions: ", enigma_positions(self), "\n", sep = "")
  }
  input <- file("stdin")
  open(input)
  on.exit(close(input))
  repeat {
    cat(prompt)
    flush(stdout())                                # show the prompt before waiting for a line
    line <- readLines(input, n = 1, warn = FALSE)
    if (length(line) == 0) break                   # end of input
    line <- sub("[\r\n]+$", "", line, useBytes = TRUE)   # drop the trailing newline
    space <- regexpr(" ", line, fixed = TRUE, useBytes = TRUE)
    command <- if (space == -1) line else substr(line, 1, space - 1)
    args <- if (space == -1) "" else substr(line, space + 1, nchar(line, type = "bytes"))

    if (command == "exit") {
      break
    } else if (command == "reset") {
      enigma_reset(self)
      cat("Rotars reset\n")
    } else if (command == "plugs") {
      if (nzchar(args) && enigma_set_plugs(self, args)) cat("Rotars reset\n")
      cat("Plugboard key: ", self$plugs$pairs, "\n", sep = "")
    } else if (command == "show") {
      enigma_display(self)
    } else {
      enigma_process_input(self, line)
    }
  }
}

#' @brief Steps the rotars like an odometer.
#'
#' The first rotar steps on every key press; each rotar that completes a full
#' turn carries one step into the next.
#'
#' @param self The machine.
#' @return void
enigma_step_rotors <- function(self) {
  for (rotar in self$rotars) {
    if (!rotar_step(rotar)) break   # no full turn, so nothing carries further
  }
}

#' @brief Turns every rotar back to its start position.
#'
#' The plugboard is left alone. Do this before typing ciphertext to decrypt it.
#'
#' @param self The machine.
#' @return void
enigma_reset <- function(self) {
  for (rotar in self$rotars) rotar_reset(rotar)
}

#' @brief Plugs in a new key and resets the rotars, so the machine starts from a known state.
#'
#' @param self  The machine.
#' @param pairs Letter pairs, e.g. "AV BS CG".
#' @return FALSE if the key was rejected; the previous cables and rotar positions stay as they were.
enigma_set_plugs <- function(self, pairs) {
  if (!plugboard_set_pairs(self$plugs, pairs)) return(FALSE)
  enigma_reset(self)
  TRUE
}

#' @brief Sets where each rotar starts, and turns the rotars there.
#'
#' @param self      The machine.
#' @param positions One letter per rotar, rotar I (the fast rotar) first, either case:
#'                  "AAA" is all at 0, "BAA" starts rotar I one step on.
#' @return FALSE (with a message) unless it is exactly one letter per rotar; the rotars
#'         then stay as they were.
enigma_set_positions <- function(self, positions) {
  characters <- split_chars(positions)
  if (length(characters) != length(self$rotars) || !all(is_letter(characters))) {
    cat("Enigma: positions \"", positions, "\" must be ", length(self$rotars), " letters, one per rotar\n", sep = "")
    return(FALSE)
  }
  for (i in seq_along(self$rotars)) {
    rotar_set_start(self$rotars[[i]], to_index(characters[i]))
  }
  TRUE
}

#' @brief The rotar start positions as letters.
#'
#' @param self The machine.
#' @return One uppercase letter per rotar, rotar I first, e.g. "AAA".
enigma_positions <- function(self) {
  paste(vapply(self$rotars, function(rotar) to_letter(rotar$start), character(1)), collapse = "")
}

#' @brief One key press: steps the rotars, then runs the full signal path.
#'
#' key -> plugboard -> I -> II -> III -> reflector -> III -> II -> I -> plugboard -> lamp
#' Prints each stage, so the line reads left to right along that path: ten letters,
#' the first being the key typed and the last the lamp.
#'
#' @param self      The machine.
#' @param character The key pressed; must be a letter, either case.
#' @return The lit lamp (uppercase letter).
enigma_translate_character <- function(self, character) {
  enigma_step_rotors(self)                                   # rotors move before the signal passes through
  idx <- to_index(character)
  trace <- idx
  idx <- plugboard_translate_character(self$plugs, idx)
  trace <- c(trace, idx)
  for (rotar in self$rotars) {
    idx <- rotar_translate_character(rotar, idx)
    trace <- c(trace, idx)
  }
  idx <- reflector_translate_character(self$reflector, idx)
  trace <- c(trace, idx)
  for (rotar in rev(self$rotars)) {
    idx <- rotar_reverse_character(rotar, idx)
    trace <- c(trace, idx)
  }
  idx <- plugboard_translate_character(self$plugs, idx)      # same cables on the way out
  trace <- c(trace, idx)
  cat(paste(to_letter(trace), collapse = " => "), "\n", sep = "")
  to_letter(idx)
}

#' @brief Starts the machine and its command line.
#'
#' Usage: Rscript enigma.R [--test]
#' No option:  plugboard key and rotar start positions from enigma.ini (random key if
#'             the ini leaves plugs empty), console cleared once.
#' --test:     ignores enigma.ini; fixed plugboard key, positions AAA and no clearing,
#'             so every run starts in the same state and its output can be compared
#'             with an earlier run.
#' enigma.ini is looked for beside this script.
#'
#' @param argv        The command line options.
#' @param script_path The path this script was started with.
#' @return 0 normally, 1 on an unknown option.
main <- function(argv, script_path) {
  test_mode <- FALSE
  for (option in argv) {
    if (option == "--test") {
      test_mode <- TRUE
    } else {
      cat("Unknown option: ", option, "\nUsage: ", script_path, " [--test]\n", sep = "")
      return(1)
    }
  }

  cat("Hello World\n")
  key <- TEST_KEY
  positions <- "AAA"
  if (!test_mode) {
    # The ini lives beside this script
    config <- load_config(file.path(dirname(script_path), "enigma.ini"))
    key <- config$plugs
    positions <- config$positions
  }
  enigma <- enigma_new(key, positions)
  enigma_run_cli(enigma, !test_mode)
  0
}

# Main Usage (only when run directly with Rscript, not when source()'d)
if (sys.nframe() == 0) {
  # Rscript passes the script as --file=...
  script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[1]) else "enigma.R"
  quit(status = main(commandArgs(trailingOnly = TRUE), script_path))
}
