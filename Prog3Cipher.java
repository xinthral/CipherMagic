import com.sun.deploy.util.ArrayUtil;

import java.util.Arrays;

/**
 * Week 3 Program, Cipher manipulation
 * Purpose: Generate a cipher based on a key utilizing shifting techniques
 * @Author: Jesse Hassell
 * Date: 9/18/18
 */

public class Prog3Cipher {
    // CLASS SCOPE VARIABLES
    public static final char[] letters = {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
            'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'};
    public char[][] outputMatrix = new char[26][26];
    public char[][] shadowMatrix = new char[26][26];
    public char[] keyArray;

    // CLASS METHODS
    private int getIndex(char letter){
        /**
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
    private void generateCipherMatrix(char code){
        /**
         * Generates the Matrix with a given starting position
         * @param code : The first letter that the matrix starts at.
         */
        int startIndex = getIndex(code);

        for ( int i = 0; i < 26; i++) {
            char[] shiftedChars = new char[26];
            System.arraycopy(letters, startIndex, shiftedChars,0, letters.length - startIndex);
            System.arraycopy(letters, 0, shiftedChars, (letters.length - startIndex), letters.length - (letters.length - startIndex));
            outputMatrix[i] = shiftedChars;
            if (startIndex < 26) {
                startIndex++;
            } else {
                startIndex = 0;
            }
            Arrays.fill(shadowMatrix[i], ' ');
        }
    }

    String encode(String inputText){
        /**
         * Takes in a string to be encoded with the ciphered matrix
         * @param inputText: Given string you wish to be encoded.
         * @return The cipher encoded string.
         */

        char[] inputArray = inputText.toCharArray();
        String outputString = "";

        int keyIndex = 0;
        for(int i = 0; i < inputArray.length; i++) {
            if (inputArray[i] != ' ') {
                int firstIndex = getIndex(keyArray[keyIndex]);
                int secondIndex = getIndex(inputArray[i]);
                outputString += outputMatrix[firstIndex][secondIndex];
                shadowMatrix[firstIndex][secondIndex] = inputArray[i];
            } else {
                outputString += " ";
            }
            if (keyIndex < keyArray.length-1) {
                keyIndex++;
            } else {
                keyIndex = 0;
            }
        }

        return outputString;
    }

    String decode(String inputText){
        /**
         * Takes in a string to be decoded with the ciphered matrix
         * @param inputText: Given string you wish to be decoded.
         * @return The cipher decoded string.
         */
        char[] inputArray = inputText.toCharArray();
        String outputString = "";

        int keyIndex = 0;
        for(int i = 0; i < inputArray.length; i++) {
            if (inputArray[i] != ' ') {
                char[] temp = outputMatrix[getIndex(keyArray[keyIndex])];
                for (int j = 0; j < temp.length; j++) {
                    if (temp[j] == inputArray[i]) {
                        outputString += letters[j];
                    }
                }
            } else {
                outputString += " ";
            }
            if (keyIndex < keyArray.length-1) {
                keyIndex++;
            } else {
                keyIndex = 0;
            }
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
                matrixString[i] += String.format("[%s]", letters[i]);
                shadowString[i] += String.format("[%s]", letters[i]);
                for (int j = 0; j < outputMatrix[i].length; j++) {
                    matrixString[i] += String.format(" | %s", outputMatrix[i][j]);
                    shadowString[i] += String.format(" | %s", shadowMatrix[i][j]);
                }
        }

        for (int i = 0; i < letters.length; i++) {
            header += String.format("[%c] ", letters[i]);
        }

        System.out.println(header);
        for (int i = 0; i < matrixString.length; i++) {
            System.out.println(blackOut ? shadowString[i] : matrixString[i]);
        }
    }

    public Prog3Cipher(char code, String key) {
        /**
         * Constructor method to initialize the ciphered matrix
         * @param code: The starting letter for the matrix.
         * @param key: A given string that can be used to encrypt
         *           and decrypt a given message.
         *
         */
        keyArray = key.toCharArray();
        generateCipherMatrix(code);
    }

    public static void main(String[] args) {
	    //System.out.print(outputMatrix[V][>]);
        char code = 'H';
        String key = "BABBAGE";
        boolean hidden = false;
        Prog3Cipher self = new Prog3Cipher(code, key);

        assert "PHXXF MQYBPKNJ".equals( self.encode( "HAPPY BIRTHDAY" ) );
        assert "HAPPY BIRTHDAY".equals( self.decode( "PHXXF MQYBPKNJ" ) );

        // Optional Method for viewing the cipher matrix based on last item decoded
        self.displayMatrix(hidden);
    }
}
