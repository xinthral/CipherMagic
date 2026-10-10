'''
  The Enigma machine is a rotor cipher: every key press steps the rotars, so the
  same letter comes out differently each time it is typed.
  This is a port of enigma.cpp, with the same classes, commands and output.

  Signal path for one key press:
    key -> Plugboard -> Rotar I -> II -> III -> Reflector -> III -> II -> I -> Plugboard -> lamp
  Every stage on the way back undoes its partner on the way in, with the Reflector's pairs in
  the middle, so the same settings both encrypt and decrypt.

  Run from the repository root (see the Makefile):
    make pyEnigma                     starts the machine
    python3 enigma/enigma.py --test   fixed plugboard key and no screen clearing, for repeatable runs

  Starting settings (plugboard key, rotar start positions) come from enigma.ini, which sits
  beside this file and is shared with the other language versions. --test ignores it.
'''
import configparser
import os
import random
import sys

SYMBOL_COUNT: int = 26
TEST_KEY: str = 'AV BS CG DL FU HZ IN KM OW RX'   # 1941 key-sheet example; with it and positions AAA, HELLOWORLD -> TUBEYQMVQC

def enableAnsi() -> None:
  """
  Turns on ANSI escape-code support in the Windows console.

  Parameters:
  - None: The function does not take any parameters.

  Returns:
  - None: The function does not return any value.

  Windows Terminal and Linux terminals understand escape codes already; the older
  Windows console (conhost) only does after a call into the system shell.
  Does nothing on Linux. Call once at startup.
  """
  if os.name == 'nt':
    os.system('')

def clearScreen() -> None:
  """
  Clears the console (and its scrollback) and moves the cursor to the top-left.

  Parameters:
  - None: The function does not take any parameters.

  Returns:
  - None: The function does not return any value.

  Requires enableAnsi() to have been called on Windows.
  """
  print('\033[2J\033[3J\033[H', end='', flush=True)

def isLetter(character: str) -> bool:
  """
  Checks whether a character is a letter the machine has a key for (A-Z, either case).

  Parameters:
  - character (str): The character to check.

  Returns:
  - bool: True if the character is between 'A' and 'Z' or 'a' and 'z'.

  Unlike str.isalpha(), this rejects accented letters (such as 'É') that have no
  contact on the rotars.
  """
  return character.isascii() and character.isalpha()

def toIndex(letter: str) -> int:
  """
  Converts a letter to its contact index.

  Parameters:
  - letter (str): A single letter, either case.

  Returns:
  - int: The index, 'A'/'a' -> 0 ... 'Z'/'z' -> 25.
  """
  return ord(letter.upper()) - ord('A')

def toLetter(idx: int) -> str:
  """
  Converts a contact index back to its uppercase letter.

  Parameters:
  - idx (int): The index, 0-25.

  Returns:
  - str: The letter, 0 -> 'A' ... 25 -> 'Z'.
  """
  return chr(ord('A') + idx)

