/*
  The Ceasar Cipher is a simple rotational cryptographic algorithm.
  However, it is enhanced with the additions of Vigenère modifications.
*/
const assert = require('assert');
const fs = require('fs');
const path = require('path');

class CeasarCipher {
  /**!
   * @brief Constructor for the CeasarCipher class.
   *
   * Initializes the CeasarCipher object with the provided code and mask. It also
   * generates a 2D matrix of characters based on the given code.
   *
   * @param code The character used to determine the starting index for rotating the lexicon.
   * @param mask A string (SALT) used for masking the message during encryption or decryption.
   */
  constructor(code, mask) {
    this.letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    this.length = this.letters.length;
    this.code = code.toUpperCase();
    this.mask = mask.toUpperCase();
    this.matrix = this.generateMatrix(this.code);
  }

  /**!
   * @brief Decrypts a message that was encrypted using the Caesar/Vigenère-style matrix.
   *
   * For each character, it finds the row determined by the current SALT character,
   * searches that row for the encrypted character, and maps the column back to the
   * original alphabet letter. Non-alphabetic characters are preserved as-is. The SALT
   * advances on every character, including spaces.
   *
   * @param input The encrypted message to be decrypted.
   * @return The decrypted message.
   */
  decode(input) {
    let output = '';
    let keyIdx = 0;
    for (const character of input.toUpperCase()) {
      if (this.isLetter(character)) {
        const row = this.matrix[this.getIndex(this.mask[keyIdx])];
        const column = row.indexOf(character);
        output += (column === -1) ? character : this.letters[column];
      } else {
        output += character;
      }
      keyIdx = (keyIdx + 1) % this.mask.length;
    }
    return output;
  }

  /**!
   * @brief Encrypts a message using the Caesar/Vigenère-style matrix and SALT.
   *
   * Each letter is substituted with matrix[row][column], where the row is the index of
   * the current SALT character and the column is the index of the letter. Non-alphabetic
   * characters are preserved as-is. The SALT advances on every character, including spaces.
   *
   * @param input The plaintext message to be encrypted.
   * @return The encrypted message.
   *
   * @note Each letter of the input message is converted to uppercase before encryption.
   */
  encode(input) {
    let output = '';
    let keyIdx = 0;
    for (const character of input.toUpperCase()) {
      if (this.isLetter(character)) {
        const firstIdx = this.getIndex(this.mask[keyIdx]);
        const secondIdx = this.getIndex(character);
        output += this.matrix[firstIdx][secondIdx];
      } else {
        output += character;
      }
      keyIdx = (keyIdx + 1) % this.mask.length;
    }
    return output;
  }

  /**!
   * @brief Generates a 2D matrix of characters based on a given code.
   *
   * Each row is the lexicon rotated to start one letter later than the row above it,
   * with the first row starting at the index of the given code.
   *
   * @param code The character used to determine the starting index for rotating the lexicon.
   * @return A 2D matrix (array of row strings) representing the generated matrix.
   */
  generateMatrix(code) {
    // Get Coded Index
    let idx = this.getIndex(code);
    const grid = [];
    // Loop through lexicon and rotate each per row
    for (let i = 0; i < this.length; i++) {
      grid.push(this.letters.slice(idx) + this.letters.slice(0, idx));
      idx = (idx + 1) % this.length;
    }
    return grid;
  }

  /**!
   * @brief Gets the index of a given character in the lexicon.
   *
   * @param code The character to search for in the lexicon.
   * @return The index of the character in the lexicon, or -1 if not found.
   */
  getIndex(code) {
    return this.letters.indexOf(code.toUpperCase());
  }

  /**!
   * @brief Checks whether a character is a letter in the lexicon (A-Z).
   *
   * @param character The character to check.
   * @return True if the character is between 'A' and 'Z'.
   */
  isLetter(character) {
    return character >= 'A' && character <= 'Z';
  }

  /**!
   * @brief Prints the generated 2D matrix of characters.
   *
   * @return void
   */
  printMatrix() {
    // Headers
    let line = '[ ] ';
    for (const letter of this.letters) { line += ` [${letter}]`; }
    console.log(line);
    // Body
    for (let i = 0; i < this.length; i++) {
      console.log(`[${this.letters[i]}] | ${[...this.matrix[i]].join(' | ')} |`);
    }
  }
}

/**!
 * @brief Loads the code, mask, and msg settings from the shared ceasar.ini file.
 *
 * Reads simple key = value lines, skipping blank lines, comments (; or #), and
 * [section] headers. Any setting missing from the file keeps its default value.
 *
 * @param file The path to the ini file.
 * @return An object holding code, mask, and msg.
 */
function loadConfig(file) {
  const config = { code: 'H', mask: 'BABBAGE', msg: 'HAPPY BIRTHDAY' };
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

if (require.main === module) {
  const config = loadConfig(path.join(__dirname, 'ceasar.ini'));
  const code = config.code;
  const mask = config.mask;
  const mesg = config.msg;
  const c = new CeasarCipher(code, mask);
  const response1 = c.encode(mesg);
  const response2 = c.decode(response1);
  assert.strictEqual(response2, mesg.toUpperCase(), 'Round trip failed');

  // c.printMatrix();
  console.log(`Input:     ${mesg}`);
  console.log(`Encrypted: ${response1}\nDecrypted: ${response2}`);
}

module.exports = { CeasarCipher, loadConfig };
