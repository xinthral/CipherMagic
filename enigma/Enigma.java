/**!
  The Enigma machine is a rotor cipher: every key press steps the rotars, so the
  same letter comes out differently each time it is typed.
  This is a port of enigma.cpp, with the same classes, commands and output.

  Signal path for one key press:
    key -> Plugboard -> Rotar I -> II -> III -> Reflector -> III -> II -> I -> Plugboard -> lamp
  Every stage on the way back undoes its partner on the way in, with the Reflector's pairs in
  the middle, so the same settings both encrypt and decrypt.

  Build and run from the repository root (see the Makefile):
    make javaEnigma                    compiles the classes into enigma/ and starts the machine
    java -cp enigma Enigma --test      fixed plugboard key and no screen clearing, for repeatable runs

  Starting settings (plugboard key, rotar start positions) come from enigma.ini, which sits
  beside the compiled classes and is shared with the other language versions. --test ignores it.
*/
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Properties;

/**!
  Two-way chaining translation matrix.
  Receiving input from the Plugboard, each rotar translates an input index and passes it
  along to the next rotar until it hits the reflector; the rotars then translate the
  reflected index in reverse order until it reaches the Plugboard again.
  The wiring never changes; turning the rotar only moves position, which the translate
  methods apply as an offset. start is where reset() returns it to.
*/
class Rotar {
  // Historical wirings: the letter in slot 1 is where A exits, slot 2 where B exits, and so on
  private static final String[] WIRINGS = {
    "EKMFLGDQVZNTOWYHXUSPAIBRCJ",   // I
    "AJDKSIRUXBLHWTMCQGZNPYFVOE",   // II
    "BDFHJLCPRTXVZNYEIWGAKMUSQO",   // III
  };

  private final String label;
  private int start = 0;                    // position the rotar begins at and resets to (0-25)
  private int position = 0;                 // current position (0-25); a carry happens when it wraps to 0
  private int[] ingressArray = new int[0];  // forward wiring: entry contact -> exit contact
  private int[] engressArray = new int[0];  // inverse wiring: exit contact -> entry contact

  Rotar(String label, int config) {
    /**!
     * Builds a rotar with one of the historical wirings, starting at position 0.
     * The inverse wiring is calculated from the forward wiring, so the two can never
     * disagree. Prints a message if the config number is unknown, in which case the
     * rotar has no wiring and must not be used.
     * @param label:  Name shown in messages and display(), e.g. "I".
     * @param config: Which wiring: 0 = I, 1 = II, 2 = III.
     */
    System.out.println("Rotar " + label + " Loaded...");
    this.label = label;
    if (config >= 0 && config < WIRINGS.length) {
      ingressArray = Enigma.toWiring(WIRINGS[config]);
      engressArray = new int[Enigma.SYMBOL_COUNT];
      for (int entryContact = 0; entryContact < Enigma.SYMBOL_COUNT; entryContact++) {
        engressArray[ingressArray[entryContact]] = entryContact;
      }
    } else {
      System.out.println("Rotar " + label + ": unknown config " + config + " (expected 0-2)");
    }
  }

  void display() {
    /**!
     * Prints the forward wiring as 26 letters.
     * The letter in slot 1 is where A exits, slot 2 where B exits, and so on. The
     * wiring is shown as built; the current position is not applied.
     */
    System.out.println("Rotary " + label + " Configuration");
    System.out.println(Enigma.wiringLine(ingressArray));
  }

  boolean step() {
    /**!
     * Advances the rotar one position.
     * Only the position changes; the wiring stays fixed, and the translate methods
     * apply the position offset.
     * @return True when the rotar wraps from position 25 back to 0 (carry into the next rotar).
     */
    position = (position + 1) % Enigma.SYMBOL_COUNT;
    return position == 0;
  }

  void reset() {
    /**!
     * Turns the rotar back to its starting position.
     * Decrypting needs the rotars where they were when encrypting began.
     */
    position = start;
  }