class Rotar:
  # Historical wirings: the letter in slot 1 is where A exits, slot 2 where B exits, and so on
  WIRINGS: list[str] = [
    'EKMFLGDQVZNTOWYHXUSPAIBRCJ',   # I
    'AJDKSIRUXBLHWTMCQGZNPYFVOE',   # II
    'BDFHJLCPRTXVZNYEIWGAKMUSQO',   # III
  ]

  def __init__(self, label: str, config: int) -> None:
    """
    Builds a rotar with one of the historical wirings, starting at position 0.

    Parameters:
    - label (str): Name shown in messages and display(), e.g. "I".
    - config (int): Which wiring: 0 = I, 1 = II, 2 = III.

    Returns:
    - None: The function does not return any value.

    The __init__ method initializes the following attributes:
    - label: The name of the rotar.
    - start: Position the rotar begins at and resets to (0-25).
    - position: Current position (0-25); a carry happens when it wraps to 0.
    - ingressArray: Forward wiring, entry contact -> exit contact.
    - engressArray: Inverse wiring, exit contact -> entry contact.

    The wiring never changes; turning the rotar only moves position, which the
    translate functions apply as an offset. start is where reset() returns it to.
    The inverse wiring is calculated from
    the forward wiring, so the two can never disagree. Prints a message if the
    config number is unknown, in which case the rotar has no wiring and must not be used.
    """
    print(f"Rotar {label} Loaded...")
    self.label: str = label
    self.start: int = 0
    self.position: int = 0
    self.ingressArray: list[int] = []
    self.engressArray: list[int] = []
    if 0 <= config < len(self.WIRINGS):
      self.ingressArray = [toIndex(letter) for letter in self.WIRINGS[config]]
      self.engressArray = [0] * SYMBOL_COUNT
      for entryContact, exitContact in enumerate(self.ingressArray):
        self.engressArray[exitContact] = entryContact
    else:
      print(f"Rotar {label}: unknown config {config} (expected 0-2)")

  def display(self) -> None:
    """
    Prints the forward wiring as 26 letters.

    Parameters:
    - None: The function does not take any parameters.

    Returns:
    - None: The function does not return any value.

    The letter in slot 1 is where A exits, slot 2 where B exits, and so on. The
    wiring is shown as built; the current position is not applied.
    """
    print(f"Rotary {self.label} Configuration")
    print(''.join(f"{toLetter(ele)} " for ele in self.ingressArray))

  def step(self) -> bool:
    """
    Advances the rotar one position.

    Parameters:
    - None: The function does not take any parameters.

    Returns:
    - bool: True when the rotar wraps from position 25 back to 0 (carry into the next rotar).

    Only the position changes; the wiring stays fixed, and the translate functions
    apply the position offset.
    """
    self.position = (self.position + 1) % SYMBOL_COUNT
    return self.position == 0

  def reset(self) -> None:
    """
    Turns the rotar back to its starting position.

    Parameters:
    - None: The function does not take any parameters.

    Returns:
    - None: The function does not return any value.

    Decrypting needs the rotars where they were when encrypting began.
    """
    self.position = self.start

  def setStart(self, start: int) -> None:
    """
    Sets the position the rotar begins at, and turns it there.

    Parameters:
    - start (int): Start position, 0-25 (A = 0 ... Z = 25).

    Returns:
    - None: The function does not return any value.
    """
    self.start = start % SYMBOL_COUNT
    self.position = self.start

  def translateCharacter(self, idx: int) -> int:
    """
    Passes an index forward through the rotar at its current position.

    Parameters:
    - idx (int): Entry contact, 0-25.

    Returns:
    - int: Exit contact, 0-25.

    The disc turns but the wires don't: the signal enters wire (idx + p), and the
    wire's exit end has turned p places too, so p is subtracted on the way out.
    """
    wire: int = self.ingressArray[(idx + self.position) % SYMBOL_COUNT]
    return (wire - self.position) % SYMBOL_COUNT

  def reverseCharacter(self, idx: int) -> int:
    """
    Passes an index backward through the rotar at its current position.

    Parameters:
    - idx (int): Contact the signal comes back in on (an exit contact of the forward pass), 0-25.

    Returns:
    - int: Contact it leaves on (the matching entry contact of the forward pass), 0-25.

    The return trip after the reflector. Same position offset as translateCharacter,
    but looked up in the inverse wiring, so for any position
    reverseCharacter(translateCharacter(x)) == x.
    """
    wire: int = self.engressArray[(idx + self.position) % SYMBOL_COUNT]
    return (wire - self.position) % SYMBOL_COUNT

class Reflector:
  WIRING: str = 'YRUHQSLDPXNGOKMIEBFZCWVJAT'   # historical Reflector B

  def __init__(self) -> None:
    """
    Loads the historical Reflector B wiring and checks it.

    Parameters:
    - None: The function does not take any parameters.

    Returns:
    - None: The function does not return any value.

    The __init__ method initializes the following attributes:
    - reflection: Contact -> paired contact, the same table both ways.

    The reflector sits after the last rotar and sends the signal back through the
    rotars in reverse. Its wiring is 13 swapped pairs, so it is its own inverse and
    no letter maps to itself. It never steps and is applied once per key press.
    Prints a message for any letter that breaks those two rules.
    """
    print('Reflector Loaded...')
    self.reflection: list[int] = [toIndex(letter) for letter in self.WIRING]
    # A valid reflector is made of pairs (applying it twice gets you back) and never maps a letter to itself
    for i in range(SYMBOL_COUNT):
      if self.reflection[self.reflection[i]] != i or self.reflection[i] == i:
        print(f"Reflector: invalid wiring at {toLetter(i)}")

  def display(self) -> None:
    """
    Prints the reflector wiring as 26 letters.

    Parameters:
    - None: The function does not take any parameters.

    Returns:
    - None: The function does not return any value.

    The letter in slot 1 is A's partner, slot 2 is B's partner, and so on.
    """
    print('Reflector Configuration')
    print(''.join(f"{toLetter(ele)} " for ele in self.reflection))

  def translateCharacter(self, idx: int) -> int:
    """
    Bounces an index back toward the rotars.

    Parameters:
    - idx (int): Contact coming out of the last rotar, 0-25.

    Returns:
    - int: Paired contact to send back through the rotars, 0-25.

    No position offset: the reflector doesn't turn.
    """
    return self.reflection[idx]

