/*
  The Enigma machine is a rotor cipher: every key press steps the rotars, so the
  same letter comes out differently each time it is typed.
  This is a port of enigma.cpp, with the same classes, commands and output.

  Signal path for one key press:
    key -> Plugboard -> Rotar I -> II -> III -> Reflector -> III -> II -> I -> Plugboard -> lamp
  Every stage on the way back undoes its partner on the way in, with the Reflector's pairs in
  the middle, so the same settings both encrypt and decrypt.

  Run from the repository root (see the Makefile):
    make jsEnigma                  starts the machine
    node enigma/enigma.js --test   fixed plugboard key and no screen clearing, for repeatable runs

  Starting settings (plugboard key, rotar start positions) come from enigma.ini, which sits
  beside this file and is shared with the other language versions. --test ignores it.
*/
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const SYMBOL_COUNT = 26;
// 1941 key-sheet example; with it and positions AAA, HELLOWORLD -> TUBEYQMVQC
const TEST_KEY = 'AV BS CG DL FU HZ IN KM OW RX';

/**!
 * @brief Clears the console (and its scrollback) and moves the cursor to the top-left.
 *
 * Node turns on escape-code support in the Windows console by itself, so there is
 * nothing to enable first.
 */
function clearScreen() {
  process.stdout.write('\x1b[2J\x1b[3J\x1b[H');
}

/**!
 * @brief Checks whether a character is a letter the machine has a key for (A-Z, either case).
 *
 * @param character The character to check.
 * @return True if the character is between 'A' and 'Z' or 'a' and 'z'. Accented letters
 *         (such as 'É') have no contact on the rotars and are rejected.
 */
function isLetter(character) {
  return /^[A-Za-z]$/.test(character);
}

/**!
 * @brief Converts a letter to its contact index.
 *
 * @param letter A single letter, either case.
 * @return The index, 'A'/'a' -> 0 ... 'Z'/'z' -> 25.
 */
function toIndex(letter) {
  return letter.toUpperCase().charCodeAt(0) - 'A'.charCodeAt(0);
}

/**!
 * @brief Converts a contact index back to its uppercase letter.
 *
 * @param idx The index, 0-25.
 * @return The letter, 0 -> 'A' ... 25 -> 'Z'.
 */
function toLetter(idx) {
  return String.fromCharCode('A'.charCodeAt(0) + idx);
}

/**!
 * @brief Formats a wiring table the way every display method prints it.
 *
 * @param wiring An array of 26 contact indexes.
 * @return The 26 letters, each followed by a space.
 */