  void setStart(int start) {
    /**!
     * Sets the position the rotar begins at, and turns it there.
     * @param start: Start position, 0-25 (A = 0 ... Z = 25).
     */
    this.start = Math.floorMod(start, Enigma.SYMBOL_COUNT);
    position = this.start;
  }

  int getStart() {
    /**!
     * The position the rotar begins at and resets to.
     * @return Start position, 0-25.
     */
    return start;
  }

  int translateCharacter(int idx) {
    /**!
     * Passes an index forward through the rotar at its current position.
     * The disc turns but the wires don't: the signal enters wire (idx + p), and the
     * wire's exit end has turned p places too, so p is subtracted on the way out.
     * floorMod keeps the result from going negative.
     * @param idx: Entry contact, 0-25.
     * @return Exit contact, 0-25.
     */
    int wire = ingressArray[(idx + position) % Enigma.SYMBOL_COUNT];
    return Math.floorMod(wire - position, Enigma.SYMBOL_COUNT);
  }

  int reverseCharacter(int idx) {
    /**!
     * Passes an index backward through the rotar at its current position.
     * The return trip after the reflector. Same position offset as translateCharacter,
     * but looked up in the inverse wiring, so for any position
     * reverseCharacter(translateCharacter(x)) == x.
     * @param idx: Contact the signal comes back in on (an exit contact of the forward pass), 0-25.
     * @return Contact it leaves on (the matching entry contact of the forward pass), 0-25.
     */
    int wire = engressArray[(idx + position) % Enigma.SYMBOL_COUNT];
    return Math.floorMod(wire - position, Enigma.SYMBOL_COUNT);
  }
}

/**!
  Fixed, one-sided translation matrix (historical Reflector B).
  Sits after the last rotar and sends the signal back through the rotars in reverse.
  Its wiring is 13 swapped pairs, so it is its own inverse and no letter maps to
  itself. It never steps and is applied once per key press.
*/
class Reflector {
  private static final String WIRING = "YRUHQSLDPXNGOKMIEBFZCWVJAT";   // historical Reflector B

  private final int[] reflection;   // contact -> paired contact, same table both ways

  Reflector() {
    /**!
     * Loads the Reflector B wiring and checks it.
     * Prints a message for any letter that breaks the two reflector rules: pairs
     * only, and no letter to itself.
     */
    System.out.println("Reflector Loaded...");
    reflection = Enigma.toWiring(WIRING);
    // A valid reflector is made of pairs (applying it twice gets you back) and never maps a letter to itself
    for (int i = 0; i < Enigma.SYMBOL_COUNT; i++) {
      if (reflection[reflection[i]] != i || reflection[i] == i) {
        System.out.println("Reflector: invalid wiring at " + Enigma.toLetter(i));
      }
    }
  }

  void display() {
    /**!
     * Prints the reflector wiring as 26 letters.
     * The letter in slot 1 is A's partner, slot 2 is B's partner, and so on.
     */
    System.out.println("Reflector Configuration");
    System.out.println(Enigma.wiringLine(reflection));
  }

  int translateCharacter(int idx) {
    /**!
     * Bounces an index back toward the rotars.
     * No position offset: the reflector doesn't turn.
     * @param idx: Contact coming out of the last rotar, 0-25.
     * @return Paired contact to send back through the rotars, 0-25.
     */
    return reflection[idx];
  }
}

/**!
  Swapped-pair translation matrix, passed on the way in and on the way out.
  Each cable swaps two letters (A <-> V); letters without a cable pass through
  unchanged. Up to 13 cables, 10 was standard. Because it is built from pairs it is
  its own inverse, so the same table serves both passes.
*/
class Plugboard {
  private String pairs = "";                       // current cables as "AV BS CG ...", reusable as a key
  private int[] ingressArray = identityTable();    // letter -> swapped letter (itself when no cable is plugged)

  Plugboard() {
    /**!
     * Builds a plugboard with 10 random cables.
     * Use setPairs afterwards to plug in a known key instead.
     */
    System.out.println("Plugboard is Loaded...");
    randomConfig(10);
  }

