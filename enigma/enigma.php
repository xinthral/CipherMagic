<?php
/*
  The Enigma machine is a rotor cipher: every key press steps the rotars, so the
  same letter comes out differently each time it is typed.
  This is a port of enigma.cpp, with the same classes, commands and output.

  Signal path for one key press:
    key -> Plugboard -> Rotar I -> II -> III -> Reflector -> III -> II -> I -> Plugboard -> lamp
  Every stage on the way back undoes its partner on the way in, with the Reflector's pairs in
  the middle, so the same settings both encrypt and decrypt.

  Run from the repository root (see the Makefile):
    make phpEnigma                  starts the machine
    php enigma/enigma.php --test    fixed plugboard key and no screen clearing, for repeatable runs

  Starting settings (plugboard key, rotar start positions) come from enigma.ini, which sits
  beside this file and is shared with the other language versions. --test ignores it.
*/

// PHP has a built-in interface called Reflector; the namespace lets this file have its own
namespace Enigma;

const SYMBOL_COUNT = 26;
// 1941 key-sheet example; with it and positions AAA, HELLOWORLD -> TUBEYQMVQC
const TEST_KEY = 'AV BS CG DL FU HZ IN KM OW RX';

/**!
 * @brief Turns on ANSI escape-code support in the Windows console.
 *
 * Windows Terminal and Linux terminals understand escape codes already; the older
 * Windows console (conhost) only does after this is called. The function it uses
 * only exists in PHP for Windows, so this does nothing anywhere else. Call once at startup.
 */
function enableAnsi(): void {
  if (function_exists('sapi_windows_vt100_support')) {
    sapi_windows_vt100_support(STDOUT, true);
  }
}

/**!
 * @brief Clears the console (and its scrollback) and moves the cursor to the top-left.
 *
 * @note Requires enableAnsi() to have been called on Windows.
 */
function clearScreen(): void {
  echo "\033[2J\033[3J\033[H";
}

/**!
 * @brief Splits text into its characters.
 *
 * @param text The text to split.
 * @return An array with one element per character (empty for empty text, which
 *         str_split alone only does from PHP 8.2 on).
 */
function splitChars(string $text): array {
  return ($text === '') ? [] : str_split($text);
}

/**!
 * @brief Checks whether a character is a letter the machine has a key for (A-Z, either case).
 *
 * @param character The character to check.
 * @return True if the character is between 'A' and 'Z' or 'a' and 'z'. Accented letters
 *         have no contact on the rotars and are rejected.
 */
function isLetter(string $character): bool {
  return preg_match('/^[A-Za-z]$/', $character) === 1;
}

/**!
 * @brief Converts a letter to its contact index.
 *
 * @param letter A single letter, either case.
 * @return The index, 'A'/'a' -> 0 ... 'Z'/'z' -> 25.
 */
function toIndex(string $letter): int {
  return ord(strtoupper($letter)) - ord('A');
}

/**!
 * @brief Converts a contact index back to its uppercase letter.
 *
 * @param idx The index, 0-25.
 * @return The letter, 0 -> 'A' ... 25 -> 'Z'.
 */
function toLetter(int $idx): string {
  return chr(ord('A') + $idx);
}

/**!
 * @brief Formats a wiring table the way every display method prints it.
 *
 * @param wiring An array of 26 contact indexes.
 * @return The 26 letters, each followed by a space.
 */
function wiringLine(array $wiring): string {
  $output = '';
  foreach ($wiring as $ele) {
    $output .= toLetter($ele) . ' ';
  }
  return $output;
}

/**!
 * @brief Two-way chaining translation matrix.
 *
 * Receiving input from the Plugboard, each rotar translates an input index and passes it
 * along to the next rotar until it hits the reflector; the rotars then translate the
 * reflected index in reverse order until it reaches the Plugboard again.
 * The wiring never changes; turning the rotar only moves position, which the translate
 * methods apply as an offset. start is where reset() returns it to.
 */
class Rotar {
  // Historical wirings: the letter in slot 1 is where A exits, slot 2 where B exits, and so on
  private const WIRINGS = [
    'EKMFLGDQVZNTOWYHXUSPAIBRCJ',   // I
    'AJDKSIRUXBLHWTMCQGZNPYFVOE',   // II
    'BDFHJLCPRTXVZNYEIWGAKMUSQO',   // III
  ];

