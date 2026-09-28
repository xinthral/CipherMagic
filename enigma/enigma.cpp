/**!
 * My first real attempt at a coding an enigma machine
*/
#include "enigma.h"

//! *********************** Rotar *********************** //
Rotar::Rotar(std::string label, int startIdx) : _label(label) {
  printf("Rotar %s Loaded\n", _label.c_str());
  int idx = startIdx;
  for (int i = 0; i < 26; i++) {
    ingressArray.push_back(idx);
    idx = (idx + 1) % 26;
  }
}

Rotar::Rotar(int label) : Rotar(std::to_string(label), label) {}

void Rotar::displayIngress() {
  for (int ele : ingressArray) {
    printf("%c ", 'A' + ele);
  }
  printf("\n");
}

//! *********************** Plugboard *********************** //
Plugboard::Plugboard() {
  printf("Plugboard is Loaded...\n");
}

//! *********************** Enigma *********************** //
Enigma::Enigma() {
  printf("Enigma is Loaded\n");
  // temp loop for test data
  std::string name;
  for (int i = 0; i < 3; i++) {
    name = std::to_string(i);
    rotars.emplace_back(name, i  + 13);
    rotars.back().displayIngress();
  }
}

//! *********************** main *********************** //
int main() {
  printf("Hello World\n");
  Enigma e;
}