function wiringLine(wiring) {
  return wiring.map((ele) => `${toLetter(ele)} `).join('');
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
  constructor(label, config) {
    console.log(`Rotar ${label} Loaded...`);
    this.label = label;
    this.start = 0;           // position the rotar begins at and resets to (0-25)
    this.position = 0;        // current position (0-25); a carry happens when it wraps to 0
    this.ingressArray = [];   // forward wiring: entry contact -> exit contact
    this.engressArray = [];   // inverse wiring: exit contact -> entry contact
    if (Number.isInteger(config) && config >= 0 && config < Rotar.WIRINGS.length) {
      this.ingressArray = Array.from(Rotar.WIRINGS[config], toIndex);
      this.engressArray = new Array(SYMBOL_COUNT).fill(0);
      this.ingressArray.forEach((exitContact, entryContact) => {
        this.engressArray[exitContact] = entryContact;
      });
    } else {
      console.log(`Rotar ${label}: unknown config ${config} (expected 0-2)`);
    }
  }

  /**!
   * @brief Prints the forward wiring as 26 letters.
   *
   * The letter in slot 1 is where A exits, slot 2 where B exits, and so on. The
   * wiring is shown as built; the current position is not applied.
   */
  display() {
    console.log(`Rotary ${this.label} Configuration`);
    console.log(wiringLine(this.ingressArray));
  }

  /**!
   * @brief Advances the rotar one position.
   *
   * Only the position changes; the wiring stays fixed, and the translate methods
   * apply the position offset.
   *
   * @return True when the rotar wraps from position 25 back to 0 (carry into the next rotar).
   */
  step() {
    this.position = (this.position + 1) % SYMBOL_COUNT;
    return this.position === 0;
  }

  /**!
   * @brief Turns the rotar back to its starting position.
   *
   * Decrypting needs the rotars where they were when encrypting began.
   */
  reset() {
    this.position = this.start;
  }

  /**!
   * @brief Sets the position the rotar begins at, and turns it there.
   *
   * @param start Start position, 0-25 (A = 0 ... Z = 25).
   */
  setStart(start) {
    this.start = start % SYMBOL_COUNT;
    this.position = this.start;
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
  translateCharacter(idx) {
    const wire = this.ingressArray[(idx + this.position) % SYMBOL_COUNT];
    return (wire - this.position + SYMBOL_COUNT) % SYMBOL_COUNT;
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
  reverseCharacter(idx) {
    const wire = this.engressArray[(idx + this.position) % SYMBOL_COUNT];
    return (wire - this.position + SYMBOL_COUNT) % SYMBOL_COUNT;
  }
}

// Historical wirings: the letter in slot 1 is where A exits, slot 2 where B exits, and so on
Rotar.WIRINGS = [
  'EKMFLGDQVZNTOWYHXUSPAIBRCJ',   // I
  'AJDKSIRUXBLHWTMCQGZNPYFVOE',   // II
  'BDFHJLCPRTXVZNYEIWGAKMUSQO',   // III
];

/**!
 * @brief Fixed, one-sided translation matrix (historical Reflector B).
 *
 * Sits after the last rotar and sends the signal back through the rotars in reverse.
 * Its wiring is 13 swapped pairs, so it is its own inverse and no letter maps to
 * itself. It never steps and is applied once per key press.
 */
class Reflector {
  /**!
   * @brief Loads the Reflector B wiring and checks it.
   *
   * Prints a message for any letter that breaks the two reflector rules: pairs only,
   * and no letter to itself.
   */
  constructor() {
    console.log('Reflector Loaded...');
    this.reflection = Array.from(Reflector.WIRING, toIndex);   // contact -> paired contact, same table both ways
    // A valid reflector is made of pairs (applying it twice gets you back) and never maps a letter to itself
    for (let i = 0; i < SYMBOL_COUNT; i++) {
      if (this.reflection[this.reflection[i]] !== i || this.reflection[i] === i) {
        console.log(`Reflector: invalid wiring at ${toLetter(i)}`);
      }
    }
  }

  /**!
   * @brief Prints the reflector wiring as 26 letters.
   *
   * The letter in slot 1 is A's partner, slot 2 is B's partner, and so on.
   */
  display() {
    console.log('Reflector Configuration');
    console.log(wiringLine(this.reflection));
  }

  /**!
   * @brief Bounces an index back toward the rotars.
   *
   * No position offset: the reflector doesn't turn.
   *
   * @param idx Contact coming out of the last rotar, 0-25.
   * @return Paired contact to send back through the rotars, 0-25.
   */
  translateCharacter(idx) {
    return this.reflection[idx];
  }
}

// Historical Reflector B
Reflector.WIRING = 'YRUHQSLDPXNGOKMIEBFZCWVJAT';

/**!
 * @brief Swapped-pair translation matrix, passed on the way in and on the way out.
 *
 * Each cable swaps two letters (A <-> V); letters without a cable pass through
 * unchanged. Up to 13 cables, 10 was standard. Because it is built from pairs it is
 * its own inverse, so the same table serves both passes.
 */
class Plugboard {
  /**!
   * @brief Builds a plugboard with 10 random cables.
   *
   * Use setPairs afterwards to plug in a known key instead.
   */
  constructor() {
    console.log('Plugboard is Loaded...');
    this.pairs = '';                                                   // current cables as "AV BS CG ...", reusable as a key
    this.ingressArray = Array.from({ length: SYMBOL_COUNT }, (_, i) => i);   // letter -> swapped letter (itself when no cable is plugged)
    this.randomConfig();
  }

  /**!
   * @brief Prints the key, then the full table as 26 letters.
   *
   * The letter in slot 1 is what A becomes, slot 2 what B becomes, and so on.
   * Unplugged letters show as themselves.
   */
  display() {
    console.log(`Plugboard Configuration (${this.pairs})`);
    console.log(wiringLine(this.ingressArray));
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
  setPairs(pairs) {
    const table = Array.from({ length: SYMBOL_COUNT }, (_, i) => i);   // no cables: every letter maps to itself

    let letters = '';
    for (const character of pairs) {
      if (/\s/.test(character)) { continue; }
      if (!isLetter(character)) {
        console.log(`Plugboard: '${character}' is not a letter`);
        return false;
      }
      letters += character.toUpperCase();
    }
    if (letters.length % 2 !== 0) {
      console.log(`Plugboard: ${letters[letters.length - 1]} has no partner`);
      return false;
    }

    const cleaned = [];
    for (let i = 0; i < letters.length; i += 2) {
      const pair = letters.slice(i, i + 2);
      const a = toIndex(pair[0]);
      const b = toIndex(pair[1]);
      if (a === b) {
        console.log(`Plugboard: ${pair[0]} can't be plugged into itself`);
        return false;
      }
      if (table[a] !== a || table[b] !== b) {   // already swapped by an earlier cable
        console.log(`Plugboard: ${pair} reuses a plugged letter`);
        return false;
      }
      table[a] = b;
      table[b] = a;
      cleaned.push(pair);
    }

    this.ingressArray = table;
    this.pairs = cleaned.join(' ');
    return true;
  }

  /**!
   * @brief Plugs in random cables.
   *
   * Shuffles the 26 letters and takes neighbours as pairs, (0,1), (2,3), ..., so no
   * letter can land in two cables. Print the pairs property to keep the key for decrypting.
   *
   * @param count Number of cables, clamped to 0-13. Defaults to 10.
   */
  randomConfig(count = 10) {
    const cables = Math.max(0, Math.min(count, SYMBOL_COUNT / 2));
    const letters = Array.from({ length: SYMBOL_COUNT }, (_, i) => toLetter(i));
    for (let i = letters.length - 1; i > 0; i--) {   // Fisher-Yates shuffle
      const j = Math.floor(Math.random() * (i + 1));
      [letters[i], letters[j]] = [letters[j], letters[i]];
    }
    this.setPairs(letters.slice(0, cables * 2).join(''));
  }

  /**!
   * @brief Swaps an index for its cabled partner.
   *
   * Used for both passes, keyboard -> rotars and rotars -> lamp.
   *
   * @param idx Letter index, 0-25.
   * @return The partner's index, or idx itself when the letter has no cable.
   */
  translateCharacter(idx) {
    return this.ingressArray[idx];
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
  constructor(key = '', positions = 'AAA') {
    this.plugs = new Plugboard();
    this.reflector = new Reflector();
    console.log('Enigma is Loaded...');
    // Rotars I, II, III (rotars[0] is the fast rotar that steps on every key)
    this.rotars = ['I', 'II', 'III'].map((name, config) => new Rotar(name, config));
    if (key) {
      this.setPlugs(key);
    }
    if (positions) {
      this.setPositions(positions);
    }
    console.log(`Plugboard key: ${this.plugs.pairs}`);
    console.log(`Rotar positions: ${this.positions()}`);
  }

  /**!
   * @brief Prints the wiring of every part: plugboard, each rotar, then the reflector.
   */
  display() {
    this.plugs.display();
    for (const rotar of this.rotars) {
      rotar.display();
    }
    this.reflector.display();
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
  processInput(input) {
    let output = '';
    for (const character of input) {
      if (isLetter(character)) {
        output += this.translateCharacter(character);
      }
    }
    console.log(`Output: ${output}`);
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
   * Node reads input as events rather than by waiting, so this is an async method:
   * it returns a promise that settles when the command line ends.
   *
   * @param clear True (the default) wipes the console once before the first prompt and
   *              prints the plugboard key and rotar positions again; results stay on
   *              screen after that.
   */
  async runCLI(clear = true) {
    const prompt = '>> ';
    if (clear) {
      clearScreen();                                        // once, so results stay on screen between prompts
      console.log(`Plugboard key: ${this.plugs.pairs}`);    // the startup copy was just cleared
      console.log(`Rotar positions: ${this.positions()}`);
    }
    const reader = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
    process.stdout.write(prompt);
    for await (const line of reader) {
      const space = line.indexOf(' ');
      const command = (space === -1) ? line : line.slice(0, space);
      const args = (space === -1) ? '' : line.slice(space + 1);

      if (command === 'exit') {
        break;
      } else if (command === 'reset') {
        this.reset();
        console.log('Rotars reset');
      } else if (command === 'plugs') {
        if (args && this.setPlugs(args)) {
          console.log('Rotars reset');
        }
        console.log(`Plugboard key: ${this.plugs.pairs}`);
      } else if (command === 'show') {
        this.display();
      } else {
        this.processInput(line);
      }
      process.stdout.write(prompt);
    }
    reader.close();
  }

  /**!
   * @brief Steps the rotars like an odometer.
   *
   * The first rotar steps on every key press; each rotar that completes a full
   * turn carries one step into the next.
   */
  stepRotors() {
    for (const rotar of this.rotars) {
      if (!rotar.step()) { break; }   // no full turn, so nothing carries further
    }
  }

  /**!
   * @brief Turns every rotar back to its start position.
   *
   * The plugboard is left alone. Do this before typing ciphertext to decrypt it.
   */
  reset() {
    for (const rotar of this.rotars) {
      rotar.reset();
    }
  }

  /**!
   * @brief Plugs in a new key and resets the rotars, so the machine starts from a known state.
   *
   * @param pairs Letter pairs, e.g. "AV BS CG".
   * @return False if the key was rejected; the previous cables and rotar positions stay as they were.
   */
  setPlugs(pairs) {
    if (!this.plugs.setPairs(pairs)) { return false; }
    this.reset();
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
  setPositions(positions) {
    if (positions.length !== this.rotars.length || !Array.from(positions).every(isLetter)) {
      console.log(`Enigma: positions "${positions}" must be ${this.rotars.length} letters, one per rotar`);
      return false;
    }
    this.rotars.forEach((rotar, i) => rotar.setStart(toIndex(positions[i])));
    return true;
  }

  /**!
   * @brief The rotar start positions as letters.
   *
   * @return One uppercase letter per rotar, rotar I first, e.g. "AAA".
   */
  positions() {
    return this.rotars.map((rotar) => toLetter(rotar.start)).join('');
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
  translateCharacter(character) {
    this.stepRotors();                                // rotors move before the signal passes through
    let idx = toIndex(character);
    const trace = [toLetter(idx)];
    idx = this.plugs.translateCharacter(idx);
    trace.push(toLetter(idx));
    for (const rotar of this.rotars) {
      idx = rotar.translateCharacter(idx);
      trace.push(toLetter(idx));
    }
    idx = this.reflector.translateCharacter(idx);
    trace.push(toLetter(idx));
    for (let i = this.rotars.length - 1; i >= 0; i--) {
      idx = this.rotars[i].reverseCharacter(idx);
      trace.push(toLetter(idx));
    }
    idx = this.plugs.translateCharacter(idx);         // same cables on the way out
    trace.push(toLetter(idx));
    console.log(trace.join(' => '));
    return toLetter(idx);
  }
}

/**!
 * @brief Loads the plugs and positions settings from the shared enigma.ini file.
 *
 * Reads simple key = value lines, skipping blank lines, comments (; or #), and
 * [section] headers. Any setting missing from the file keeps its default value:
 * plugs is empty (random cables) and positions is AAA. A missing file gives all defaults.
 *
 * @param file The path to the ini file.
 * @return An object holding plugs and positions.
 */
function loadConfig(file) {
  const config = { plugs: '', positions: 'AAA' };
  let text = '';
  try { text = fs.readFileSync(file, 'utf8'); } catch (err) { return config; }
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith(';') || line.startsWith('#') || line.startsWith('[')) { continue; }
    const eq = line.indexOf('=');
    if (eq === -1) { continue; }
    const key = line.slice(0, eq).trim();
    if (key in config) { config[key] = line.slice(eq + 1).trim(); }
  }
  return config;
}

/**!
 * @brief Starts the machine and its command line.
 *
 * Usage: node enigma.js [--test]
 * No option:  plugboard key and rotar start positions from enigma.ini (random key if
 *             the ini leaves plugs empty), console cleared once.
 * --test:     ignores enigma.ini; fixed plugboard key, positions AAA and no clearing,
 *             so every run starts in the same state and its output can be compared
 *             with an earlier run.
 * enigma.ini is looked for beside this file.
 *
 * @param argv The command line options (without node and the script name).
 * @return A promise for the exit code: 0 normally, 1 on an unknown option.
 */
async function main(argv) {
  let testMode = false;
  for (const option of argv) {
    if (option === '--test') {
      testMode = true;
    } else {
      console.log(`Unknown option: ${option}\nUsage: node ${path.basename(__filename)} [--test]`);
      return 1;
    }
  }

  console.log('Hello World');
  let key = TEST_KEY;
  let positions = 'AAA';
  if (!testMode) {
    // The ini lives beside this file
    const config = loadConfig(path.join(__dirname, 'enigma.ini'));
    key = config.plugs;
    positions = config.positions;
  }
  const e = new Enigma(key, positions);
  await e.runCLI(!testMode);
  return 0;
}

if (require.main === module) {
  // exitCode rather than process.exit(), so output still in the pipe is not cut off
  main(process.argv.slice(2)).then((code) => { process.exitCode = code; });
}

module.exports = { Rotar, Reflector, Plugboard, Enigma, loadConfig };