  private string $label;
  private int $start = 0;             // position the rotar begins at and resets to (0-25)
  private int $position = 0;          // current position (0-25); a carry happens when it wraps to 0
  private array $ingressArray = [];   // forward wiring: entry contact -> exit contact
  private array $engressArray = [];   // inverse wiring: exit contact -> entry contact

  /**!
   * @brief Builds a rotar with one of the historical wirings, starting at position 0.
   *
   * The inverse wiring is calculated from the forward wiring, so the two can never
   * disagree. Prints a message if the config number is unknown, in which case the
   * rotar has no wiring and must not be used.
   *
   * @param label  Name shown in messages and display(), e.g. "I".
   * @param config Which wiring: 0 = I, 1 = II, 2 = III.
   */
  public function __construct(string $label, int $config) {
    echo "Rotar {$label} Loaded...\n";
    $this->label = $label;
    if ($config >= 0 && $config < count(self::WIRINGS)) {
      $this->ingressArray = array_map(toIndex(...), splitChars(self::WIRINGS[$config]));
      $this->engressArray = array_fill(0, SYMBOL_COUNT, 0);
      foreach ($this->ingressArray as $entryContact => $exitContact) {
        $this->engressArray[$exitContact] = $entryContact;
      }
    } else {
      echo "Rotar {$label}: unknown config {$config} (expected 0-2)\n";
    }
  }

  /**!
   * @brief Prints the forward wiring as 26 letters.
   *
   * The letter in slot 1 is where A exits, slot 2 where B exits, and so on. The
   * wiring is shown as built; the current position is not applied.
   */
  public function display(): void {
    echo "Rotary {$this->label} Configuration\n";
    echo wiringLine($this->ingressArray) . "\n";
  }

  /**!
   * @brief Advances the rotar one position.
   *
   * Only the position changes; the wiring stays fixed, and the translate methods
   * apply the position offset.
   *
   * @return True when the rotar wraps from position 25 back to 0 (carry into the next rotar).
   */
  public function step(): bool {
    $this->position = ($this->position + 1) % SYMBOL_COUNT;
    return $this->position === 0;
  }

  /**!
   * @brief Turns the rotar back to its starting position.
   *
   * Decrypting needs the rotars where they were when encrypting began.
   */
  public function reset(): void {
    $this->position = $this->start;
  }

  /**!
   * @brief Sets the position the rotar begins at, and turns it there.
   *
   * @param start Start position, 0-25 (A = 0 ... Z = 25).
   */
  public function setStart(int $start): void {
    $this->start = $start % SYMBOL_COUNT;
    $this->position = $this->start;
  }

  /**!
   * @brief The position the rotar begins at and resets to.
   *
   * @return Start position, 0-25.
   */
  public function start(): int {
    return $this->start;
  }

  /**!
   * @brief Passes an index forward through the rotar at its current position.
   *
   * The disc turns but the wires don't: the signal enters wire (idx + p), and the
   * wire's exit end has turned p places too, so p is subtracted on the way out.
   * The + SYMBOL_COUNT keeps the result from going negative before the %.
   *
   * @param idx Entry contact, 0-25.
   * @return Exit contact, 0-25.
   */
  public function translateCharacter(int $idx): int {
    $wire = $this->ingressArray[($idx + $this->position) % SYMBOL_COUNT];
    return ($wire - $this->position + SYMBOL_COUNT) % SYMBOL_COUNT;
  }

  /**!
   * @brief Passes an index backward through the rotar at its current position.
   *
   * The return trip after the reflector. Same position offset as translateCharacter,
   * but looked up in the inverse wiring, so for any position
   * reverseCharacter(translateCharacter(x)) === x.
   *
   * @param idx Contact the signal comes back in on (an exit contact of the forward pass), 0-25.
   * @return Contact it leaves on (the matching entry contact of the forward pass), 0-25.
   */
  public function reverseCharacter(int $idx): int {
    $wire = $this->engressArray[($idx + $this->position) % SYMBOL_COUNT];
    return ($wire - $this->position + SYMBOL_COUNT) % SYMBOL_COUNT;
  }
}

