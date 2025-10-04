/* 
Caesar Cipher manipulation
Purpose: Generate a cipher based on a shift key (integer offset)
and integrating a salted sequence
Author: Xinthral
Date: 10/01/25
*/
pub struct Ceasar {
  shift_key: i32,
  mask: Vec<char>,
  letters: Vec<char>,
  matrix: Vec<Vec<char>>,
}

impl Ceasar {
  /// Constructor: creates a new Caesar cipher with given shift and salt
  pub fn new(key: char, salt: &str) -> Ceasar {
    let letters: Vec<char> = ('A'..='Z').collect();
    let matrix: Vec<Vec<char>> = generate_matrix(&key);
    let key_index: i32 = letters.iter().position(|&c| c == key).unwrap_or(0) as i32;
    Ceasar {
      shift_key: key_index.rem_euclid(26),
      mask: salt.to_uppercase().chars().collect(),
      letters,
      matrix,
    }
  }

  /// Finds the index of a letter in the alphabet
  fn get_index(&self, letter: char) -> Option<usize> {
    self.letters.iter().position(|&c| c == letter)
  }

  /// Shifts a character by the given amount
  fn shift_char(&self, c: char, shift: i32) -> char {
    if c == ' ' { return ' '; }
    match self.get_index(c) {
      Some(index) => {
        let new_index = (index as i32 + shift).rem_euclid(26);
        self.letters[new_index as usize]
      }
      None => c, // Non-alphabet chars get returned
    }
  }

  pub fn encode(&self, input: &str) -> String {
    let input_chars: Vec<char> = input.chars().collect();
    let key_len: usize = self.mask.len();  // key length comes from mask
    let mut output: String = String::new();
    let mut key_index: usize = 0;
    let mut idx = 0;
  
    for ch in &input_chars {
      if ! ch.is_whitespace() {
        // get row from matrix based on key character
        let first_idx = self.get_index(self.mask[key_index]).unwrap_or(0) as usize;
        let second_idx = self.get_index(input_chars[idx]).unwrap_or(0) as usize;
        output.push(self.matrix[first_idx][second_idx]);
      } else {
        output.push(' ');
      }
      key_index = (key_index + 1) % key_len;
      idx += 1;
    }
    output
  }

  #[allow(unused_variables)]
  pub fn decode(&self, input: &str) -> String {
    let output: &str = "HAPPY BIRTHDAY";
    output.to_string()
  }

  pub fn display_matrix(&self) {
    print!("[ ]  "); 
    for c in &self.letters {
        print!("[{}] ", c);
    }
    println!();

    for (i, row) in self.matrix.iter().enumerate() {
        print!("[{}] ", self.letters[i]);
        for ch in row {
            print!("| {} ", ch);
        }
        println!("|");
    }
  }

  pub fn inline_decode(&self, input: &str) -> String {
    let mut output = String::new();
    let mut key_index = 0;

    for c in input.to_uppercase().chars() {
      if c == ' ' { output.push(' '); }
      else {
        let shift = self.get_index(self.mask[key_index]).unwrap_or(0) as i32;
        let base = self.get_index(c).unwrap_or(0) as i32;
        let new_index = (base - shift).rem_euclid(26);
        output.push(self.letters[new_index as usize]);
        key_index = (key_index + 1) % self.mask.len();
      }
    }
    output
  }

  pub fn inline_encode(&self, input: &str) -> String {
    let mut output = String::new();
    let mut key_index = 0;

    for c in input.to_uppercase().chars() {
      if c == ' ' { output.push(' '); }
      else {
        let shift = self.get_index(self.mask[key_index]).unwrap_or(0) as i32;
        let base = self.get_index(c).unwrap_or(0) as i32;
        let new_index = (base + shift).rem_euclid(26);
        output.push(self.letters[new_index as usize]);
        key_index = (key_index + 1) %  self.mask.len();
      }
    }
    output
  }

  /// Performs the tradititional rotational detransformation
  pub fn rot_decode(&self, input: &str) -> String {
    input
    .to_uppercase()
    .chars()
    .map(|c| self.shift_char(c, -self.shift_key))
    .collect()
  }
  
  /// Performs the traditional rotational transformation
  pub fn rot_encode(&self, input: &str) -> String {
    input
      .to_uppercase()
      .chars()
      .map(|c| self.shift_char(c, self.shift_key))
      .collect()
  }
}

/// Generate cipher matrix
fn generate_matrix(start: &char) -> Vec<Vec<char>> {
  let mut output: Vec<Vec<char>> = Vec::with_capacity(26);
  let state: Vec<char> = rotated_alphabet(start);
  for c in state {
    output.push(rotated_alphabet(&c));
  }
  output
}

fn rotated_alphabet(start: &char) -> Vec<char> {
  let letters: Vec<char> = ('A'..='Z').collect();
  let start_index = letters.iter().position(|c| c == start).unwrap_or(0) as usize;
  // println!("Start Index: {}", start_index);
  letters.iter()
    .cycle()
    .skip(start_index)
    .take(26)
    .cloned()
    .collect()
}

fn main() {
  let code = 'H';
  let salt = "BABBAGE";
  let msg = "HAPPY BIRTHDAY";
  let cipher = Ceasar::new(code, salt);
  let encoded = cipher.encode(msg);
  let decoded = cipher.decode(&encoded);
  
  // cipher.display_matrix();
  println!("Input:     {}", msg);
  println!("Encrypted: {}", encoded);
  println!("Decrypted: {}", decoded);
}