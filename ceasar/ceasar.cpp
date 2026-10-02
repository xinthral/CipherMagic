/**!
  The Ceasar Cipher is a simple rotational cryptographic algorithm.
  However, it is enhanced with the additions of Vigenère modifications.
 */
#include <stdio.h>
#include <algorithm>
#include <cstring>
#include <cctype>
#include <string>
#include <filesystem>
#include <fstream>
#include <map>

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

  /**!
   * @brief Destructor for the CeasarCipher class.
   *
   * Frees each row of the matrix, then the matrix itself.
   */
  ~CeasarCipher() {
    for (int i = 0; i < length; i++) { delete[] matrix[i]; }
    delete[] matrix;
  }

  // The matrix is owned by this object, so copying it would free it twice
  CeasarCipher(const CeasarCipher&) = delete;
  CeasarCipher& operator=(const CeasarCipher&) = delete;

  /**!
   * @brief Decrypts a message that was encrypted using the Caesar/Vigenère-style matrix.
   *
   * The decode function takes an encrypted string and reverses the encryption using the
   * same 2D matrix and SALT string used for encoding. For each character, it finds the
   * corresponding row determined by the current SALT character, searches that row for
   * the encrypted character, and maps it back to the original alphabet letter. Non-
   * alphabetic characters are preserved as-is. The SALT cycles through for each letter.
   *
   * @param input The encrypted message to be decrypted.
   * @return A newly allocated char array containing the decrypted message. Caller is
   *         responsible for deleting the returned array to avoid memory leaks.
   *
   * @note Each letter of the encrypted message is expected to match the matrix encoding.
   *       Spaces and punctuation are preserved unchanged. The decryption relies on
   *       the same initial code character and SALT used during encryption.
   */
  char * decode(const char * input) {
    int keyIdx = 0;
    int inputLength = std::strlen(input);
    int maskLength = std::strlen(mask);
    char * output = new char[inputLength + 1];
    for (int i = 0; i < inputLength; i++) {
      // Non-letters, and anything not found in the row, are copied through
      output[i] = input[i];
      if (isLetter(input[i])) {
        const char * row = matrix[getIndex(mask[keyIdx])];
        const char * pos = std::strchr(row, input[i]);
        if (pos) { output[i] = letters[pos - row]; }
      }
      keyIdx = (keyIdx + 1) % maskLength;
    }
    output[inputLength] = '\0';
    return output;
  }
  
  /**!
   * @brief Encrypts a message using the Caesar/Vigenère-style matrix and SALT.
   *
   * The encode function takes an input string and encrypts it using the pre-generated
   * 2D matrix. Each character is substituted based on its corresponding row determined
   * by the current character in the SALT string. Non-alphabetic characters are
   * preserved as-is. The SALT cycles through for each letter of the message.
   *
   * @param input The plaintext message to be encrypted.
   * @return A newly allocated char array containing the encrypted message. Caller is
   *         responsible for deleting the returned array to avoid memory leaks.
   *
   * @note Each letter of the input message is converted to uppercase before encryption.
   *       Spaces and punctuation are preserved unchanged. The encryption is dependent
   *       on both the initial code character and the SALT string.
   */
  char * encode(const char * input) {
    int keyIdx = 0;
    int firstIdx = 0;
    int secondIdx = 0;
    int inputLength = std::strlen(input);
    int maskLength = std::strlen(mask);
    char * output = new char[inputLength + 1];
    for (int i = 0; i < inputLength; i++) {
      char ch = std::toupper(static_cast<unsigned char>(input[i]));
      if (isLetter(ch)) {
        firstIdx = getIndex(mask[keyIdx]);
        secondIdx = getIndex(ch);
        output[i] = matrix[firstIdx][secondIdx];
      } else {
        output[i] = ch;
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
   * @brief Checks whether a character is a letter in the lexicon (A-Z).
   *
   * Unlike std::isalpha, this rejects lowercase letters, which getIndex cannot find.
   *
   * @param ch The character to check.
   * @return True if the character is between 'A' and 'Z'.
   */
  bool isLetter(const char ch) {
    return ch >= 'A' && ch <= 'Z';
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
      printf("%c - Not found.\n", code);
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

/**!
 * @brief Loads the code, mask, and msg settings from the shared ceasar.ini file.
 *
 * Reads simple key = value lines, skipping blank lines, comments (; or #), and
 * [section] headers. Any setting missing from the file keeps its default value.
 *
 * @param path The path to the ini file.
 * @return A map of setting names to values.
 */
std::map<std::string, std::string> loadConfig(const std::filesystem::path& path) {
  std::map<std::string, std::string> config = {
    {"code", "H"}, {"mask", "BABBAGE"}, {"msg", "HAPPY BIRTHDAY"}
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

int main(int argc, char **argv) {
  // The ini lives beside this source file
  auto config = loadConfig(std::filesystem::path(__FILE__).parent_path() / "ceasar.ini");
  const char code = std::toupper(config["code"][0]);
  std::string maskUpper = config["mask"];
  std::transform(maskUpper.begin(), maskUpper.end(), maskUpper.begin(), ::toupper);
  std::string mesgUpper = config["msg"];
  std::transform(mesgUpper.begin(), mesgUpper.end(), mesgUpper.begin(), ::toupper);
  const char* mask = maskUpper.c_str();
  const char* mesg = config["msg"].c_str();
  const char* response1;
  const char* response2;
  CeasarCipher c(code, mask);
  response1 = c.encode(mesgUpper.c_str());
  response2 = c.decode(response1);
  assertm(std::strcmp(mesgUpper.c_str(), response2) == 0, "Round trip failed");

  // c.printMatrix();
  printf("Input:     %s\n", mesg);
  printf("Encrypted: %s\nDecrypted: %s\n", response1, response2);

  // encode and decode return new[] buffers owned by the caller
  delete[] response1;
  delete[] response2;
}