class Plugboard:
  def __init__(self) -> None:
    """
    Builds a plugboard with 10 random cables.

    Parameters:
    - None: The function does not take any parameters.

    Returns:
    - None: The function does not return any value.

    The __init__ method initializes the following attributes:
    - pairs: The current cables as "AV BS CG ...", reusable as a key.
    - ingressArray: Letter -> swapped letter (itself when no cable is plugged).

    Each cable swaps two letters (A <-> V); letters without a cable pass through
    unchanged. Up to 13 cables, 10 was standard. Because it is built from pairs it is
    its own inverse, so the same table serves both passes. Use setPairs afterwards to
    plug in a known key instead.
    """
    print('Plugboard is Loaded...')
    self.pairs: str = ''
    self.ingressArray: list[int] = list(range(SYMBOL_COUNT))
    self.randomConfig()

  def display(self) -> None:
    """
    Prints the key, then the full table as 26 letters.

    Parameters:
    - None: The function does not take any parameters.

    Returns:
    - None: The function does not return any value.

    The letter in slot 1 is what A becomes, slot 2 what B becomes, and so on.
    Unplugged letters show as themselves.
    """
    print(f"Plugboard Configuration ({self.pairs})")
    print(''.join(f"{toLetter(ele)} " for ele in self.ingressArray))

  def setPairs(self, pairs: str) -> bool:
    """
    Plugs in cables from a key-sheet style string.

    Parameters:
    - pairs (str): Letter pairs, spaces optional, any case: "AV BS CG" or "avbscg".

    Returns:
    - bool: False (with a message) on a non-letter, a letter paired with itself, a letter
      used twice, or a leftover letter with no partner.

    Builds the table into a scratch copy and only keeps it if every pair is valid,
    so a typo leaves the previous cables in place.
    """
    table: list[int] = list(range(SYMBOL_COUNT))   # no cables: every letter maps to itself

    letters: str = ''
    for character in pairs:
      if character.isspace():
        continue
      if not isLetter(character):
        print(f"Plugboard: '{character}' is not a letter")
        return False
      letters += character.upper()
    if len(letters) % 2 != 0:
      print(f"Plugboard: {letters[-1]} has no partner")
      return False

    cleaned: list[str] = []
    for i in range(0, len(letters), 2):
      a: int = toIndex(letters[i])
      b: int = toIndex(letters[i + 1])
      if a == b:
        print(f"Plugboard: {letters[i]} can't be plugged into itself")
        return False
      if table[a] != a or table[b] != b:   # already swapped by an earlier cable
        print(f"Plugboard: {letters[i:i + 2]} reuses a plugged letter")
        return False
      table[a] = b
      table[b] = a
      cleaned.append(letters[i:i + 2])

    self.ingressArray = table
    self.pairs = ' '.join(cleaned)
    return True

  def randomConfig(self, count: int = 10) -> None:
    """
    Plugs in random cables.

    Parameters:
    - count (int): Number of cables, clamped to 0-13.

    Returns:
    - None: The function does not return any value.

    Shuffles the 26 letters and takes neighbours as pairs, (0,1), (2,3), ..., so no
    letter can land in two cables. Print the pairs attribute to keep the key for decrypting.
    """
    count = max(0, min(count, SYMBOL_COUNT // 2))
    letters: list[int] = list(range(SYMBOL_COUNT))
    random.shuffle(letters)
    self.setPairs(''.join(toLetter(idx) for idx in letters[:count * 2]))

  def translateCharacter(self, idx: int) -> int:
    """
    Swaps an index for its cabled partner.

    Parameters:
    - idx (int): Letter index, 0-25.

    Returns:
    - int: The partner's index, or idx itself when the letter has no cable.

    Used for both passes, keyboard -> rotars and rotars -> lamp.
    """
    return self.ingressArray[idx]

class Enigma:
  def __init__(self, key: str = '', positions: str = 'AAA') -> None:
    """
    Builds the machine: rotars I, II, III, Reflector B and a plugboard.

    Parameters:
    - key (str): Plugboard pairs, e.g. "AV BS CG". Empty (the default) keeps the random
      cables the plugboard starts with; so does a key that setPairs rejects.
    - positions (str): One start letter per rotar, rotar I first, e.g. "AAA" (the default).
      Empty, or a value setPositions rejects, leaves every rotar at A.

    Returns:
    - None: The function does not return any value.

    The __init__ method initializes the following attributes:
    - plugs: The Plugboard.
    - reflector: The Reflector.
    - rotars: The three Rotars; rotars[0] is the fast rotar, stepped on every key press.

    Encrypting and decrypting are the same operation: put the machine back in the
    state it started in (same plugboard key, same start positions, rotars reset) and
    type the ciphertext. Prints the plugboard key and the rotar start positions once,
    after they are settled, so they can be written down and used later to decrypt.

    Stepping is a plain odometer carry, and there are no ring settings or rotar
    order to choose, so output will not match a historical Enigma.
    """
    self.plugs: Plugboard = Plugboard()
    self.reflector: Reflector = Reflector()
    print('Enigma is Loaded...')
    self.rotars: list[Rotar] = [Rotar(name, config) for config, name in enumerate(['I', 'II', 'III'])]
    if key:
      self.setPlugs(key)
    if positions:
      self.setPositions(positions)
    print(f"Plugboard key: {self.plugs.pairs}")
    print(f"Rotar positions: {self.positions()}")

  def display(self) -> None:
    """
    Prints the wiring of every part: plugboard, each rotar, then the reflector.

    Parameters:
    - None: The function does not take any parameters.

    Returns:
    - None: The function does not return any value.
    """
    self.plugs.display()
    for rotar in self.rotars:
      rotar.display()
    self.reflector.display()

  def processInput(self, text: str) -> None:
    """
    Runs a line of text through the machine and prints the result.

    Parameters:
    - text (str): Text to encrypt or decrypt, any case.

    Returns:
    - None: The function does not return any value.

    Each letter is one key press, so the rotars keep moving from wherever the last
    line left them. Non-letters are skipped and do not step the rotars. Prints one
    trace line per letter (see translateCharacter), then "Output:" with the result.
    """
    output: str = ''
    for character in text:
      if isLetter(character):
        output += self.translateCharacter(character)
    print(f"Output: {output}")

  def runCLI(self, clear: bool = True) -> None:
    """
    Reads lines until "exit" (or the end of input).

    Parameters:
    - clear (bool): True wipes the console once before the first prompt and prints the
      plugboard key and rotar positions again; results stay on screen after that.

    Returns:
    - None: The function does not return any value.

    Commands:
    - exit: Quit.
    - reset: Turn the rotars back to their start positions.
    - plugs: Show the plugboard key.
    - plugs AV BS ..: Set the plugboard (also resets the rotars).
    - show: Display every part's wiring.

    Any other line is run through the machine; non-letters are skipped.
    To decrypt: reset (and set the same plugs), then type the ciphertext. In a new
    run the start positions must match too; those come from enigma.ini.
    A line that starts with a command word is always taken as the command, so
    those four words can't begin a message.
    """
    prompt: str = '>> '
    if clear:
      clearScreen()                                    # once, so results stay on screen between prompts
      print(f"Plugboard key: {self.plugs.pairs}")      # the startup copy was just cleared
      print(f"Rotar positions: {self.positions()}")
    while True:
      try:
        line: str = input(prompt)
      except EOFError:
        break
      command, _, args = line.partition(' ')

      if command == 'exit':
        break
      elif command == 'reset':
        self.reset()
        print('Rotars reset')
      elif command == 'plugs':
        if args and self.setPlugs(args):
          print('Rotars reset')
        print(f"Plugboard key: {self.plugs.pairs}")
      elif command == 'show':
        self.display()
      else:
        self.processInput(line)

  def stepRotors(self) -> None:
    """
    Steps the rotars like an odometer.

    Parameters:
    - None: The function does not take any parameters.

    Returns:
    - None: The function does not return any value.

    The first rotar steps on every key press; each rotar that completes a full
    turn carries one step into the next.
    """
    for rotar in self.rotars:
      if not rotar.step():
        break   # no full turn, so nothing carries further

  def reset(self) -> None:
    """
    Turns every rotar back to its start position.

    Parameters:
    - None: The function does not take any parameters.

    Returns:
    - None: The function does not return any value.

    The plugboard is left alone. Do this before typing ciphertext to decrypt it.
    """
    for rotar in self.rotars:
      rotar.reset()

  def setPlugs(self, pairs: str) -> bool:
    """
    Plugs in a new key and resets the rotars, so the machine starts from a known state.

    Parameters:
    - pairs (str): Letter pairs, e.g. "AV BS CG".

    Returns:
    - bool: False if the key was rejected; the previous cables and rotar positions stay as they were.
    """
    if not self.plugs.setPairs(pairs):
      return False
    self.reset()
    return True

  def setPositions(self, positions: str) -> bool:
    """
    Sets where each rotar starts, and turns the rotars there.

    Parameters:
    - positions (str): One letter per rotar, rotar I (the fast rotar) first, either case:
      "AAA" is all at 0, "BAA" starts rotar I one step on.

    Returns:
    - bool: False (with a message) unless it is exactly one letter per rotar; the rotars
      then stay as they were.
    """
    if len(positions) != len(self.rotars) or not all(isLetter(character) for character in positions):
      print(f'Enigma: positions "{positions}" must be {len(self.rotars)} letters, one per rotar')
      return False
    for rotar, letter in zip(self.rotars, positions):
      rotar.setStart(toIndex(letter))
    return True

  def positions(self) -> str:
    """
    The rotar start positions as letters.

    Parameters:
    - None: The function does not take any parameters.

    Returns:
    - str: One uppercase letter per rotar, rotar I first, e.g. "AAA".
    """
    return ''.join(toLetter(rotar.start) for rotar in self.rotars)

  def translateCharacter(self, character: str) -> str:
    """
    One key press: steps the rotars, then runs the full signal path.

    Parameters:
    - character (str): The key pressed; must be a letter, either case.

    Returns:
    - str: The lit lamp (uppercase letter).

    key -> plugboard -> I -> II -> III -> reflector -> III -> II -> I -> plugboard -> lamp
    Prints each stage, so the line reads left to right along that path: ten letters,
    the first being the key typed and the last the lamp.
    """
    self.stepRotors()                                  # rotors move before the signal passes through
    idx: int = toIndex(character)
    trace: list[str] = [toLetter(idx)]
    idx = self.plugs.translateCharacter(idx)
    trace.append(toLetter(idx))
    for rotar in self.rotars:
      idx = rotar.translateCharacter(idx)
      trace.append(toLetter(idx))
    idx = self.reflector.translateCharacter(idx)
    trace.append(toLetter(idx))
    for rotar in reversed(self.rotars):
      idx = rotar.reverseCharacter(idx)
      trace.append(toLetter(idx))
    idx = self.plugs.translateCharacter(idx)           # same cables on the way out
    trace.append(toLetter(idx))
    print(' => '.join(trace))
    return toLetter(idx)

def load_config(path: str) -> dict[str, str]:
  """
  Loads the plugs and positions settings from the shared enigma.ini file.

  Parameters:
  - path (str): The path to the ini file.

  Returns:
  - dict[str, str]: The settings, falling back to the defaults for any missing value:
    plugs is empty (random cables) and positions is AAA.

  A missing file gives all defaults. So does a file that can't be parsed, with a message.
  """
  config: dict[str, str] = {'plugs': '', 'positions': 'AAA'}
  parser = configparser.ConfigParser(interpolation=None)
  try:
    if parser.read(path, encoding='utf-8') and parser.has_section('enigma'):
      config.update({key: parser.get('enigma', key) for key in config if parser.has_option('enigma', key)})
  except configparser.Error as error:
    print(f"enigma.ini could not be read, using defaults: {error}")
  return config

def main(argv: list[str]) -> int:
  """
  Starts the machine and its command line.

  Parameters:
  - argv (list[str]): The command line, program name first.

  Returns:
  - int: 0 normally, 1 on an unknown option.

  Usage: enigma.py [--test]
  - No option: plugboard key and rotar start positions from enigma.ini (random key
    if the ini leaves plugs empty), console cleared once.
  - --test: ignores enigma.ini; fixed plugboard key, positions AAA and no clearing,
    so every run starts in the same state and its output can be compared with an
    earlier run.

  enigma.ini is looked for beside this file.

  "make pyEnigma" starts the program with no option; run
  python3 enigma/enigma.py --test yourself for test mode.
  """
  testMode: bool = False
  for option in argv[1:]:
    if option == '--test':
      testMode = True
    else:
      print(f"Unknown option: {option}\nUsage: {argv[0]} [--test]")
      return 1

  enableAnsi()
  print('Hello World')
  key: str = TEST_KEY
  positions: str = 'AAA'
  if not testMode:
    config: dict[str, str] = load_config(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'enigma.ini'))
    key = config['plugs']
    positions = config['positions']
  e = Enigma(key, positions)
  e.runCLI(not testMode)
  return 0

if __name__ == "__main__":
  sys.exit(main(sys.argv))
