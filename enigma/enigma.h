#ifndef ENIGMA_H
#define ENIGMA_H

/**!
 * The purpose of this was my first attempt at modeling an Enigma machine with mathcing features.
 * Honestly, will likely butcher the algorithm but that's never stopped me before.
*/

#include <stdio.h>
#include <string>
#include <vector>

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
  std::string       _label;
  std::vector<int> ingressArray;
  std::vector<char> engressArray;
public:
  Rotar(std::string, int);
  Rotar(int);
  void displayIngress();
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
  std::vector<char> ingressArray;
public:
  Plugboard();
};

class Enigma {
private:
  Plugboard plugs;
public:
  std::vector<Rotar> rotars;
  Enigma();
};

#endif // ENIGMA_H //