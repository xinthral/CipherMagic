/**!
 * My first real attempt at a coding an enigma machine
 *
 * Build and run from the repository root:
 *   make cppEnigma            compiles enigma/enigma.o, links cppEnigma.exe and starts it
 *   ./cppEnigma.exe --test    run the built program in test mode (see main)
 *   make clean                removes the object files and executables
 *
 * Starting settings are read from enigma.ini beside this file (see loadConfig and main).
*/
#include "enigma.h"
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX            // keep windows.h from defining min/max macros
#include <windows.h>
#endif

//! *********************** Console *********************** //
void enableAnsi() {
#ifdef _WIN32
  HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
  DWORD mode = 0;
  if (GetConsoleMode(out, &mode)) {
    SetConsoleMode(out, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
  }
#endif
}

void clearScreen() {
  printf("\033[2J\033[3J\033[H");   // clear screen, clear scrollback, cursor home
  fflush(stdout);
}

void rotateVector(std::vector<int>& input) {
  if (!input.empty()) {
    // Left rotate by one: {A, B, C, D} -> {B, C, D, A}
    std::rotate(input.begin(), input.begin() + 1, input.end());
  }
}

//! *********************** Config *********************** //
std::map<std::string, std::string> loadConfig(const std::filesystem::path& path) {
  std::map<std::string, std::string> config = {
    {"plugs", ""}, {"positions", "AAA"}
  };
  auto trim = [](const std::string& s) {
    size_t first = s.find_first_not_of(" \t\r\n");
    size_t last = s.find_last_not_of(" \t\r\n");
    return (first == std::string::npos) ? std::string() : s.substr(first, last - first + 1);
  };
  std::ifstream file(path);
  std::string line;
  while (std::getline(file, line)) {
    line = trim(line);
    if (line.empty() || line[0] == ';' || line[0] == '#' || line[0] == '[') { continue; }
    size_t eq = line.find('=');
    if (eq == std::string::npos) { continue; }
    std::string key = trim(line.substr(0, eq));
    if (config.count(key)) { config[key] = trim(line.substr(eq + 1)); }
  }
  return config;
}

//! *********************** Rotar *********************** //
/**!
 * \brief   Builds a rotar with one of the historical wirings, starting at position 0
 * \details Loads the forward and inverse wiring from selectConfig and converts both from
 *          ASCII to 0-25 indexes. Prints a message if the config number is unknown, in
 *          which case the rotar has no wiring and must not be used.
 * \param   label   Name shown in messages and display(), e.g. "I"
 * \param   config  Which wiring: 0 = I, 1 = II, 2 = III
*/
Rotar::Rotar(std::string label, int config) : _idx(config), _label(label) {
  printf("Rotar %s Loaded...\n", _label.c_str());
  selectConfig(config, ingressArray, engressArray);
  for (int& value : ingressArray) {
    value -= 'A';                           // ASCII -> index: 'A' (65) -> 0 ... 'Z' (90) -> 25
  }
  for (int& value : engressArray) {
    value -= 'A';
  }
  if (ingressArray.size() != 26) {
    printf("Rotar %s: unknown config %d (expected 0-2)\n", _label.c_str(), config);
  }
}

/**!
 * \brief   Builds a rotar from its config number alone, using the number as the label
 * \param   label   Which wiring: 0 = I, 1 = II, 2 = III
*/
Rotar::Rotar(int label) : Rotar(std::to_string(label), label) {}

/**!
 * \brief   Prints the forward wiring as 26 letters
 * \details The letter in slot 1 is where A exits, slot 2 where B exits, and so on. The
 *          wiring is shown as built; the current position is not applied.
*/
void Rotar::display() {
  printf("Rotary %s Configuration\n", _label.c_str());
  for (int ele : ingressArray) {
    printf("%c ", 'A' + ele);
  }
  printf("\n");
}

/**!
 * \brief   Unused: appends a plain rotation (_idx, _idx + 1, ...) to the forward wiring
 * \details An early stand-in from before the historical wirings were added. It appends
 *          rather than replaces and leaves the inverse wiring alone, so calling it on a
 *          built rotar would break it.
*/
void Rotar::setup() {
  for (int i = 0; i < 26; i++) {
    ingressArray.push_back(_idx);
    _idx = (_idx + 1) % 26;
  }
}

/**!
 * \brief   Advances the rotar one position
 * \details Only the position changes; the wiring in ingressArray stays fixed, and
 *          translateCharacter applies the position offset.
 * \return  True when the rotar wraps from position 25 back to 0 (carry into the next rotar).
*/
bool Rotar::step() {
  _position = (_position + 1) % 26;
  return _position == 0;
}

/**!
 * \brief   Turns the rotar back to its starting position
 * \details Decrypting needs the rotars where they were when encrypting began.
*/
void Rotar::reset() {
  _position = _start;
}

/**!
 * \brief   Sets the position the rotar begins at, and turns it there
 * \param   start   Start position, 0-25 (A = 0 ... Z = 25)
*/
void Rotar::setStart(int start) {
  _start = start % 26;
  _position = _start;
}

/**!
 * \brief   The position the rotar begins at and resets to
 * \return  Start position, 0-25
*/
int Rotar::start() {
  return _start;
}

/**!
 * \brief   Passes an index forward through the rotar at its current position
 * \details The disc turns but the wires don't: the signal enters wire (idx + p), and the
 *          wire's exit end has turned p places too, so p is subtracted on the way out.
 *          The + 26 keeps the result from going negative before the % 26.
 * \param   idx     Entry contact, 0-25
 * \return  Exit contact, 0-25
*/
int Rotar::translateCharacter(int idx) {
  int wire = ingressArray.at((idx + _position) % 26);
  return (wire - _position + 26) % 26;
}

/**!
 * \brief   Passes an index backward through the rotar at its current position
 * \details The return trip after the reflector. Same position offset as translateCharacter,
 *          but looked up in the inverse wiring, so for any position
 *          reverseCharacter(translateCharacter(x)) == x.
 * \param   idx     Contact the signal comes back in on (an exit contact of the forward pass), 0-25
 * \return  Contact it leaves on (the matching entry contact of the forward pass), 0-25
*/
int Rotar::reverseCharacter(int idx) {
  int wire = engressArray.at((idx + _position) % 26);
  return (wire - _position + 26) % 26;
}

/**!
 * \brief   Writes a historical rotar wiring and its inverse into the caller's vectors, as ASCII values
 * \param   idx     Which rotar: 0 = I, 1 = II, 2 = III. Any other value leaves both vectors unchanged.
 * \param   output  Replaced with the 26 forward wiring values (entry contact -> exit contact).
 * \param   inverse Replaced with the 26 inverse wiring values (exit contact -> entry contact).
 * \note:   Values are ASCII ('A' = 65 ... 'Z' = 90). Subtract 'A' to get the 0-25 indexes
 *          that ingressArray, engressArray and the translate functions use.
 * \note:   The inverse tables are typed in, not calculated. If a forward table changes, its
 *          inverse must be redone so that inverse[output[i]] == i for every i.
*/
void Rotar::selectConfig(int idx, std::vector<int>& output, std::vector<int>& inverse) {
  static const std::vector<int> rotorI        = {69, 75, 77, 70, 76, 71, 68, 81, 86, 90, 78, 84, 79,  // EKMFLGDQVZNTO
                                                87, 89, 72, 88, 85, 83, 80, 65, 73, 66, 82, 67, 74};  // WYHXUSPAIBRCJ
  static const std::vector<int> rotorII       = {65, 74, 68, 75, 83, 73, 82, 85, 88, 66, 76, 72, 87,  // AJDKSIRUXBLHW
                                                84, 77, 67, 81, 71, 90, 78, 80, 89, 70, 86, 79, 69};  // TMCQGZNPYFVOE
  static const std::vector<int> rotorIII      = {66, 68, 70, 72, 74, 76, 67, 80, 82, 84, 88, 86, 90,  // BDFHJLCPRTXVZ
                                                78, 89, 69, 73, 87, 71, 65, 75, 77, 85, 83, 81, 79};  // NYEIWGAKMUSQO
  static const std::vector<int> rotorI_inv    = {85, 87, 89, 71, 65, 68, 70, 80, 86, 90, 66, 69, 67,  // UWYGADFPVZBEC
                                                75, 77, 84, 72, 88, 83, 76, 82, 73, 78, 81, 79, 74};  // KMTHXSLRINQOJ
  static const std::vector<int> rotorII_inv   = {65, 74, 80, 67, 90, 87, 82, 76, 70, 66, 68, 75, 79,  // AJPCZWRLFBDKO
                                                84, 89, 85, 81, 71, 69, 78, 72, 88, 77, 73, 86, 83};  // TYUQGENHXMIVS
  static const std::vector<int> rotorIII_inv  = {84, 65, 71, 66, 80, 67, 83, 68, 81, 69, 85, 70, 86,  // TAGBPCSDQEUFV
                                                78, 90, 72, 89, 73, 88, 74, 87, 76, 82, 75, 79, 77};  // NZHYIXJWLRKOM

  switch (idx) {
    case 0:
      output = rotorI;
      inverse = rotorI_inv;
      break;
    case 1:
      output = rotorII;
      inverse = rotorII_inv;
      break;
    case 2:
      output = rotorIII;
      inverse = rotorIII_inv;
      break;
    default:
      break;
  }
}

//! *********************** Reflector *********************** //
/**!
 * \brief   Loads the historical Reflector B wiring and checks it
 * \details Converts the wiring from ASCII to 0-25 indexes, then prints a message for any
 *          letter that breaks the two reflector rules: pairs only, and no letter to itself.
*/
Reflector::Reflector() {
  printf("Reflector Loaded...\n");
  reflection = {89, 82, 85, 72, 81, 83, 76, 68, 80, 88, 78, 71, 79,   // YRUHQSLDPXNGO
                75, 77, 73, 69, 66, 70, 90, 67, 87, 86, 74, 65, 84};  // KMIEBFZCWVJAT
  for (int& value : reflection) {
    value -= 'A';                           // ASCII -> index: 'A' (65) -> 0 ... 'Z' (90) -> 25
  }
  // A valid reflector is made of pairs (applying it twice gets you back) and never maps a letter to itself
  for (int i = 0; i < 26; i++) {
    if (reflection[reflection[i]] != i || reflection[i] == i) {
      printf("Reflector: invalid wiring at %c\n", 'A' + i);
    }
  }
}

/**!
 * \brief   Prints the reflector wiring as 26 letters
 * \details The letter in slot 1 is A's partner, slot 2 is B's partner, and so on.
*/
void Reflector::display() {
  printf("Reflector Configuration\n");
  for (int ele : reflection) {
    printf("%c ", 'A' + ele);
  }
  printf("\n");
}

/**!
 * \brief   Bounces an index back toward the rotars
 * \details No position offset: the reflector doesn't turn.
 * \param   idx     Contact coming out of the last rotar, 0-25
 * \return  Paired contact to send back through the rotars, 0-25
*/
int Reflector::translateCharacter(int idx) {
  return reflection.at(idx);
}


//! *********************** Plugboard *********************** //
/**!
 * \brief   Builds a plugboard with 10 random cables
 * \details Use setPairs afterwards to plug in a known key instead.
*/
Plugboard::Plugboard() {
  printf("Plugboard is Loaded...\n");
  randomConfig();
}

/**!
 * \brief   Prints the key, then the full table as 26 letters
 * \details The letter in slot 1 is what A becomes, slot 2 what B becomes, and so on.
 *          Unplugged letters show as themselves.
*/
void Plugboard::display() {
  printf("Plugboard Configuration (%s)\n", _pairs.c_str());
  for (int ele : ingressArray) {
    printf("%c ", 'A' + ele);
  }
  printf("\n");
}

/**!
 * \brief   Plugs in cables from a key-sheet style string
 * \details Builds the table into a scratch copy and only keeps it if every pair is valid,
 *          so a typo leaves the previous cables in place.
 * \param   pairs   Letter pairs, spaces optional, any case: "AV BS CG" or "avbscg"
 * \return  False (with a message) on a non-letter, a letter paired with itself, a letter
 *          used twice, or a leftover letter with no partner.
*/
bool Plugboard::setPairs(std::string pairs) {
  std::vector<int> table(26);
  for (int i = 0; i < 26; i++) {
    table[i] = i;                           // no cables: every letter maps to itself
  }

  std::string letters;
  for (char c : pairs) {
    if (isspace((unsigned char)c)) { continue; }
    if (!isalpha((unsigned char)c)) {
      printf("Plugboard: '%c' is not a letter\n", c);
      return false;
    }
    letters += (char)toupper((unsigned char)c);
  }
  if (letters.size() % 2 != 0) {
    printf("Plugboard: %c has no partner\n", letters.back());
    return false;
  }

  std::string cleaned;
  for (size_t i = 0; i < letters.size(); i += 2) {
    int a = letters[i] - 'A';
    int b = letters[i + 1] - 'A';
    if (a == b) {
      printf("Plugboard: %c can't be plugged into itself\n", letters[i]);
      return false;
    }
    if (table[a] != a || table[b] != b) {   // already swapped by an earlier cable
      printf("Plugboard: %c%c reuses a plugged letter\n", letters[i], letters[i + 1]);
      return false;
    }
    table[a] = b;
    table[b] = a;
    cleaned += cleaned.empty() ? "" : " ";
    cleaned += letters.substr(i, 2);
  }

  ingressArray = table;
  _pairs = cleaned;
  return true;
}

/**!
 * \brief   Plugs in random cables
 * \details Shuffles the 26 letters and takes neighbours as pairs, (0,1), (2,3), ..., so no
 *          letter can land in two cables. Print pairs() to keep the key for decrypting.
 * \param   count   Number of cables, clamped to 0-13
*/
void Plugboard::randomConfig(int count) {
  count = std::max(0, std::min(count, 13));
  std::vector<int> letters(26);
  for (int i = 0; i < 26; i++) {
    letters[i] = i;
  }
  std::random_device rd;
  std::mt19937 r(rd());
  std::shuffle(letters.begin(), letters.end(), r);

  std::string pairs;
  for (int i = 0; i < count * 2; i += 2) {
    pairs += (char)('A' + letters[i]);
    pairs += (char)('A' + letters[i + 1]);
    pairs += ' ';
  }
  setPairs(pairs);
}

/**!
 * \brief   The current cables as a key string
 * \return  Uppercase pairs separated by spaces, e.g. "AV BS CG"; empty with no cables.
 *          Passing it back to setPairs rebuilds the same plugboard.
*/
std::string Plugboard::pairs() {
  return _pairs;
}

/**!
 * \brief   Swaps an index for its cabled partner
 * \details Used for both passes, keyboard -> rotars and rotars -> lamp.
 * \param   idx     Letter index, 0-25
 * \return  The partner's index, or idx itself when the letter has no cable
*/
int Plugboard::translateCharacter(int idx) {
  return ingressArray.at(idx);
}

//! *********************** Enigma *********************** //
/**!
 * \brief   Builds the machine: rotars I, II, III, Reflector B and a plugboard
 * \details Prints the plugboard key and the rotar start positions once, after they are
 *          settled, so they can be written down and used later to decrypt.
 * \param   key         Plugboard pairs, e.g. "AV BS CG". Empty (the default) keeps the random
 *                      cables the plugboard starts with; so does a key that setPairs rejects.
 * \param   positions   One start letter per rotar, rotar I first, e.g. "AAA" (the default).
 *                      Empty, or a value setPositions rejects, leaves every rotar at A.
*/
Enigma::Enigma(std::string key, std::string positions) {
  printf("Enigma is Loaded...\n");
  // Rotars I, II, III (rotars[0] is the fast rotar that steps on every key)
  const char* names[] = {"I", "II", "III"};
  for (int i = 0; i < 3; i++) {
    rotars.emplace_back(names[i], i);
  }
  // The plugboard already holds random cables; a rejected key keeps them (setPairs prints why)
  if (!key.empty()) {
    setPlugs(key);
  }
  if (!positions.empty()) {
    setPositions(positions);
  }
  printf("Plugboard key: %s\n", plugs.pairs().c_str());
  printf("Rotar positions: %s\n", this->positions().c_str());
}

/**!
 * \brief   Prints the wiring of every part: plugboard, each rotar, then the reflector
*/
void Enigma::display() {
  plugs.display();
  for (Rotar r : rotars) {
    r.display();
  }
  reflector.display();
}

/**!
 * \brief   Runs a line of text through the machine and prints the result
 * \details Each letter is one key press, so the rotars keep moving from wherever the last
 *          line left them. Non-letters are skipped and do not step the rotars. Prints one
 *          trace line per letter (see translateCharacter), then "Output:" with the result.
 * \param   input   Text to encrypt or decrypt, any case
*/
void Enigma::processInput(std::string input) {
  std::string output;
  for (char letter : input) {
    if (isalpha(letter)) {
      output += translateCharacter(letter);
    }
  }
  printf("Output: %s\n", output.c_str());
}

/**!
 * \brief   Reads lines until "exit"
 * \details Commands:   exit            quit
 *                      reset           turn the rotars back to their start positions
 *                      plugs           show the plugboard key
 *                      plugs AV BS ..  set the plugboard (also resets the rotars)
 *                      show            display every part's wiring
 *          Any other line is run through the machine; non-letters are skipped.
 *          To decrypt: reset (and set the same plugs), then type the ciphertext. In a new
 *          run the start positions must match too; those come from enigma.ini.
 *          A line that starts with a command word is always taken as the command, so
 *          those four words can't begin a message. Lines are read up to 255 characters.
 * \param   clear   True wipes the console once before the first prompt and prints the
 *                  plugboard key and rotar positions again; results stay on screen after that.
*/
void Enigma::runCLI(bool clear) {
  char buf[256];
  std::string prompt = ">> ";
  if (clear) {
    clearScreen();                          // once, so results stay on screen between prompts
    printf("Plugboard key: %s\n", plugs.pairs().c_str());   // the startup copy was just cleared
    printf("Rotar positions: %s\n", positions().c_str());
  }
  while (true) {
    printf("%s", prompt.c_str());
    fflush(stdout);
    if (!fgets(buf, sizeof(buf), stdin)) { break; }
    std::string line(buf);
    line.erase(line.find_last_not_of("\r\n") + 1);    // drop the trailing newline
    std::string command = line.substr(0, line.find(' '));
    std::string args = command.size() < line.size() ? line.substr(command.size() + 1) : "";

    if (command == "exit") {
      break;
    } else if (command == "reset") {
      reset();
      printf("Rotars reset\n");
    } else if (command == "plugs") {
      if (!args.empty() && setPlugs(args)) {
        printf("Rotars reset\n");
      }
      printf("Plugboard key: %s\n", plugs.pairs().c_str());
    } else if (command == "show") {
      display();
    } else {
      processInput(line);
    }
  }
}

/**!
 * \brief   Steps the rotars like an odometer
 * \details The first rotar steps on every key press; each rotar that completes a full
 *          turn carries one step into the next. Uses references so the real rotars move.
*/
void Enigma::stepRotors() {
  for (Rotar& r : rotars) {
    if (!r.step()) { break; }   // no full turn, so nothing carries further
  }
}

/**!
 * \brief   Turns every rotar back to its start position
 * \details The plugboard is left alone. Do this before typing ciphertext to decrypt it.
*/
void Enigma::reset() {
  for (Rotar& r : rotars) {
    r.reset();
  }
}

/**!
 * \brief   Plugs in a new key and resets the rotars, so the machine starts from a known state
 * \param   pairs   Letter pairs, e.g. "AV BS CG"
 * \return  False if the key was rejected; the previous cables and rotar positions stay as they were
*/
bool Enigma::setPlugs(std::string pairs) {
  if (!plugs.setPairs(pairs)) { return false; }
  reset();
  return true;
}

/**!
 * \brief   Sets where each rotar starts, and turns the rotars there
 * \param   positions   One letter per rotar, rotar I (the fast rotar) first, either case:
 *                      "AAA" is all at 0, "BAA" starts rotar I one step on.
 * \return  False (with a message) unless it is exactly one letter per rotar; the rotars
 *          then stay as they were.
*/
bool Enigma::setPositions(std::string positions) {
  bool valid = positions.size() == rotars.size();
  for (char c : positions) {
    if (!isalpha((unsigned char)c)) { valid = false; }
  }
  if (!valid) {
    printf("Enigma: positions \"%s\" must be %d letters, one per rotar\n", positions.c_str(), (int)rotars.size());
    return false;
  }
  for (size_t i = 0; i < rotars.size(); i++) {
    rotars[i].setStart(toupper((unsigned char)positions[i]) - 'A');
  }
  return true;
}

/**!
 * \brief   The rotar start positions as letters
 * \return  One uppercase letter per rotar, rotar I first, e.g. "AAA"
*/
std::string Enigma::positions() {
  std::string output;
  for (Rotar& r : rotars) {
    output += (char)('A' + r.start());
  }
  return output;
}

/**!
 * \brief   One key press: steps the rotars, then runs the full signal path
 * \details key -> plugboard -> I -> II -> III -> reflector -> III -> II -> I -> plugboard -> lamp
 *          Prints each stage, so the line reads left to right along that path: ten letters,
 *          the first being the key typed and the last the lamp.
 * \param   c       The key pressed; must be a letter, either case
 * \return  The lit lamp (uppercase letter)
*/
char Enigma::translateCharacter(char c) {
  stepRotors();                            // rotors move before the signal passes through
  int idx = toupper(c) - 'A';              // letter -> index: 'A'/'a' -> 0 ... 'Z'/'z' -> 25
  printf("%c => ", 'A' + idx);
  idx = plugs.translateCharacter(idx);
  printf("%c => ", 'A' + idx);
  for (Rotar r: rotars) {
    idx = r.translateCharacter(idx);
    printf("%c => ", 'A' + idx);
  }
  idx = reflector.translateCharacter(idx);
  printf("%c => ", 'A' + idx);
  for (unsigned i = rotars.size(); i-- > 0;) {
    idx = rotars[i].reverseCharacter(idx);
    printf("%c => ", 'A' + idx);
  }
  idx = plugs.translateCharacter(idx);     // same cables on the way out
  printf("%c\n", 'A' + idx);
  return 'A' + idx;
}


//! *********************** main *********************** //
/**!
 * \brief   Starts the machine and its command line
 * \details Usage: cppEnigma.exe [--test]
 *          No option:  plugboard key and rotar start positions from enigma.ini (random key
 *                      if the ini leaves plugs empty), console cleared once.
 *          --test:     ignores enigma.ini; fixed plugboard key, positions AAA and no
 *                      clearing, so every run starts in the same state and its output
 *                      can be compared with an earlier run.
 *          enigma.ini is looked for beside this source file, by the path it was compiled
 *          with, so run the program from the repository root.
 *          "make cppEnigma" builds and then starts the program with no option; run
 *          ./cppEnigma.exe --test yourself for test mode.
 * \return  0 normally, 1 on an unknown option
*/
int main(int argc, char **argv) {
  // --test: don't clear the screen, and use a fixed starting state instead of enigma.ini
  bool testMode = false;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--test") == 0) {
      testMode = true;
    } else {
      printf("Unknown option: %s\nUsage: %s [--test]\n", argv[i], argv[0]);
      return 1;
    }
  }

  enableAnsi();
  printf("Hello World\n");
  // 1941 key-sheet example; with it and positions AAA, HELLOWORLD -> TUBEYQMVQC
  std::string key = "AV BS CG DL FU HZ IN KM OW RX";
  std::string positions = "AAA";
  if (!testMode) {
    // The ini lives beside this source file
    auto config = loadConfig(std::filesystem::path(__FILE__).parent_path() / "enigma.ini");
    key = config["plugs"];
    positions = config["positions"];
  }
  Enigma e(key, positions);
  e.runCLI(!testMode);
}