/**!
 * @brief Fixed, one-sided translation matrix (historical Reflector B).
 *
 * Sits after the last rotar and sends the signal back through the rotars in reverse.
 * Its wiring is 13 swapped pairs, so it is its own inverse and no letter maps to
 * itself. It never steps and is applied once per key press.
 */
class Reflector {
  // Historical Reflector B
  private const WIRING = 'YRUHQSLDPXNGOKMIEBFZCWVJAT';

  private array $reflection;   // contact -> paired contact, same table both ways

  /**!
   * @brief Loads the Reflector B wiring and checks it.
   *
   * Prints a message for any letter that breaks the two reflector rules: pairs only,
   * and no letter to itself.
   */
  public function __construct() {
    echo "Reflector Loaded...\n";
    $this->reflection = array_map(toIndex(...), splitChars(self::WIRING));
    // A valid reflector is made of pairs (applying it twice gets you back) and never maps a letter to itself
    for ($i = 0; $i < SYMBOL_COUNT; $i++) {
      if ($this->reflection[$this->reflection[$i]] !== $i || $this->reflection[$i] === $i) {
        echo 'Reflector: invalid wiring at ' . toLetter($i) . "\n";
      }
    }
  }

  /**!
   * @brief Prints the reflector wiring as 26 letters.
   *
   * The letter in slot 1 is A's partner, slot 2 is B's partner, and so on.
   */
  public function display(): void {
    echo "Reflector Configuration\n";
    echo wiringLine($this->reflection) . "\n";
  }

  /**!
   * @brief Bounces an index back toward the rotars.
   *
   * No position offset: the reflector doesn't turn.
   *
   * @param idx Contact coming out of the last rotar, 0-25.
   * @return Paired contact to send back through the rotars, 0-25.
   */
  public function translateCharacter(int $idx): int {
    return $this->reflection[$idx];
  }
}

/**!
 * @brief Swapped-pair translation matrix, passed on the way in and on the way out.
 *
 * Each cable swaps two letters (A <-> V); letters without a cable pass through
 * unchanged. Up to 13 cables, 10 was standard. Because it is built from pairs it is
 * its own inverse, so the same table serves both passes.
 */
class Plugboard {
  private string $pairs = '';   // current cables as "AV BS CG ...", reusable as a key
  private array $ingressArray;  // letter -> swapped letter (itself when no cable is plugged)

  /**!
   * @brief Builds a plugboard with 10 random cables.
   *
   * Use setPairs afterwards to plug in a known key instead.
   */
  public function __construct() {
    echo "Plugboard is Loaded...\n";
    $this->ingressArray = range(0, SYMBOL_COUNT - 1);
    $this->randomConfig();
  }

  /**!
   * @brief Prints the key, then the full table as 26 letters.
   *
   * The letter in slot 1 is what A becomes, slot 2 what B becomes, and so on.
   * Unplugged letters show as themselves.
   */
  public function display(): void {
    echo "Plugboard Configuration ({$this->pairs})\n";
    echo wiringLine($this->ingressArray) . "\n";
  }

  /**!
   * @brief Plugs in cables from a key-sheet style string.
   *
   * Builds the table into a scratch copy and only keeps it if every pair is valid,
   * so a typo leaves the previous cables in place.
   *
   * @param pairs Letter pairs, spaces optional, any case: "AV BS CG" or "avbscg".
   * @return False (with a message) on a non-letter, a letter paired with itself, a
   *         letter used twice, or a leftover letter with no partner.
   */
  public function setPairs(string $pairs): bool {
    $table = range(0, SYMBOL_COUNT - 1);   // no cables: every letter maps to itself

    $letters = '';
    foreach (splitChars($pairs) as $character) {
      if (preg_match('/^\s$/', $character) === 1) { continue; }
      if (!isLetter($character)) {
        echo "Plugboard: '{$character}' is not a letter\n";
        return false;
      }
      $letters .= strtoupper($character);
    }
    if (strlen($letters) % 2 !== 0) {
      echo 'Plugboard: ' . $letters[strlen($letters) - 1] . " has no partner\n";
      return false;
    }

    $cleaned = [];
    for ($i = 0; $i < strlen($letters); $i += 2) {
      $pair = substr($letters, $i, 2);
      $a = toIndex($pair[0]);
      $b = toIndex($pair[1]);
      if ($a === $b) {
        echo "Plugboard: {$pair[0]} can't be plugged into itself\n";
        return false;
      }
      if ($table[$a] !== $a || $table[$b] !== $b) {   // already swapped by an earlier cable
        echo "Plugboard: {$pair} reuses a plugged letter\n";
        return false;
      }
      $table[$a] = $b;
      $table[$b] = $a;
      $cleaned[] = $pair;
    }

    $this->ingressArray = $table;
    $this->pairs = implode(' ', $cleaned);
    return true;
  }

