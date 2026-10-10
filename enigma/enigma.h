#ifndef ENIGMA_H
#define ENIGMA_H

/**!
 * The purpose of this was my first attempt at modeling an Enigma machine with mathcing features.
 * Honestly, will likely butcher the algorithm but that's never stopped me before.
 *
 * Signal path for one key press:
 *   key -> Plugboard -> Rotar I -> II -> III -> Reflector -> III -> II -> I -> Plugboard -> lamp
 * Every stage on the way back undoes its partner on the way in, with the Reflector's pairs in
 * the middle, so the same settings both encrypt and decrypt.
 *
 * Build and run from the repository root (see the Makefile):
 *   make cppEnigma            builds cppEnigma.exe and starts it
 *   ./cppEnigma.exe --test    fixed plugboard key and no screen clearing, for repeatable runs
 *
 * Starting settings (plugboard key, rotar start positions) come from enigma.ini, which sits
 * beside this file and is shared with the other language versions. --test ignores it.
*/

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <map>
#include <random>
#include <stdio.h>
#include <string>
#include <string.h>
#include <vector>

/**!
 * \brief   Turns on ANSI escape-code support in the Windows console
 * \details Windows Terminal and Linux terminals understand escape codes already; the older
 *          Windows console (conhost) only does after this is called. Does nothing on Linux.
 *          Call once at startup.
*/
void enableAnsi();

/**!
 * \brief   Clears the console (and its scrollback) and moves the cursor to the top-left
 * \note:   Requires enableAnsi() to have been called on Windows.
*/
void clearScreen();

/**!
 * \brief   Rotates a vector left by one position, in place
 * \details The first element moves to the end: {A, B, C, D} becomes {B, C, D, A}.
 *          Does nothing to an empty vector.
*/
void rotateVector(std::vector<int>&);

/**!
 * \brief   Loads the plugs and positions settings from the shared enigma.ini file
 * \details Reads simple key = value lines, skipping blank lines, comments (; or #), and
 *          [section] headers. Any setting missing from the file keeps its default value:
 *          plugs is empty (random cables) and positions is AAA. A missing file gives
 *          all defaults.
 * \param   path    The path to the ini file
 * \return  A map of setting names to values
*/
std::map<std::string, std::string> loadConfig(const std::filesystem::path&);

/**!
 * \class   Rotar
 * \brief   Two-way chaining translation Matrix
 * \details Receiving input from the Plugboard, each rotar translates an input index to a 
 *          translation index, then passes it along to the next rotar until it hits the 
 *          reflector plate. Proceeding with in-verse order, each rotar translates the
 *          reflected index to an output index until it reaches the Plugboard again.
 *          The wiring never changes; turning the rotar only moves _position, which the
 *          translate functions apply as an offset. _start is where reset() returns it to.
*/
class Rotar {
private:
  int               _idx;             // config number the rotar was built with (0 = I, 1 = II, 2 = III)
  std::string       _label;
  int               _start = 0;       // position the rotar begins at and resets to (0-25)
  int               _position = 0;    // current position (0-25); a carry happens when it wraps to 0
  std::vector<int> ingressArray;      // forward wiring: entry contact -> exit contact
  std::vector<int> engressArray;      // inverse wiring: exit contact -> entry contact
public:
  Rotar(std::string, int);
  Rotar(int);
  void display();
  void setup();
  bool step();
  void reset();
  void setStart(int);
  int  start();
  int  translateCharacter(int);
  int  reverseCharacter(int);
  void selectConfig(int, std::vector<int>&, std::vector<int>&);
};

/**!
 * \class   Reflector
 * \brief   Fixed, one-sided translation Matrix (historical Reflector B)
 * \details Sits after the last rotar and sends the signal back through the rotars in
 *          reverse. Its wiring is 13 swapped pairs, so it is its own inverse and no letter
 *          maps to itself. It never steps and is applied once per key press.
*/
class Reflector {
private:
  int              _idx;              // unused
  std::vector<int> reflection;        // contact -> paired contact, same table both ways
public:
  Reflector();
  void display();
  int  translateCharacter(int);
};

/**!
 * \class   Plugboard
 * \brief   Swapped-pair translation Matrix, passed on the way in and on the way out
 * \details Each cable swaps two letters (A <-> V); letters without a cable pass through
 *          unchanged. Up to 13 cables, 10 was standard. Because it is built from pairs it is
 *          its own inverse, so the same table serves both passes.
*/
class Plugboard {
private:
  std::string       _pairs;           // current cables as "AV BS CG ...", reusable as a key
  std::vector<int>  ingressArray;     // letter -> swapped letter (itself when no cable is plugged)
public:
  Plugboard();
  void        display();
  bool        setPairs(std::string);
  void        randomConfig(int count = 10);
  std::string pairs();
  int         translateCharacter(int);
};

/**!
 * \class   Enigma
 * \brief   The whole machine: a Plugboard, three Rotars and a Reflector, plus the command line
 * \details Owns the parts, steps the rotars on each key press and runs the signal through
 *          them. Encrypting and decrypting are the same operation: put the machine back in
 *          the state it started in (same plugboard key, same start positions, rotars
 *          reset) and type the ciphertext.
 * \note:   Stepping is a plain odometer carry, and there are no ring settings or rotar
 *          order to choose, so output will not match a historical Enigma.
*/
class Enigma {
private:
  Plugboard plugs;
  Reflector reflector;
public:
  std::vector<Rotar> rotars;        // rotars[0] is the fast rotar, stepped on every key press
  // key: plugboard pairs, empty means random cables; positions: one start letter per rotar
  Enigma(std::string key = "", std::string positions = "AAA");
  void display();
  void processInput(std::string);
  void runCLI(bool clear = true);   // clear: wipe the console once before the first prompt
  void stepRotors();
  void reset();
  bool setPlugs(std::string);
  bool setPositions(std::string);
  std::string positions();
  char translateCharacter(char);
};

#endif // ENIGMA_H //