  private static int[] identityTable() {
    /**!
     * Builds a table with no swaps.
     * @return 26 entries where table[i] == i.
     */
    int[] table = new int[Enigma.SYMBOL_COUNT];
    for (int i = 0; i < Enigma.SYMBOL_COUNT; i++) {
      table[i] = i;
    }
    return table;
  }

  void display() {
    /**!
     * Prints the key, then the full table as 26 letters.
     * The letter in slot 1 is what A becomes, slot 2 what B becomes, and so on.
     * Unplugged letters show as themselves.
     */
    System.out.println("Plugboard Configuration (" + pairs + ")");
    System.out.println(Enigma.wiringLine(ingressArray));
  }

  boolean setPairs(String pairs) {
    /**!
     * Plugs in cables from a key-sheet style string.
     * Builds the table into a scratch copy and only keeps it if every pair is valid,
     * so a typo leaves the previous cables in place.
     * @param pairs: Letter pairs, spaces optional, any case: "AV BS CG" or "avbscg".
     * @return False (with a message) on a non-letter, a letter paired with itself, a
     *         letter used twice, or a leftover letter with no partner.
     */
    int[] table = identityTable();   // no cables: every letter maps to itself

    StringBuilder letters = new StringBuilder();
    for (char c : pairs.toCharArray()) {
      if (Character.isWhitespace(c)) { continue; }
      if (!Enigma.isLetter(c)) {
        System.out.println("Plugboard: '" + c + "' is not a letter");
        return false;
      }
      letters.append(Character.toUpperCase(c));
    }
    if (letters.length() % 2 != 0) {
      System.out.println("Plugboard: " + letters.charAt(letters.length() - 1) + " has no partner");
      return false;
    }

    List<String> cleaned = new ArrayList<>();
    for (int i = 0; i < letters.length(); i += 2) {
      String pair = letters.substring(i, i + 2);
      int a = Enigma.toIndex(pair.charAt(0));
      int b = Enigma.toIndex(pair.charAt(1));
      if (a == b) {
        System.out.println("Plugboard: " + pair.charAt(0) + " can't be plugged into itself");
        return false;
      }
      if (table[a] != a || table[b] != b) {   // already swapped by an earlier cable
        System.out.println("Plugboard: " + pair + " reuses a plugged letter");
        return false;
      }
      table[a] = b;
      table[b] = a;
      cleaned.add(pair);
    }

    ingressArray = table;
    this.pairs = String.join(" ", cleaned);
    return true;
  }

  void randomConfig(int count) {
    /**!
     * Plugs in random cables.
     * Shuffles the 26 letters and takes neighbours as pairs, (0,1), (2,3), ..., so no
     * letter can land in two cables. Print getPairs() to keep the key for decrypting.
     * @param count: Number of cables, clamped to 0-13.
     */
    count = Math.max(0, Math.min(count, Enigma.SYMBOL_COUNT / 2));
    List<Character> letters = new ArrayList<>();
    for (int i = 0; i < Enigma.SYMBOL_COUNT; i++) {
      letters.add(Enigma.toLetter(i));
    }
    Collections.shuffle(letters);

    StringBuilder key = new StringBuilder();
    for (int i = 0; i < count * 2; i++) {
      key.append(letters.get(i));
    }
    setPairs(key.toString());
  }

  String getPairs() {
    /**!
     * The current cables as a key string.
     * @return Uppercase pairs separated by spaces, e.g. "AV BS CG"; empty with no cables.
     *         Passing it back to setPairs rebuilds the same plugboard.
     */
    return pairs;
  }

  int translateCharacter(int idx) {
    /**!
     * Swaps an index for its cabled partner.
     * Used for both passes, keyboard -> rotars and rotars -> lamp.
     * @param idx: Letter index, 0-25.
     * @return The partner's index, or idx itself when the letter has no cable.
     */
    return ingressArray[idx];
  }
}