  /**!
   * @brief Plugs in random cables.
   *
   * Shuffles the 26 letters and takes neighbours as pairs, (0,1), (2,3), ..., so no
   * letter can land in two cables. Print pairs() to keep the key for decrypting.
   *
   * @param count Number of cables, clamped to 0-13. Defaults to 10.
   */
  public function randomConfig(int $count = 10): void {
    $count = max(0, min($count, intdiv(SYMBOL_COUNT, 2)));
    $letters = array_map(toLetter(...), range(0, SYMBOL_COUNT - 1));
    shuffle($letters);
    $this->setPairs(implode('', array_slice($letters, 0, $count * 2)));
  }

  /**!
   * @brief The current cables as a key string.
   *
   * @return Uppercase pairs separated by spaces, e.g. "AV BS CG"; empty with no cables.
   *         Passing it back to setPairs rebuilds the same plugboard.
   */
  public function pairs(): string {
    return $this->pairs;
  }

  /**!
   * @brief Swaps an index for its cabled partner.
   *
   * Used for both passes, keyboard -> rotars and rotars -> lamp.
   *
   * @param idx Letter index, 0-25.
   * @return The partner's index, or idx itself when the letter has no cable.
   */
  public function translateCharacter(int $idx): int {
    return $this->ingressArray[$idx];
  }
}

/**!
 * @brief The whole machine: a Plugboard, three Rotars and a Reflector, plus the command line.
 *
 * Owns the parts, steps the rotars on each key press and runs the signal through
 * them. Encrypting and decrypting are the same operation: put the machine back in
 * the state it started in (same plugboard key, same start positions, rotars reset) and
 * type the ciphertext.
 *
 * @note Stepping is a plain odometer carry, and there are no ring settings or rotar
 *       order to choose, so output will not match a historical Enigma.
 */
class Enigma {
  private Plugboard $plugs;
  private Reflector $reflector;
  private array $rotars = [];   // rotars[0] is the fast rotar, stepped on every key press

  /**!
   * @brief Builds the machine: rotars I, II, III, Reflector B and a plugboard.
   *
   * Prints the plugboard key and the rotar start positions once, after they are
   * settled, so they can be written down and used later to decrypt.
   *
   * @param key       Plugboard pairs, e.g. "AV BS CG". Empty (the default) keeps the random
   *                  cables the plugboard starts with; so does a key that setPairs rejects.
   * @param positions One start letter per rotar, rotar I first, e.g. "AAA" (the default).
   *                  Empty, or a value setPositions rejects, leaves every rotar at A.
   */
  public function __construct(string $key = '', string $positions = 'AAA') {
    $this->plugs = new Plugboard();
    $this->reflector = new Reflector();
    echo "Enigma is Loaded...\n";
    // Rotars I, II, III (rotars[0] is the fast rotar that steps on every key)
    foreach (['I', 'II', 'III'] as $config => $name) {
      $this->rotars[] = new Rotar($name, $config);
    }
    if ($key !== '') {
      $this->setPlugs($key);
    }
    if ($positions !== '') {
      $this->setPositions($positions);
    }
    echo "Plugboard key: {$this->plugs->pairs()}\n";
    echo "Rotar positions: {$this->positions()}\n";
  }

