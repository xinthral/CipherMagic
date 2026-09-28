<?php
/*
  The Ceasar Cipher is a simple rotational cryptographic algorithm.
  However, it is enhanced with the additions of Vigenère modifications.
*/

class CeasarCipher {
  private string $letters;
  private int $length;
  private string $code;
  private string $mask;
  private array $matrix;

  /**!
   * @brief Constructor for the CeasarCipher class.
   *
   * Initializes the CeasarCipher object with the provided code and mask. It also
   * generates a 2D matrix of characters based on the given code.
   *
   * @param code The character used to determine the starting index for rotating the lexicon.
   * @param mask A string (SALT) used for masking the message during encryption or decryption.
   */
  public function __construct(string $code, string $mask) {
    $this->letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    $this->length = strlen($this->letters);
    $this->code = strtoupper($code);
    $this->mask = strtoupper($mask);
    $this->matrix = $this->generateMatrix($this->code);
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
  public function decode(string $input): string {
    $output = '';
    $keyIdx = 0;
    $maskLength = strlen($this->mask);
    foreach (str_split(strtoupper($input)) as $character) {
      if ($this->isLetter($character)) {
        $row = $this->matrix[$this->getIndex($this->mask[$keyIdx])];
        $column = strpos($row, $character);
        $output .= ($column === false) ? $character : $this->letters[$column];
      } else {
        $output .= $character;
      }
      $keyIdx = ($keyIdx + 1) % $maskLength;
    }
    return $output;
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
  public function encode(string $input): string {
    $output = '';
    $keyIdx = 0;
    $maskLength = strlen($this->mask);
    foreach (str_split(strtoupper($input)) as $character) {
      if ($this->isLetter($character)) {
        $firstIdx = $this->getIndex($this->mask[$keyIdx]);
        $secondIdx = $this->getIndex($character);
        $output .= $this->matrix[$firstIdx][$secondIdx];
      } else {
        $output .= $character;
      }
      $keyIdx = ($keyIdx + 1) % $maskLength;
    }
    return $output;
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
  public function generateMatrix(string $code): array {
    // Get Coded Index
    $idx = $this->getIndex($code);
    $grid = [];
    // Loop through lexicon and rotate each per row
    for ($i = 0; $i < $this->length; $i++) {
      $grid[] = substr($this->letters, $idx) . substr($this->letters, 0, $idx);
      $idx = ($idx + 1) % $this->length;
    }
    return $grid;
  }

  /**!
   * @brief Gets the index of a given character in the lexicon.
   *
   * @param code The character to search for in the lexicon.
   * @return The index of the character in the lexicon, or -1 if not found.
   */
  public function getIndex(string $code): int {
    $pos = strpos($this->letters, strtoupper($code));
    return ($pos === false) ? -1 : $pos;
  }

  /**!
   * @brief Checks whether a character is a letter in the lexicon (A-Z).
   *
   * @param character The character to check.
   * @return True if the character is between 'A' and 'Z'.
   */
  public function isLetter(string $character): bool {
    return $character >= 'A' && $character <= 'Z';
  }

  /**!
   * @brief Prints the generated 2D matrix of characters.
   *
   * @return void
   */
  public function printMatrix(): void {
    // Headers
    echo '[ ] ';
    foreach (str_split($this->letters) as $letter) { echo " [{$letter}]"; }
    echo "\n";
    // Body
    for ($i = 0; $i < $this->length; $i++) {
      echo "[{$this->letters[$i]}] | " . implode(' | ', str_split($this->matrix[$i])) . " |\n";
    }
  }
}

/**!
 * @brief Loads the code, mask, and msg settings from the shared ceasar.ini file.
 *
 * Uses INI_SCANNER_RAW so characters like ! ( ) in unquoted values are kept as
 * plain text. Any setting missing from the file keeps its default value.
 *
 * @param path The path to the ini file.
 * @return An array holding code, mask, and msg.
 */
function loadConfig(string $path): array {
  $config = ['code' => 'H', 'mask' => 'BABBAGE', 'msg' => 'HAPPY BIRTHDAY'];
  $parsed = is_readable($path) ? parse_ini_file($path, false, INI_SCANNER_RAW) : false;
  if ($parsed !== false) {
    foreach (array_keys($config) as $key) {
      if (isset($parsed[$key])) { $config[$key] = trim($parsed[$key]); }
    }
  }
  return $config;
}

if (PHP_SAPI === 'cli' && realpath($argv[0]) === __FILE__) {
  $config = loadConfig(__DIR__ . '/ceasar.ini');
  $code = $config['code'];
  $mask = $config['mask'];
  $mesg = $config['msg'];
  $c = new CeasarCipher($code, $mask);
  $response1 = $c->encode($mesg);
  $response2 = $c->decode($response1);
  // Checked explicitly, since assert() is disabled by default in production php.ini
  if ($response2 !== strtoupper($mesg)) { throw new RuntimeException("Round trip failed: {$response2}"); }

  // $c->printMatrix();
  echo "Input:     {$mesg}\n";
  echo "Encrypted: {$response1}\nDecrypted: {$response2}\n";
}

?>