/**!
  The whole machine: a Plugboard, three Rotars and a Reflector, plus the command line.
  Owns the parts, steps the rotars on each key press and runs the signal through
  them. Encrypting and decrypting are the same operation: put the machine back in
  the state it started in (same plugboard key, same start positions, rotars reset) and
  type the ciphertext.
  Stepping is a plain odometer carry, and there are no ring settings or rotar order
  to choose, so output will not match a historical Enigma.
*/
public class Enigma {
  // CLASS SCOPE VARIABLES
  public static final int SYMBOL_COUNT = 26;
  // 1941 key-sheet example; with it and positions AAA, HELLOWORLD -> TUBEYQMVQC
  public static final String TEST_KEY = "AV BS CG DL FU HZ IN KM OW RX";

  private final Plugboard plugs;
  private final Reflector reflector;
  private final Rotar[] rotars;   // rotars[0] is the fast rotar, stepped on every key press

  // HELPER METHODS
  static boolean isLetter(char character) {
    /**!
     * Checks whether a character is a letter the machine has a key for (A-Z, either case).
     * @param character: The character you wish to check.
     * @return True if the character is between 'A' and 'Z' or 'a' and 'z'. Unlike
     *         Character.isLetter, this rejects accented letters (such as 'É') that
     *         have no contact on the rotars.
     */
    return (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z');
  }

  static int toIndex(char letter) {
    /**!
     * Converts a letter to its contact index.
     * @param letter: A letter, either case.
     * @return The index, 'A'/'a' -> 0 ... 'Z'/'z' -> 25.
     */
    return Character.toUpperCase(letter) - 'A';
  }

  static char toLetter(int idx) {
    /**!
     * Converts a contact index back to its uppercase letter.
     * @param idx: The index, 0-25.
     * @return The letter, 0 -> 'A' ... 25 -> 'Z'.
     */
    return (char) ('A' + idx);
  }

  static int[] toWiring(String wiring) {
    /**!
     * Turns a wiring string into an array of contact indexes.
     * @param wiring: 26 letters, e.g. "EKMFLGDQVZNTOWYHXUSPAIBRCJ".
     * @return Entry contact -> exit contact.
     */
    int[] output = new int[wiring.length()];
    for (int i = 0; i < wiring.length(); i++) {
      output[i] = toIndex(wiring.charAt(i));
    }
    return output;
  }

  static String wiringLine(int[] wiring) {
    /**!
     * Formats a wiring table the way every display method prints it.
     * @param wiring: The table to format.
     * @return The letters, each followed by a space.
     */
    StringBuilder output = new StringBuilder();
    for (int ele : wiring) {
      output.append(toLetter(ele)).append(' ');
    }
    return output.toString();
  }

  static void enableAnsi() {
    /**!
     * Turns on ANSI escape-code support in the Windows console.
     * Windows Terminal and Linux terminals understand escape codes already; the older
     * Windows console (conhost) only does after a call into the system shell.
     * Does nothing on Linux. Call once at startup.
     */
    if (!System.getProperty("os.name", "").startsWith("Windows")) { return; }
    try {
      new ProcessBuilder("cmd", "/c", "").inheritIO().start().waitFor();
    } catch (IOException e) {
      // No shell to call; escape codes may show as plain text
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
  }

  static void clearScreen() {
    /**!
     * Clears the console (and its scrollback) and moves the cursor to the top-left.
     * Requires enableAnsi() to have been called on Windows.
     */
    System.out.print("\033[2J\033[3J\033[H");
    System.out.flush();
  }

  // CLASS METHODS
  public Enigma(String key, String positions) {
    /**!
     * Builds the machine: rotars I, II, III, Reflector B and a plugboard.
     * Prints the plugboard key and the rotar start positions once, after they are
     * settled, so they can be written down and used later to decrypt.
     * @param key:       Plugboard pairs, e.g. "AV BS CG". Empty keeps the random cables
     *                   the plugboard starts with; so does a key that setPairs rejects.
     * @param positions: One start letter per rotar, rotar I first, e.g. "AAA". Empty, or
     *                   a value setPositions rejects, leaves every rotar at A.
     */
    plugs = new Plugboard();
    reflector = new Reflector();
    System.out.println("Enigma is Loaded...");
    String[] names = {"I", "II", "III"};
    rotars = new Rotar[names.length];
    for (int i = 0; i < names.length; i++) {
      rotars[i] = new Rotar(names[i], i);
    }
    if (!key.isEmpty()) {
      setPlugs(key);
    }
    if (!positions.isEmpty()) {
      setPositions(positions);
    }
    System.out.println("Plugboard key: " + plugs.getPairs());
    System.out.println("Rotar positions: " + getPositions());
  }

  public void display() {
    /**!
     * Prints the wiring of every part: plugboard, each rotar, then the reflector.
     */
    plugs.display();
    for (Rotar rotar : rotars) {
      rotar.display();
    }
    reflector.display();
  }

  public void processInput(String input) {
    /**!
     * Runs a line of text through the machine and prints the result.
     * Each letter is one key press, so the rotars keep moving from wherever the last
     * line left them. Non-letters are skipped and do not step the rotars. Prints one
     * trace line per letter (see translateCharacter), then "Output:" with the result.
     * @param input: Text to encrypt or decrypt, any case.
     */
    StringBuilder output = new StringBuilder();
    for (char letter : input.toCharArray()) {
      if (isLetter(letter)) {
        output.append(translateCharacter(letter));
      }
    }
    System.out.println("Output: " + output);
  }

  public void runCLI(boolean clear) {
    /**!
     * Reads lines until "exit" (or the end of input).
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
     * @param clear: True wipes the console once before the first prompt and prints the
     *               plugboard key and rotar positions again; results stay on screen after that.
     */
    String prompt = ">> ";
    if (clear) {
      clearScreen();                                              // once, so results stay on screen between prompts
      System.out.println("Plugboard key: " + plugs.getPairs());   // the startup copy was just cleared
      System.out.println("Rotar positions: " + getPositions());
    }
    BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
    while (true) {
      System.out.print(prompt);
      System.out.flush();
      String line;
      try {
        line = reader.readLine();
      } catch (IOException e) {
        break;
      }
      if (line == null) { break; }   // end of input
      int space = line.indexOf(' ');
      String command = space < 0 ? line : line.substring(0, space);
      String args = space < 0 ? "" : line.substring(space + 1);

      if (command.equals("exit")) {
        break;
      } else if (command.equals("reset")) {
        reset();
        System.out.println("Rotars reset");
      } else if (command.equals("plugs")) {
        if (!args.isEmpty() && setPlugs(args)) {
          System.out.println("Rotars reset");
        }
        System.out.println("Plugboard key: " + plugs.getPairs());
      } else if (command.equals("show")) {
        display();
      } else {
        processInput(line);
      }
    }
  }

  public void stepRotors() {
    /**!
     * Steps the rotars like an odometer.
     * The first rotar steps on every key press; each rotar that completes a full
     * turn carries one step into the next.
     */
    for (Rotar rotar : rotars) {
      if (!rotar.step()) { break; }   // no full turn, so nothing carries further
    }
  }

  public void reset() {
    /**!
     * Turns every rotar back to its start position.
     * The plugboard is left alone. Do this before typing ciphertext to decrypt it.
     */
    for (Rotar rotar : rotars) {
      rotar.reset();
    }
  }

  public boolean setPlugs(String pairs) {
    /**!
     * Plugs in a new key and resets the rotars, so the machine starts from a known state.
     * @param pairs: Letter pairs, e.g. "AV BS CG".
     * @return False if the key was rejected; the previous cables and rotar positions
     *         stay as they were.
     */
    if (!plugs.setPairs(pairs)) { return false; }
    reset();
    return true;
  }

  public boolean setPositions(String positions) {
    /**!
     * Sets where each rotar starts, and turns the rotars there.
     * @param positions: One letter per rotar, rotar I (the fast rotar) first, either case:
     *                   "AAA" is all at 0, "BAA" starts rotar I one step on.
     * @return False (with a message) unless it is exactly one letter per rotar; the
     *         rotars then stay as they were.
     */
    boolean valid = positions.length() == rotars.length;
    for (char c : positions.toCharArray()) {
      if (!isLetter(c)) { valid = false; }
    }
    if (!valid) {
      System.out.println("Enigma: positions \"" + positions + "\" must be " + rotars.length + " letters, one per rotar");
      return false;
    }
    for (int i = 0; i < rotars.length; i++) {
      rotars[i].setStart(toIndex(positions.charAt(i)));
    }
    return true;
  }

  public String getPositions() {
    /**!
     * The rotar start positions as letters.
     * @return One uppercase letter per rotar, rotar I first, e.g. "AAA".
     */
    StringBuilder output = new StringBuilder();
    for (Rotar rotar : rotars) {
      output.append(toLetter(rotar.getStart()));
    }
    return output.toString();
  }

  public char translateCharacter(char c) {
    /**!
     * One key press: steps the rotars, then runs the full signal path.
     * key -> plugboard -> I -> II -> III -> reflector -> III -> II -> I -> plugboard -> lamp
     * Prints each stage, so the line reads left to right along that path: ten letters,
     * the first being the key typed and the last the lamp.
     * @param c: The key pressed; must be a letter, either case.
     * @return The lit lamp (uppercase letter).
     */
    stepRotors();                                // rotors move before the signal passes through
    int idx = toIndex(c);
    List<String> trace = new ArrayList<>();
    trace.add(String.valueOf(toLetter(idx)));
    idx = plugs.translateCharacter(idx);
    trace.add(String.valueOf(toLetter(idx)));
    for (Rotar rotar : rotars) {
      idx = rotar.translateCharacter(idx);
      trace.add(String.valueOf(toLetter(idx)));
    }
    idx = reflector.translateCharacter(idx);
    trace.add(String.valueOf(toLetter(idx)));
    for (int i = rotars.length - 1; i >= 0; i--) {
      idx = rotars[i].reverseCharacter(idx);
      trace.add(String.valueOf(toLetter(idx)));
    }
    idx = plugs.translateCharacter(idx);         // same cables on the way out
    trace.add(String.valueOf(toLetter(idx)));
    System.out.println(String.join(" => ", trace));
    return toLetter(idx);
  }

  public static Properties loadConfig() {
    /**!
     * Loads the plugs and positions settings from the shared enigma.ini file,
     * which lives beside Enigma.class. Any setting missing from the file keeps
     * its default value: plugs is empty (random cables) and positions is AAA.
     * A missing file gives all defaults.
     * @return Properties holding plugs and positions.
     */
    Properties defaults = new Properties();
    defaults.setProperty("plugs", "");
    defaults.setProperty("positions", "AAA");
    Properties config = new Properties(defaults);
    try {
      Path dir = Paths.get(Enigma.class.getProtectionDomain().getCodeSource().getLocation().toURI());
      try (Reader reader = new InputStreamReader(Files.newInputStream(dir.resolve("enigma.ini")), StandardCharsets.UTF_8)) {
        config.load(reader);
      }
    } catch (Exception e) {
      // No readable ini; the defaults are used
    }
    return config;
  }

  public static void main(String[] args) {
    /**!
     * Starts the machine and its command line.
     * Usage: java -cp enigma Enigma [--test]
     * No option:  plugboard key and rotar start positions from enigma.ini (random key
     *             if the ini leaves plugs empty), console cleared once.
     * --test:     ignores enigma.ini; fixed plugboard key, positions AAA and no
     *             clearing, so every run starts in the same state and its output can
     *             be compared with an earlier run.
     * Exits with 0 normally, 1 on an unknown option.
     * @param args: The command line options.
     */
    boolean testMode = false;
    for (String option : args) {
      if (option.equals("--test")) {
        testMode = true;
      } else {
        System.out.println("Unknown option: " + option + "\nUsage: java -cp enigma Enigma [--test]");
        System.exit(1);
      }
    }

    enableAnsi();
    System.out.println("Hello World");
    String key = TEST_KEY;
    String positions = "AAA";
    if (!testMode) {
      Properties config = loadConfig();
      key = config.getProperty("plugs").trim();
      positions = config.getProperty("positions").trim();
    }
    Enigma self = new Enigma(key, positions);
    self.runCLI(!testMode);
  }
}