  /**!
   * @brief Prints the wiring of every part: plugboard, each rotar, then the reflector.
   */
  public function display(): void {
    $this->plugs->display();
    foreach ($this->rotars as $rotar) {
      $rotar->display();
    }
    $this->reflector->display();
  }

  /**!
   * @brief Runs a line of text through the machine and prints the result.
   *
   * Each letter is one key press, so the rotars keep moving from wherever the last
   * line left them. Non-letters are skipped and do not step the rotars. Prints one
   * trace line per letter (see translateCharacter), then "Output:" with the result.
   *
   * @param input Text to encrypt or decrypt, any case.
   */
  public function processInput(string $input): void {
    $output = '';
    foreach (splitChars($input) as $character) {
      if (isLetter($character)) {
        $output .= $this->translateCharacter($character);
      }
    }
    echo "Output: {$output}\n";
  }

  /**!
   * @brief Reads lines until "exit" (or the end of input).
   *
   * Commands:   exit            quit
   *             reset           turn the rotars back to their start positions
   *             plugs           show the plugboard key
   *             plugs AV BS ..  set the plugboard (also resets the rotars)
   *             show            display every part's wiring
   * Any other line is run through the machine; non-letters are skipped.
   * To decrypt: reset (and set the same plugs), then type the ciphertext. In a new
   * run the start positions must match too; those come from enigma.ini.
   * A line that starts with a command word is always taken as the command, so
   * those four words can't begin a message.
   *
   * @param clear True (the default) wipes the console once before the first prompt and
   *              prints the plugboard key and rotar positions again; results stay on
   *              screen after that.
   */
  public function runCLI(bool $clear = true): void {
    $prompt = '>> ';
    if ($clear) {
      clearScreen();                                     // once, so results stay on screen between prompts
      echo "Plugboard key: {$this->plugs->pairs()}\n";   // the startup copy was just cleared
      echo "Rotar positions: {$this->positions()}\n";
    }
    while (true) {
      echo $prompt;
      $line = fgets(STDIN);
      if ($line === false) { break; }                    // end of input
      $line = rtrim($line, "\r\n");                      // drop the trailing newline
      $space = strpos($line, ' ');
      $command = ($space === false) ? $line : substr($line, 0, $space);
      $args = ($space === false) ? '' : substr($line, $space + 1);

      if ($command === 'exit') {
        break;
      } elseif ($command === 'reset') {
        $this->reset();
        echo "Rotars reset\n";
      } elseif ($command === 'plugs') {
        if ($args !== '' && $this->setPlugs($args)) {
          echo "Rotars reset\n";
        }
        echo "Plugboard key: {$this->plugs->pairs()}\n";
      } elseif ($command === 'show') {
        $this->display();
      } else {
        $this->processInput($line);
      }
    }
  }

  /**!
   * @brief Steps the rotars like an odometer.
   *
   * The first rotar steps on every key press; each rotar that completes a full
   * turn carries one step into the next.
   */
  public function stepRotors(): void {
    foreach ($this->rotars as $rotar) {
      if (!$rotar->step()) { break; }   // no full turn, so nothing carries further
    }
  }

  /**!
   * @brief Turns every rotar back to its start position.
   *
   * The plugboard is left alone. Do this before typing ciphertext to decrypt it.
   */
  public function reset(): void {
    foreach ($this->rotars as $rotar) {
      $rotar->reset();
    }
  }

  /**!
   * @brief Plugs in a new key and resets the rotars, so the machine starts from a known state.
   *
   * @param pairs Letter pairs, e.g. "AV BS CG".
   * @return False if the key was rejected; the previous cables and rotar positions stay as they were.
   */
  public function setPlugs(string $pairs): bool {
    if (!$this->plugs->setPairs($pairs)) { return false; }
    $this->reset();
    return true;
  }

  /**!
   * @brief Sets where each rotar starts, and turns the rotars there.
   *
   * @param positions One letter per rotar, rotar I (the fast rotar) first, either case:
   *                  "AAA" is all at 0, "BAA" starts rotar I one step on.
   * @return False (with a message) unless it is exactly one letter per rotar; the rotars
   *         then stay as they were.
   */
  public function setPositions(string $positions): bool {
    $count = count($this->rotars);
    if (strlen($positions) !== $count || preg_match('/[^A-Za-z]/', $positions) === 1) {
      echo "Enigma: positions \"{$positions}\" must be {$count} letters, one per rotar\n";
      return false;
    }
    foreach ($this->rotars as $i => $rotar) {
      $rotar->setStart(toIndex($positions[$i]));
    }
    return true;
  }

