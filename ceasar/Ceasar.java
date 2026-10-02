/**!
  The Ceasar Cipher is a simple rotational cryptographic algorithm. 
  However, it is enhanced with the additions of Vigenère modifications.
  Originated: 9/18/18
*/
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.Properties;

public class Ceasar {
  // CLASS SCOPE VARIABLES
  public static final char[] letters = {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
          'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'};
  public char[][] outputMatrix = new char[26][26];
  public char[][] shadowMatrix = new char[26][26];
  public char[] keyArray;

  // CLASS METHODS
  private int getIndex(char letter){
    /**!
     * Locates the index of the given letter in the alphabet
     * @param letter: The letter in which you wish to locate the index of
     * @return Integer representing the index of the given letter.
     */
    // Locate index of input code
    int indexNumber = 0;
    for (int x = 0; x < letters.length; x++) {
      if (letters[x] == letter){
        indexNumber = x;
      }
    }
    return indexNumber;
  }
  private boolean isLetter(char character){
    /**!
     * Checks whether a character is a letter in the alphabet (A-Z)
     * @param character: The character you wish to check.
     * @return True if the character is between 'A' and 'Z'. Anything else
     *         (spaces, digits, punctuation) is copied through unchanged, since
     *         getIndex would otherwise treat it as 'A'.
     */
    return character >= 'A' && character <= 'Z';
  }
  private void generateCipherMatrix(char code){
    /**!
     * Generates the Matrix with a given starting position
     * @param code : The first letter that the matrix starts at.
     */
    int startIndex = getIndex(code);

    for ( int i = 0; i < 26; i++) {
      char[] shiftedChars = new char[26];
      System.arraycopy(letters, startIndex, shiftedChars,0, letters.length - startIndex);
      System.arraycopy(letters, 0, shiftedChars, (letters.length - startIndex), letters.length - (letters.length - startIndex));
      outputMatrix[i] = shiftedChars;
      startIndex = (startIndex + 1) % 26;
      Arrays.fill(shadowMatrix[i], ' ');
    }
  }

  String encode(String inputText){
    /**!
     * Takes in a string to be encoded with the ciphered matrix
     * @param inputText: Given string you wish to be encoded.
     * @return The cipher encoded string.
     */

    char[] inputArray = inputText.toCharArray();
    String outputString = "";

    int keyIndex = 0;
    for(int i = 0; i < inputArray.length; i++) {
      if (isLetter(inputArray[i])) {
        int firstIndex = getIndex(keyArray[keyIndex]);
        int secondIndex = getIndex(inputArray[i]);
        outputString += outputMatrix[firstIndex][secondIndex];
        shadowMatrix[firstIndex][secondIndex] = inputArray[i];
      } else { outputString += inputArray[i]; }
      keyIndex = (keyIndex + 1) % keyArray.length;
    }
    return outputString;
  }

  String decode(String inputText){
    /**!
     * Takes in a string to be decoded with the ciphered matrix
     * @param inputText: Given string you wish to be decoded.
     * @return The cipher decoded string.
     */
    char[] inputArray = inputText.toCharArray();
    String outputString = "";

    int keyIndex = 0;
    for(int i = 0; i < inputArray.length; i++) {
      if (isLetter(inputArray[i])) {
        char[] temp = outputMatrix[getIndex(keyArray[keyIndex])];
        for (int j = 0; j < temp.length; j++) {
          if (temp[j] == inputArray[i]) {
            outputString += letters[j];
          }
        }
      } else { outputString += inputArray[i]; }
      keyIndex = (keyIndex + 1) % keyArray.length;
    }
    return outputString;
  }

  public void displayMatrix(boolean blackOut) {
    /**
     * Displays the matrix in an easy to read format.
     * @param hidden: displays the matrix without erroneous data
     *              ** WARNING ** - If true, can only be ran after a message
     *              has been decoded.
     */
    String[] matrixString = new String[outputMatrix.length];
    String[] shadowString = new String[outputMatrix.length];
    String header = "[ ]  ";
    Arrays.fill(matrixString, "");
    Arrays.fill(shadowString, "");

    for (int i = 0; i < outputMatrix.length; i++) {
      matrixString[i] += String.format("[%s] ", letters[i]);
      shadowString[i] += String.format("[%s] ", letters[i]);
      for (int j = 0; j < outputMatrix[i].length; j++) {
        matrixString[i] += String.format("| %s ", outputMatrix[i][j]);
        shadowString[i] += String.format("| %s ", shadowMatrix[i][j]);
      }
      matrixString[i] += "|";
      shadowString[i] += "|";
    }

    for (int i = 0; i < letters.length; i++) {
      header += String.format("[%c] ", letters[i]);
    }

    System.out.println(header);
    for (int i = 0; i < matrixString.length; i++) {
      System.out.println(blackOut ? shadowString[i] : matrixString[i]);
    }
  }

  public Ceasar(char code, String key) {
    /**!
     * Constructor method to initialize the ciphered matrix
     * @param code: The starting letter for the matrix.
     * @param key:  A given string that can be used to encrypt
     *              and decrypt a given message.
     */
    keyArray = key.toCharArray();
    generateCipherMatrix(code);
  }

  public static Properties loadConfig() {
    /**!
     * Loads the code, mask, and msg settings from the shared ceasar.ini file,
     * which lives beside Ceasar.class. Any setting missing from the file keeps
     * its default value.
     * @return Properties holding code, mask, and msg.
     */
    Properties defaults = new Properties();
    defaults.setProperty("code", "H");
    defaults.setProperty("mask", "BABBAGE");
    defaults.setProperty("msg", "HAPPY BIRTHDAY");
    Properties config = new Properties(defaults);
    try {
      Path dir = Paths.get(Ceasar.class.getProtectionDomain().getCodeSource().getLocation().toURI());
      try (Reader reader = new InputStreamReader(Files.newInputStream(dir.resolve("ceasar.ini")), StandardCharsets.UTF_8)) {
        config.load(reader);
      }
    } catch (Exception e) {
      // No readable ini; the defaults are used
    }
    return config;
  }

  public static void main(String[] args) {
    Properties config = loadConfig();
    char code = config.getProperty("code").trim().toUpperCase().charAt(0);
    String key = config.getProperty("mask").trim().toUpperCase();
    String msg = config.getProperty("msg").trim();
    // boolean hidden = false;
    Ceasar self = new Ceasar(code, key);

    String response1 = self.encode(msg.toUpperCase());
    String response2 = self.decode(response1);
    // Checked explicitly, since assert is skipped unless java runs with -ea
    if (!msg.toUpperCase().equals(response2)) {
      throw new IllegalStateException("Round trip failed: " + response2);
    }

    // Optional Method for viewing the cipher matrix based on last item decoded
    // self.displayMatrix(false);
    String output = String.format("Input:     %s\nEncrypted: %s\nDecrypted: %s", msg, response1, response2);
    System.out.println(output);
  }
}
