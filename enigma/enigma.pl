#!/usr/bin/env perl
=begin comment
  The Enigma machine is a rotor cipher: every key press steps the rotars, so the
  same letter comes out differently each time it is typed.
  This is a port of enigma.cpp, with the same classes, commands and output.

  Signal path for one key press:
    key -> Plugboard -> Rotar I -> II -> III -> Reflector -> III -> II -> I -> Plugboard -> lamp
  Every stage on the way back undoes its partner on the way in, with the Reflector's pairs in
  the middle, so the same settings both encrypt and decrypt.

  Run from the repository root (see the Makefile):
    make perlEnigma                starts the machine
    perl enigma/enigma.pl --test   fixed plugboard key and no screen clearing, for repeatable runs

  Starting settings (plugboard key, rotar start positions) come from enigma.ini, which sits
  beside this file and is shared with the other language versions. --test ignores it.

  Each part of the machine is a package (Rotar, Reflector, Plugboard, Enigma) whose
  objects are blessed hash references; the helper subs they share are in package main.
=cut
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;
use List::Util qw(shuffle min max);

use constant SYMBOL_COUNT => 26;
# 1941 key-sheet example; with it and positions AAA, HELLOWORLD -> TUBEYQMVQC
use constant TEST_KEY => 'AV BS CG DL FU HZ IN KM OW RX';