  /**!
   * @brief The rotar start positions as letters.
   *
   * @return One uppercase letter per rotar, rotar I first, e.g. "AAA".
   */
  public function positions(): string {
    $output = '';
    foreach ($this->rotars as $rotar) {
      $output .= toLetter($rotar->start());
    }
    return $output;
  }

  /**!
   * @brief One key press: steps the rotars, then runs the full signal path.
   *
   * key -> plugboard -> I -> II -> III -> reflector -> III -> II -> I -> plugboard -> lamp
   * Prints each stage, so the line reads left to right along that path: ten letters,
   * the first being the key typed and the last the lamp.
   *
   * @param character The key pressed; must be a letter, either case.
   * @return The lit lamp (uppercase letter).
   */
  public function translateCharacter(string $character): string {
    $this->stepRotors();                               // rotors move before the signal passes through
    $idx = toIndex($character);
    $trace = [toLetter($idx)];
    $idx = $this->plugs->translateCharacter($idx);
    $trace[] = toLetter($idx);
    foreach ($this->rotars as $rotar) {
      $idx = $rotar->translateCharacter($idx);
      $trace[] = toLetter($idx);
    }
    $idx = $this->reflector->translateCharacter($idx);
    $trace[] = toLetter($idx);
    foreach (array_reverse($this->rotars) as $rotar) {
      $idx = $rotar->reverseCharacter($idx);
      $trace[] = toLetter($idx);
    }
    $idx = $this->plugs->translateCharacter($idx);     // same cables on the way out
    $trace[] = toLetter($idx);
    echo implode(' => ', $trace) . "\n";
    return toLetter($idx);
  }
}

/**!
 * @brief Loads the plugs and positions settings from the shared enigma.ini file.
 *
 * Any setting missing from the file keeps its default value: plugs is empty (random
 * cables) and positions is AAA. A missing file, or one PHP can't parse, gives all defaults.
 *
 * @param path The path to the ini file.
 * @return An array holding plugs and positions.
 */
function loadConfig(string $path): array {
  $config = ['plugs' => '', 'positions' => 'AAA'];
  $parsed = is_readable($path) ? @parse_ini_file($path, false, INI_SCANNER_RAW) : false;
  if ($parsed !== false) {
    foreach (array_keys($config) as $key) {
      if (isset($parsed[$key])) { $config[$key] = trim($parsed[$key]); }
    }
  }
  return $config;
}

/**!
 * @brief Starts the machine and its command line.
 *
 * Usage: php enigma.php [--test]
 * No option:  plugboard key and rotar start positions from enigma.ini (random key if
 *             the ini leaves plugs empty), console cleared once.
 * --test:     ignores enigma.ini; fixed plugboard key, positions AAA and no clearing,
 *             so every run starts in the same state and its output can be compared
 *             with an earlier run.
 * enigma.ini is looked for beside this file.
 *
 * @param argv The command line, script name first.
 * @return 0 normally, 1 on an unknown option.
 */
function main(array $argv): int {
  $testMode = false;
  foreach (array_slice($argv, 1) as $option) {
    if ($option === '--test') {
      $testMode = true;
    } else {
      echo "Unknown option: {$option}\nUsage: {$argv[0]} [--test]\n";
      return 1;
    }
  }

  enableAnsi();
  echo "Hello World\n";
  $key = TEST_KEY;
  $positions = 'AAA';
  if (!$testMode) {
    // The ini lives beside this file
    $config = loadConfig(__DIR__ . '/enigma.ini');
    $key = $config['plugs'];
    $positions = $config['positions'];
  }
  $e = new Enigma($key, $positions);
  $e->runCLI(!$testMode);
  return 0;
}

if (PHP_SAPI === 'cli' && realpath($argv[0]) === __FILE__) {
  exit(main($argv));
}

?>
