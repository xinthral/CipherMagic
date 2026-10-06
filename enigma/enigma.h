#ifndef ENIGMA_H
#define ENIGMA_H

/**!
 * The purpose of this was my first attempt at modeling an Enigma machine with mathcing features.
 * Honestly, will likely butcher the algorithm but that's never stopped me before.
*/

#include <algorithm>
#include <chrono>
#include <iterator>
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
 * \class   Rotar
 * \brief   Two-way chaining translation Matrix
 * \details Receiving input from the Plugboard, each rotar translates an input index to a 
 *          translation index, then passes it along to the next rotar until it hits the 
 *          reflector plate. Proceeding with in-verse order, each rotar translates the 
 *          reflected index to an output index until it
*/
class Rotar {
private:
  int               _idx;
  std::string       _label;
  int               _position = 0;    // steps taken since the last full turn (0-25)
  std::vector<int> ingressArray;
  std::vector<int> engressArray;
public:
  Rotar(std::string, int);
  Rotar(int);
  void display();
  void setup();
  bool step();
  int  translateCharacter(int);
  int  reverseCharacter(int);
  void selectConfig(int, std::vector<int>&);
};

/**!
 * \class   Plugboard
 * \brief   One-way optional translation Matrix
 * \details Receiving user input from the keyboard, and then passing it through a translation
 *          matrix that converts up to 13 letters prior to going through the rotars. 
 * \note:   Is not part of the in-verse translation.
*/
class Plugboard {
private:
  int               _idx;
  std::vector<char> ingressArray;
public:
  Plugboard(int);
  void display();
  void randomConfig();
  void setup();
  int  translateCharacter(int);
};

class Enigma {
private:
  Plugboard plugs;
public:
  std::vector<Rotar> rotars;
  Enigma();
  void display();
  void processInput(std::string);
  void runCLI(bool clear = true);   // clear: wipe the console before each prompt
  void stepRotors();
  void translateCharacter(char);
};

#endif // ENIGMA_H //