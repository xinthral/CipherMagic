/**!
 * My first real attempt at a coding an enigma machine
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

//! *********************** Rotar *********************** //
Rotar::Rotar(std::string label, int config) : _idx(config), _label(label) {
  printf("Rotar %s Loaded...\n", _label.c_str());
  selectConfig(config, ingressArray);
  for (int& value : ingressArray) {
    value -= 'A';                           // ASCII -> index: 'A' (65) -> 0 ... 'Z' (90) -> 25
  }
  if (ingressArray.size() != 26) {
    printf("Rotar %s: unknown config %d (expected 0-2)\n", _label.c_str(), config);
  }
}

Rotar::Rotar(int label) : Rotar(std::to_string(label), label) {}

void Rotar::display() {
  printf("Rotary %s Configuration\n", _label.c_str());
  for (int ele : ingressArray) {
    printf("%c ", 'A' + ele);
  }
  printf("\n");
}

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
 * \return  True when the rotar has completed a full turn (carry into the next rotar).
*/
bool Rotar::step() {
  _position = (_position + 1) % 26;
  return _position == 0;
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

int Rotar::reverseCharacter(int idx) {
  // (inverse[(i + p) % 26] - p + 26) % 26
  int _idx = ingressArray[idx];
  return _idx;
}

/**!
 * \brief   Writes a historical rotar wiring into the caller's vector, as ASCII values
 * \param   idx     Which rotar: 0 = I, 1 = II, 2 = III. Any other value leaves output unchanged.
 * \param   output  The vector to fill; it is replaced with the 26 wiring values.
 * \note:   Values are ASCII ('A' = 65 ... 'Z' = 90). Subtract 'A' to get the 0-25 indexes
 *          that ingressArray and translateCharacter use.
*/
void Rotar::selectConfig(int idx, std::vector<int>& output) {
  static const std::vector<int> rotorI   = {69, 75, 77, 70, 76, 71, 68, 81, 86, 90, 78, 84, 79,   // EKMFLGDQVZNTO
                                            87, 89, 72, 88, 85, 83, 80, 65, 73, 66, 82, 67, 74};  // WYHXUSPAIBRCJ
  static const std::vector<int> rotorII  = {65, 74, 68, 75, 83, 73, 82, 85, 88, 66, 76, 72, 87,   // AJDKSIRUXBLHW
                                            84, 77, 67, 81, 71, 90, 78, 80, 89, 70, 86, 79, 69};  // TMCQGZNPYFVOE
  static const std::vector<int> rotorIII = {66, 68, 70, 72, 74, 76, 67, 80, 82, 84, 88, 86, 90,   // BDFHJLCPRTXVZ
                                            78, 89, 69, 73, 87, 71, 65, 75, 77, 85, 83, 81, 79};  // NYEIWGAKMUSQO

  switch (idx) {
    case 0:
      output = rotorI;
      break;
    case 1:
      output = rotorII;
      break;
    case 2:
      output = rotorIII;
      break;
    default:
      break;
  }
}

//! *********************** Plugboard *********************** //
Plugboard::Plugboard(int startIdx = 0) : _idx(startIdx) {
  printf("Plugboard is Loaded...\n");
  // setup();
  randomConfig();
}

void Plugboard::display() {
  printf("Plugboard Configuration\n");
  for (int ele : ingressArray) {
    printf("%c ", 'A' + ele);
  }
  printf("\n");
}

void Plugboard::randomConfig() {
  ingressArray = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25};
  std::random_device rd;
  std::mt19937 r(rd());
  std::shuffle(ingressArray.begin(), ingressArray.end(), r);
}

void Plugboard::setup() {
  for (int i = 0; i < 26; i++) {
    ingressArray.push_back(_idx);
    _idx = (_idx + 1) % 26;
  }
}

int Plugboard::translateCharacter(int idx) {
  return ingressArray.at(idx);
}

//! *********************** Enigma *********************** //
Enigma::Enigma() {
  printf("Enigma is Loaded...\n");
  // Rotars I, II, III (rotars[0] is the fast rotar that steps on every key)
  const char* names[] = {"I", "II", "III"};
  for (int i = 0; i < 3; i++) {
    rotars.emplace_back(names[i], i);
  }
}

void Enigma::display() {
  plugs.display();
  for (Rotar r : rotars) {
    r.display();
  }
}

void Enigma::processInput(std::string input) {
  for (char letter : input) {
    if (isalpha(letter)) {
      translateCharacter(letter);
    }
  }
}

void Enigma::runCLI(bool clear) {
  bool repeat = true;
  char *buf = new char[256];
  char done[] = "exit";
  std::string prompt = ">> ";
  while (repeat) {
    if (clear) { clearScreen(); }
    printf("%s", prompt.c_str());
    fflush(stdout);
    if (scanf("%255s", buf) != 1) { break; }
    if (strcmp(buf, done) == 0) {
      repeat = false;
      break;
    }
    processInput(buf);
  }

  delete[] buf;
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

void Enigma::translateCharacter(char c) {
  stepRotors();                            // rotors move before the signal passes through
  int idx = toupper(c) - 'A';              // letter -> index: 'A'/'a' -> 0 ... 'Z'/'z' -> 25
  printf("%c => ", 'A' + idx);
  idx = plugs.translateCharacter(idx);
  printf("%c => ", 'A' + idx);
  for (Rotar r: rotars) {
    idx = r.translateCharacter(idx);
    printf("%c => ", 'A' + idx);
  }
  printf("%c => ", 'A' + idx);
  for (unsigned i = rotars.size(); i-- > 0;) {
    idx = rotars[i].reverseCharacter(idx);
  }
  printf("%c\n", 'A' + idx);
}


//! *********************** main *********************** //
int main(int argc, char **argv) {
  // --test: keep all output on screen (no clearScreen between prompts)
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
  Enigma e;
  e.runCLI(!testMode);
}