/*
  The Ceasar Cipher is a simple rotational cryptographic algorithm.
  However, it is enhanced with the additions of Vigenère modifications.
*/
use std::collections::HashMap;
use std::fs;
use std::path::Path;

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

  /// Checks whether a character is a letter in the alphabet (A-Z); anything
  /// else would fall back to get_index's unwrap_or(0) and be treated as 'A'
  fn is_letter(&self, c: char) -> bool {
    c.is_ascii_uppercase()
  }

  pub fn encode(&self, input: &str) -> String {
    let input_chars: Vec<char> = input.to_uppercase().chars().collect();
    let key_len: usize = self.mask.len();  // key length comes from mask
    let mut output: String = String::new();
    let mut key_index: usize = 0;
    let mut idx = 0;

    for ch in &input_chars {
      if self.is_letter(*ch) {
        // get row from matrix based on key character
        let first_idx = self.get_index(self.mask[key_index]).unwrap_or(0) as usize;
        let second_idx = self.get_index(input_chars[idx]).unwrap_or(0) as usize;
        output.push(self.matrix[first_idx][second_idx]);
      } else {
        output.push(*ch); // Non-alphabet chars get returned
      }
      key_index = (key_index + 1) % key_len;
      idx += 1;
    }
    output
  }

  /// Reverses encode: finds the SALT character's row, searches it for the
  /// encrypted character, and maps that column back to the alphabet
  pub fn decode(&self, input: &str) -> String {
    let key_len: usize = self.mask.len();  // key length comes from mask
    let mut output: String = String::new();
    let mut key_index: usize = 0;

    for ch in input.to_uppercase().chars() {
      if self.is_letter(ch) {
        // get row from matrix based on key character
        let first_idx = self.get_index(self.mask[key_index]).unwrap_or(0) as usize;
        match self.matrix[first_idx].iter().position(|&c| c == ch) {
          Some(column) => output.push(self.letters[column]),
          None => output.push(ch), // Non-alphabet chars get returned
        }
      } else {
        output.push(ch); // Non-alphabet chars get returned
      }
      key_index = (key_index + 1) % key_len;
    }
    output
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

/// Loads the code, mask, and msg settings from the shared ceasar.ini file.
/// Reads simple key = value lines, skipping blank lines, comments (; or #), and
/// [section] headers. Any setting missing from the file keeps its default value.
fn load_config(path: &Path) -> HashMap<String, String> {
  let mut config: HashMap<String, String> = HashMap::from([
    ("code".to_string(), "H".to_string()),
    ("mask".to_string(), "BABBAGE".to_string()),
    ("msg".to_string(), "HAPPY BIRTHDAY".to_string()),
  ]);
  let text = match fs::read_to_string(path) {
    Ok(text) => text,
    Err(_) => return config,
  };
  for raw in text.lines() {
    let line = raw.trim();
    if line.is_empty() || line.starts_with(';') || line.starts_with('#') || line.starts_with('[') {
      continue;
    }
    if let Some((key, value)) = line.split_once('=') {
      let key = key.trim();
      if config.contains_key(key) {
        config.insert(key.to_string(), value.trim().to_string());
      }
    }
  }
  config
}

fn main() {
  // The ini lives beside this source file (file!() is the path given to rustc)
  let ini = Path::new(file!()).parent().unwrap_or(Path::new(".")).join("ceasar.ini");
  let config = load_config(&ini);
  let code = config["code"].to_uppercase().chars().next().unwrap_or('H');
  let salt = config["mask"].as_str();
  let msg = config["msg"].as_str();
  let cipher = Ceasar::new(code, salt);
  let encoded = cipher.encode(&msg.to_uppercase());
  let decoded = cipher.decode(&encoded);
  assert_eq!(decoded, msg.to_uppercase(), "Round trip failed");

  // cipher.display_matrix();
  println!("Input:     {}", msg);
  println!("Encrypted: {}", encoded);
  println!("Decrypted: {}", decoded);
}