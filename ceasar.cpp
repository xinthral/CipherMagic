/**!
  The Ceasar Cipher is a simple rotational cryptographic algorithm.
  However, it is enhanced with the additions of Vigenère modifications.
 */
#include <stdio.h>
#include <algorithm>
#include <cstring>
#include <cctype>
#include <string>

// #define NDEBUG
#include <cassert>
 
// Use (void) to silence unused warnings.
#define assertm(exp, msg) assert((void(msg), exp))

class CeasarCipher {
protected:
private:
  char code;
  char** matrix;
  const char* mask;
  const char* letters;
  int length;
public:
  /**!
   * @brief Constructor for the CeasarCipher class.
   *
   * Initializes the CeasarCipher object with the provided code, mask, and message.
   * It also generates a 2D matrix of characters based on the given code.
   *
   * @param code The character used to determine the starting index for rotating the lexicon.
   * @param mask A string used for masking the message during encryption or decryption.
   * @param message The message to be encrypted or decrypted using the Ceasar Cipher.
   */
  CeasarCipher(const char code, const char * mask) :
    code(code), mask(mask) {
      letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
      length = std::strlen(letters);
      matrix = generateMatrix(code);
  };

  char * decode(const char * input) {
    int keyIdx = 0;
    int inputLength = std::strlen(input);
    char * temp = new char[inputLength + 1];
    char * output = new char[inputLength + 1];
    int outputIdx = 0;
    for (int i = 0; i < inputLength; i++) {
      if (std::isalpha(input[i])) {
        temp = matrix[getIndex(mask[keyIdx])];
        for (int j = 0; j < std::strlen(temp); j++) {
          if (temp[j] == input[i]) {
            output[outputIdx] = letters[j];
            outputIdx = (outputIdx + 1) % inputLength;
            break;
          }
        }
      } else { output[outputIdx++] = input[i]; }
      keyIdx = (keyIdx + 1) % std::strlen(mask);
    }
    output[inputLength] = '\0';
    return output;
  }
  
  char * encode(const char * input) {
    int keyIdx = 0;
    int firstIdx = 0;
    int secondIdx = 0;
    int inputLength = std::strlen(input);
    int maskLength = std::strlen(mask);
    char * output = new char[inputLength + 1];
    for (int i = 0; i < inputLength; i++) {
      if (std::isalpha(input[i])) {
        firstIdx = getIndex(mask[keyIdx]);
        secondIdx = getIndex(input[i]);
        output[i] = matrix[firstIdx][secondIdx];
      } else {
        output[i] = ' ';
      }
      keyIdx = (keyIdx + 1) % maskLength;
    }
    output[inputLength] = '\0';
    return output;
  }

  /**!
   * @brief Generates a 2D matrix of characters based on a given code.
   *
   * The function generates a 2D matrix where each row is a rotated version of the
   * lexicon (alphabet) starting from the index corresponding to the given code.
   *
   * @param code The character used to determine the starting index for rotating the lexicon.
   * @return A 2D matrix of characters representing the generated matrix.
   */
  char ** generateMatrix(const char code) {
    // Get Coded Index
    int idx = getIndex(code);
    // Allocate Memory for Matrix
    char** grid = new char*[length];
    grid[0] = new char[length + 1];
    char* temp = new char[length + 1];
    // Loop through lexicon and rotate each per row
    std::strcpy(temp, letters);
    rotateArray(temp, idx);
    std::strcpy(grid[0], temp);
    for (int i = 1; i < length; i++) {
      grid[i] = new char[length + 1];
      rotateArray(temp, 1);
      std::strcpy(grid[i], temp);
      idx = (idx + 1) % length;
    }
    // Delete temp and return matrix
    delete[] temp;
    return grid;
  }

  /**!
   * @brief Gets the index of a given character in the lexicon.
   *
   * This function searches for the given character in the lexicon (alphabet) and
   * returns its index. If the character is not found, it prints a message and
   * returns -1.
   *
   * @param code The character to search for in the lexicon.
   * @return The index of the character in the lexicon. If the character is not found,
   *         returns -1.
   */
  int getIndex(const char code) {
    const char* pos = std::strchr(letters, code);
    if (!pos) {
      printf("%d: %c - Not found.\n", pos, code);
      return -1;
    }
    return int(pos - letters);
  }

  /**!
   * @brief Prints the generated 2D matrix of characters.
   *
   * The printMatrix function iterates through the 2D matrix and prints each character
   * in a row-major order. The matrix is generated based on the provided code during
   * the CeasarCipher object's initialization.
   *
   * @return void
   */
  void printMatrix() {
    // Headers
    printf("[ ] ");
    for (int k = 0; k < length; k++) { printf(" [%c]", letters[k]); }
    // Body
    for (int i = 0; i < length; i++) {
      printf("\n[%c] ", letters[i]);
      for (int j = 0; j < length; j++) {
        printf("| %c ", matrix[i][j]);
      }
      printf("|");
    }
    printf("\n");
  }

  /**!
   * @brief Rotates the characters in the input array by the specified offset.
   *
   * This function takes an input array of characters and an offset value. It rotates
   * the characters in the input array by the specified offset, moving the characters
   * to the right by the given offset. The function uses a temporary array to perform
   * the rotation.
   *
   * @param input The input array of characters to be rotated.
   * @param offset The number of positions to rotate the characters to the right.
   *
   * @return void
   */
  void rotateArray(char* input, int offset) {
    offset = offset % length;
    char* tmp = new char[length + 1];
    std::strcpy(tmp, input + offset);
    std::strncat(tmp, input, offset);
    std::strcpy(input, tmp);
    delete[] tmp;
  }
};

int main(int argc, char **argv) {
  const char code = 'H';
  const char* mask = "BABBAGE";
  const char* mesg = "HAPPY BIRTHDAY";
  const char* expected = "PHXXF MQYBPKNJ";
  const char* response1;
  const char* response2;
  CeasarCipher c = CeasarCipher(code, mask);
  response1 = c.encode(mesg);
  assert(std::strcmp(expected, response1) == 0);
  response2 = c.decode(response1);
  assert(std::strcmp(mesg, response2) == 0);

  // c.printMatrix();
  printf("Input:     %s\n", mesg);
  printf("Encrypted: %s\nDecrypted: %s\n", response1, response2);
}