#!
# @brief Turns on ANSI escape-code support in the Windows console.
#
# Windows Terminal and Linux terminals understand escape codes already; the older
# Windows console (conhost) only does after a call into the system shell.
# Only needed by a native Windows perl; does nothing anywhere else. Call once at startup.
#
# @return void
#
sub enable_ansi {
  system($ENV{COMSPEC} // 'cmd', '/c', '') if $^O eq 'MSWin32';
}

#!
# @brief Clears the console (and its scrollback) and moves the cursor to the top-left.
#
# @return void
#
# @note Requires enable_ansi() to have been called on Windows.
#
sub clear_screen {
  print "\e[2J\e[3J\e[H";
}

#!
# @brief Checks whether a character is a letter the machine has a key for (A-Z, either case).
#
# @param character The character to check.
# @return True if the character is between 'A' and 'Z' or 'a' and 'z'.
#
sub is_letter {
  my ($character) = @_;
  return $character =~ /^[A-Za-z]$/;
}

#!
# @brief Converts a letter to its contact index.
#
# @param letter A single letter, either case.
# @return The index, 'A'/'a' -> 0 ... 'Z'/'z' -> 25.
#
sub to_index {
  my ($letter) = @_;
  return ord(uc $letter) - ord('A');
}

#!
# @brief Converts a contact index back to its uppercase letter.
#
# @param idx The index, 0-25.
# @return The letter, 0 -> 'A' ... 25 -> 'Z'.
#
sub to_letter {
  my ($idx) = @_;
  return chr(ord('A') + $idx);
}

#!
# @brief Formats a wiring table the way every display method prints it.
#
# @param wiring_ref Reference to an array of 26 contact indexes.
# @return The 26 letters, each followed by a space.
#
sub wiring_line {
  my ($wiring_ref) = @_;
  return join '', map { to_letter($_) . ' ' } @$wiring_ref;
}

#!
# @brief Loads the plugs and positions settings from the shared enigma.ini file.
#
# Reads simple key = value lines, skipping blank lines, comments (; or #), and
# [section] headers. Any setting missing from the file keeps its default value:
# plugs is empty (random cables) and positions is AAA. A missing file gives all defaults.
#
# @param path The path to the ini file.
# @return A hash reference holding plugs and positions.
#
sub load_config {
  my ($path) = @_;
  my %config = (plugs => '', positions => 'AAA');

  open(my $fh, '<:encoding(UTF-8)', $path) or return \%config;
  while (my $line = <$fh>) {
    $line =~ s/^\s+|\s+$//g;
    next if $line eq '' || $line =~ /^[;#\[]/;
    my ($key, $value) = split /=/, $line, 2;
    next unless defined $value;
    $key =~ s/^\s+|\s+$//g;
    $value =~ s/^\s+|\s+$//g;
    $config{$key} = $value if exists $config{$key};
  }
  close($fh);

  return \%config;
}

#!
# @brief Two-way chaining translation matrix.
#
# Receiving input from the Plugboard, each rotar translates an input index and passes it
# along to the next rotar until it hits the reflector; the rotars then translate the
# reflected index in reverse order until it reaches the Plugboard again.
# The wiring never changes; turning the rotar only moves position, which the translate
# methods apply as an offset. start is where reset() returns it to.
#
package Rotar;

# Historical wirings: the letter in slot 1 is where A exits, slot 2 where B exits, and so on
my @WIRINGS = (
  'EKMFLGDQVZNTOWYHXUSPAIBRCJ',   # I
  'AJDKSIRUXBLHWTMCQGZNPYFVOE',   # II
  'BDFHJLCPRTXVZNYEIWGAKMUSQO',   # III
);

#!
# @brief Builds a rotar with one of the historical wirings, starting at position 0.
#
# The inverse wiring is calculated from the forward wiring, so the two can never
# disagree. Prints a message if the config number is unknown, in which case the
# rotar has no wiring and must not be used.
#
# @param label  Name shown in messages and display(), e.g. "I".
# @param config Which wiring: 0 = I, 1 = II, 2 = III.
# @return The new rotar.
#
sub new {
  my ($class, $label, $config) = @_;
  print "Rotar $label Loaded...\n";
  my $self = bless {
    label         => $label,
    start         => 0,    # position the rotar begins at and resets to (0-25)
    position      => 0,    # current position (0-25); a carry happens when it wraps to 0
    ingress_array => [],   # forward wiring: entry contact -> exit contact
    engress_array => [],   # inverse wiring: exit contact -> entry contact
  }, $class;

  if ($config =~ /^\d+$/ && $config < @WIRINGS) {
    my @ingress = map { main::to_index($_) } split //, $WIRINGS[$config];
    my @engress = (0) x main::SYMBOL_COUNT;
    $engress[$ingress[$_]] = $_ for 0 .. $#ingress;
    $self->{ingress_array} = \@ingress;
    $self->{engress_array} = \@engress;
  } else {
    print "Rotar $label: unknown config $config (expected 0-2)\n";
  }

  return $self;
}

#!
# @brief Prints the forward wiring as 26 letters.
#
# The letter in slot 1 is where A exits, slot 2 where B exits, and so on. The
# wiring is shown as built; the current position is not applied.
#
# @return void
#
sub display {
  my ($self) = @_;
  print "Rotary $self->{label} Configuration\n";
  print main::wiring_line($self->{ingress_array}), "\n";
}

#!
# @brief Advances the rotar one position.
#
# Only the position changes; the wiring stays fixed, and the translate methods
# apply the position offset.
#
# @return True when the rotar wraps from position 25 back to 0 (carry into the next rotar).
#
sub step {
  my ($self) = @_;
  $self->{position} = ($self->{position} + 1) % main::SYMBOL_COUNT;
  return $self->{position} == 0;
}

#!
# @brief Turns the rotar back to its starting position.
#
# Decrypting needs the rotars where they were when encrypting began.
#
# @return void
#
sub reset {
  my ($self) = @_;
  $self->{position} = $self->{start};
}

#!
# @brief Sets the position the rotar begins at, and turns it there.
#
# @param start Start position, 0-25 (A = 0 ... Z = 25).
# @return void
#
sub set_start {
  my ($self, $start) = @_;
  $self->{start} = $start % main::SYMBOL_COUNT;
  $self->{position} = $self->{start};
}

#!
# @brief Passes an index forward through the rotar at its current position.
#
# The disc turns but the wires don't: the signal enters wire (idx + p), and the
# wire's exit end has turned p places too, so p is subtracted on the way out.
#
# @param idx Entry contact, 0-25.
# @return Exit contact, 0-25.
#
sub translate_character {
  my ($self, $idx) = @_;
  my $wire = $self->{ingress_array}[($idx + $self->{position}) % main::SYMBOL_COUNT];
  return ($wire - $self->{position}) % main::SYMBOL_COUNT;
}

#!
# @brief Passes an index backward through the rotar at its current position.
#
# The return trip after the reflector. Same position offset as translate_character,
# but looked up in the inverse wiring, so for any position
# reverse_character(translate_character(x)) == x.
#
# @param idx Contact the signal comes back in on (an exit contact of the forward pass), 0-25.
# @return Contact it leaves on (the matching entry contact of the forward pass), 0-25.
#
sub reverse_character {
  my ($self, $idx) = @_;
  my $wire = $self->{engress_array}[($idx + $self->{position}) % main::SYMBOL_COUNT];
  return ($wire - $self->{position}) % main::SYMBOL_COUNT;
}

#!
# @brief Fixed, one-sided translation matrix (historical Reflector B).
#
# Sits after the last rotar and sends the signal back through the rotars in reverse.
# Its wiring is 13 swapped pairs, so it is its own inverse and no letter maps to
# itself. It never steps and is applied once per key press.
#
package Reflector;

# Historical Reflector B
my $WIRING = 'YRUHQSLDPXNGOKMIEBFZCWVJAT';

#!
# @brief Loads the Reflector B wiring and checks it.
#
# Prints a message for any letter that breaks the two reflector rules: pairs only,
# and no letter to itself.
#
# @return The new reflector.
#
sub new {
  my ($class) = @_;
  print "Reflector Loaded...\n";
  my @reflection = map { main::to_index($_) } split //, $WIRING;
  # A valid reflector is made of pairs (applying it twice gets you back) and never maps a letter to itself
  for my $i (0 .. main::SYMBOL_COUNT - 1) {
    if ($reflection[$reflection[$i]] != $i || $reflection[$i] == $i) {
      print "Reflector: invalid wiring at ", main::to_letter($i), "\n";
    }
  }
  # reflection: contact -> paired contact, the same table both ways
  return bless { reflection => \@reflection }, $class;
}

#!
# @brief Prints the reflector wiring as 26 letters.
#
# The letter in slot 1 is A's partner, slot 2 is B's partner, and so on.
#
# @return void
#
sub display {
  my ($self) = @_;
  print "Reflector Configuration\n";
  print main::wiring_line($self->{reflection}), "\n";
}

#!
# @brief Bounces an index back toward the rotars.
#
# No position offset: the reflector doesn't turn.
#
# @param idx Contact coming out of the last rotar, 0-25.
# @return Paired contact to send back through the rotars, 0-25.
#
sub translate_character {
  my ($self, $idx) = @_;
  return $self->{reflection}[$idx];
}

#!
# @brief Swapped-pair translation matrix, passed on the way in and on the way out.
#
# Each cable swaps two letters (A <-> V); letters without a cable pass through
# unchanged. Up to 13 cables, 10 was standard. Because it is built from pairs it is
# its own inverse, so the same table serves both passes.
#
package Plugboard;

#!
# @brief Builds a plugboard with 10 random cables.
#
# Use set_pairs afterwards to plug in a known key instead.
#
# @return The new plugboard.
#
sub new {
  my ($class) = @_;
  print "Plugboard is Loaded...\n";
  my $self = bless {
    pairs         => '',                               # current cables as "AV BS CG ...", reusable as a key
    ingress_array => [ 0 .. main::SYMBOL_COUNT - 1 ],  # letter -> swapped letter (itself when no cable is plugged)
  }, $class;
  $self->random_config();
  return $self;
}

#!
# @brief Prints the key, then the full table as 26 letters.
#
# The letter in slot 1 is what A becomes, slot 2 what B becomes, and so on.
# Unplugged letters show as themselves.
#
# @return void
#
sub display {
  my ($self) = @_;
  print "Plugboard Configuration ($self->{pairs})\n";
  print main::wiring_line($self->{ingress_array}), "\n";
}

#!
# @brief Plugs in cables from a key-sheet style string.
#
# Builds the table into a scratch copy and only keeps it if every pair is valid,
# so a typo leaves the previous cables in place.
#
# @param pairs Letter pairs, spaces optional, any case: "AV BS CG" or "avbscg".
# @return False (with a message) on a non-letter, a letter paired with itself, a
#         letter used twice, or a leftover letter with no partner.
#
sub set_pairs {
  my ($self, $pairs) = @_;
  my @table = (0 .. main::SYMBOL_COUNT - 1);   # no cables: every letter maps to itself

  my $letters = '';
  for my $character (split //, $pairs) {
    next if $character =~ /\s/;
    if (!main::is_letter($character)) {
      print "Plugboard: '$character' is not a letter\n";
      return 0;
    }
    $letters .= uc $character;
  }
  if (length($letters) % 2 != 0) {
    print "Plugboard: ", substr($letters, -1), " has no partner\n";
    return 0;
  }

  my @cleaned;
  for (my $i = 0; $i < length($letters); $i += 2) {
    my $pair = substr($letters, $i, 2);
    my $first = main::to_index(substr($pair, 0, 1));
    my $second = main::to_index(substr($pair, 1, 1));
    if ($first == $second) {
      print "Plugboard: ", substr($pair, 0, 1), " can't be plugged into itself\n";
      return 0;
    }
    if ($table[$first] != $first || $table[$second] != $second) {   # already swapped by an earlier cable
      print "Plugboard: $pair reuses a plugged letter\n";
      return 0;
    }
    $table[$first] = $second;
    $table[$second] = $first;
    push @cleaned, $pair;
  }

  $self->{ingress_array} = \@table;
  $self->{pairs} = join ' ', @cleaned;
  return 1;
}

#!
# @brief Plugs in random cables.
#
# Shuffles the 26 letters and takes neighbours as pairs, (0,1), (2,3), ..., so no
# letter can land in two cables. Print the pairs field to keep the key for decrypting.
#
# @param count Number of cables, clamped to 0-13. Defaults to 10.
# @return void
#
sub random_config {
  my ($self, $count) = @_;
  $count = main::max(0, main::min($count // 10, main::SYMBOL_COUNT / 2));
  my @letters = main::shuffle(map { main::to_letter($_) } 0 .. main::SYMBOL_COUNT - 1);
  $self->set_pairs(join '', @letters[0 .. $count * 2 - 1]);
}

#!
# @brief Swaps an index for its cabled partner.
#
# Used for both passes, keyboard -> rotars and rotars -> lamp.
#
# @param idx Letter index, 0-25.
# @return The partner's index, or idx itself when the letter has no cable.
#
sub translate_character {
  my ($self, $idx) = @_;
  return $self->{ingress_array}[$idx];
}

#!
# @brief The whole machine: a Plugboard, three Rotars and a Reflector, plus the command line.
#
# Owns the parts, steps the rotars on each key press and runs the signal through
# them. Encrypting and decrypting are the same operation: put the machine back in
# the state it started in (same plugboard key, same start positions, rotars reset) and
# type the ciphertext.
#
# @note Stepping is a plain odometer carry, and there are no ring settings or rotar
#       order to choose, so output will not match a historical Enigma.
#
package Enigma;

#!
# @brief Builds the machine: rotars I, II, III, Reflector B and a plugboard.
#
# Prints the plugboard key and the rotar start positions once, after they are
# settled, so they can be written down and used later to decrypt.
#
# @param key       Plugboard pairs, e.g. "AV BS CG". Empty or missing keeps the random
#                  cables the plugboard starts with; so does a key that set_pairs rejects.
# @param positions One start letter per rotar, rotar I first, e.g. "AAA" (the default).
#                  Empty, or a value set_positions rejects, leaves every rotar at A.
# @return The new machine.
#
sub new {
  my ($class, $key, $positions) = @_;
  $key //= '';
  $positions //= 'AAA';
  my $self = bless {}, $class;
  $self->{plugs} = Plugboard->new();
  $self->{reflector} = Reflector->new();
  print "Enigma is Loaded...\n";
  # Rotars I, II, III (rotars[0] is the fast rotar that steps on every key)
  my @names = ('I', 'II', 'III');
  $self->{rotars} = [ map { Rotar->new($names[$_], $_) } 0 .. $#names ];
  $self->set_plugs($key) if $key ne '';
  $self->set_positions($positions) if $positions ne '';
  print "Plugboard key: $self->{plugs}{pairs}\n";
  print "Rotar positions: ", $self->positions(), "\n";
  return $self;
}

#!
# @brief Prints the wiring of every part: plugboard, each rotar, then the reflector.
#
# @return void
#
sub display {
  my ($self) = @_;
  $self->{plugs}->display();
  $_->display() for @{ $self->{rotars} };
  $self->{reflector}->display();
}

#!
# @brief Runs a line of text through the machine and prints the result.
#
# Each letter is one key press, so the rotars keep moving from wherever the last
# line left them. Non-letters are skipped and do not step the rotars. Prints one
# trace line per letter (see translate_character), then "Output:" with the result.
#
# @param input Text to encrypt or decrypt, any case.
# @return void
#
sub process_input {
  my ($self, $input) = @_;
  my $output = '';
  for my $character (split //, $input) {
    $output .= $self->translate_character($character) if main::is_letter($character);
  }
  print "Output: $output\n";
}

#!
# @brief Reads lines until "exit" (or the end of input).
#
# Commands:   exit            quit
#             reset           turn the rotars back to their start positions
#             plugs           show the plugboard key
#             plugs AV BS ..  set the plugboard (also resets the rotars)
#             show            display every part's wiring
# Any other line is run through the machine; non-letters are skipped.
# To decrypt: reset (and set the same plugs), then type the ciphertext. In a new
# run the start positions must match too; those come from enigma.ini.
# A line that starts with a command word is always taken as the command, so
# those four words can't begin a message.
#
# @param clear True wipes the console once before the first prompt and prints the
#              plugboard key and rotar positions again; results stay on screen after that.
# @return void
#
sub run_cli {
  my ($self, $clear) = @_;
  my $prompt = '>> ';
  if ($clear) {
    main::clear_screen();                                 # once, so results stay on screen between prompts
    print "Plugboard key: $self->{plugs}{pairs}\n";       # the startup copy was just cleared
    print "Rotar positions: ", $self->positions(), "\n";
  }
  while (1) {
    print $prompt;
    my $line = <STDIN>;
    last unless defined $line;                            # end of input
    $line =~ s/[\r\n]+$//;                                # drop the trailing newline
    my ($command, $args) = split / /, $line, 2;
    $command //= '';
    $args //= '';

    if ($command eq 'exit') {
      last;
    } elsif ($command eq 'reset') {
      $self->reset();
      print "Rotars reset\n";
    } elsif ($command eq 'plugs') {
      print "Rotars reset\n" if $args ne '' && $self->set_plugs($args);
      print "Plugboard key: $self->{plugs}{pairs}\n";
    } elsif ($command eq 'show') {
      $self->display();
    } else {
      $self->process_input($line);
    }
  }
}

#!
# @brief Steps the rotars like an odometer.
#
# The first rotar steps on every key press; each rotar that completes a full
# turn carries one step into the next.
#
# @return void
#
sub step_rotors {
  my ($self) = @_;
  for my $rotar (@{ $self->{rotars} }) {
    last unless $rotar->step();   # no full turn, so nothing carries further
  }
}

#!
# @brief Turns every rotar back to its start position.
#
# The plugboard is left alone. Do this before typing ciphertext to decrypt it.
#
# @return void
#
sub reset {
  my ($self) = @_;
  $_->reset() for @{ $self->{rotars} };
}

#!
# @brief Plugs in a new key and resets the rotars, so the machine starts from a known state.
#
# @param pairs Letter pairs, e.g. "AV BS CG".
# @return False if the key was rejected; the previous cables and rotar positions stay as they were.
#
sub set_plugs {
  my ($self, $pairs) = @_;
  return 0 unless $self->{plugs}->set_pairs($pairs);
  $self->reset();
  return 1;
}

#!
# @brief Sets where each rotar starts, and turns the rotars there.
#
# @param positions One letter per rotar, rotar I (the fast rotar) first, either case:
#                  "AAA" is all at 0, "BAA" starts rotar I one step on.
# @return False (with a message) unless it is exactly one letter per rotar; the rotars
#         then stay as they were.
#
sub set_positions {
  my ($self, $positions) = @_;
  my @rotars = @{ $self->{rotars} };
  if (length($positions) != @rotars || $positions =~ /[^A-Za-z]/) {
    printf "Enigma: positions \"%s\" must be %d letters, one per rotar\n", $positions, scalar @rotars;
    return 0;
  }
  $rotars[$_]->set_start(main::to_index(substr($positions, $_, 1))) for 0 .. $#rotars;
  return 1;
}

#!
# @brief The rotar start positions as letters.
#
# @return One uppercase letter per rotar, rotar I first, e.g. "AAA".
#
sub positions {
  my ($self) = @_;
  return join '', map { main::to_letter($_->{start}) } @{ $self->{rotars} };
}

#!
# @brief One key press: steps the rotars, then runs the full signal path.
#
# key -> plugboard -> I -> II -> III -> reflector -> III -> II -> I -> plugboard -> lamp
# Prints each stage, so the line reads left to right along that path: ten letters,
# the first being the key typed and the last the lamp.
#
# @param character The key pressed; must be a letter, either case.
# @return The lit lamp (uppercase letter).
#
sub translate_character {
  my ($self, $character) = @_;
  $self->step_rotors();                                   # rotors move before the signal passes through
  my $idx = main::to_index($character);
  my @trace = (main::to_letter($idx));
  $idx = $self->{plugs}->translate_character($idx);
  push @trace, main::to_letter($idx);
  for my $rotar (@{ $self->{rotars} }) {
    $idx = $rotar->translate_character($idx);
    push @trace, main::to_letter($idx);
  }
  $idx = $self->{reflector}->translate_character($idx);
  push @trace, main::to_letter($idx);
  for my $rotar (reverse @{ $self->{rotars} }) {
    $idx = $rotar->reverse_character($idx);
    push @trace, main::to_letter($idx);
  }
  $idx = $self->{plugs}->translate_character($idx);       # same cables on the way out
  push @trace, main::to_letter($idx);
  print join(' => ', @trace), "\n";
  return main::to_letter($idx);
}

package main;

#!
# @brief Starts the machine and its command line.
#
# Usage: perl enigma.pl [--test]
# No option:  plugboard key and rotar start positions from enigma.ini (random key if
#             the ini leaves plugs empty), console cleared once.
# --test:     ignores enigma.ini; fixed plugboard key, positions AAA and no clearing,
#             so every run starts in the same state and its output can be compared
#             with an earlier run.
# enigma.ini is looked for beside this file.
#
# @param argv The command line options.
# @return 0 normally, 1 on an unknown option.
#
sub main {
  my (@argv) = @_;
  my $test_mode = 0;
  for my $option (@argv) {
    if ($option eq '--test') {
      $test_mode = 1;
    } else {
      print "Unknown option: $option\nUsage: $0 [--test]\n";
      return 1;
    }
  }

  $| = 1;   # write output straight away, so the prompt shows before the machine waits for a line
  enable_ansi();
  print "Hello World\n";
  my $key = TEST_KEY;
  my $positions = 'AAA';
  if (!$test_mode) {
    # The ini lives beside this file
    my $config = load_config(File::Spec->catfile(dirname(__FILE__), 'enigma.ini'));
    $key = $config->{plugs};
    $positions = $config->{positions};
  }
  my $enigma = Enigma->new($key, $positions);
  $enigma->run_cli(!$test_mode);
  return 0;
}

exit main(@ARGV) unless caller;

1;
