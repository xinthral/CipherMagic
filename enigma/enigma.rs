/*
  The Enigma machine is a rotor cipher: every key press steps the rotars, so the
  same letter comes out differently each time it is typed.
  This is a port of enigma.cpp, with the same parts, commands and output.

  Signal path for one key press:
    key -> Plugboard -> Rotar I -> II -> III -> Reflector -> III -> II -> I -> Plugboard -> lamp
  Every stage on the way back undoes its partner on the way in, with the Reflector's pairs in
  the middle, so the same settings both encrypt and decrypt.

  Build and run from the repository root (see the Makefile):
    make rustEnigma            builds rustEnigma.exe and starts it
    ./rustEnigma.exe --test    fixed plugboard key and no screen clearing, for repeatable runs

  Starting settings (plugboard key, rotar start positions) come from enigma.ini, which sits
  beside this file and is shared with the other language versions. --test ignores it.
*/
use std::collections::hash_map::RandomState;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::hash::{BuildHasher, Hasher};
use std::io::{self, BufRead, Write};
use std::path::Path;
use std::process;

const SYMBOL_COUNT: usize = 26;
/// 1941 key-sheet example; with it and positions AAA, HELLOWORLD -> TUBEYQMVQC
const TEST_KEY: &str = "AV BS CG DL FU HZ IN KM OW RX";

/// Historical rotar wirings: the letter in slot 1 is where A exits, slot 2 where B exits, and so on
const ROTAR_WIRINGS: [&str; 3] = [
  "EKMFLGDQVZNTOWYHXUSPAIBRCJ",   // I
  "AJDKSIRUXBLHWTMCQGZNPYFVOE",   // II
  "BDFHJLCPRTXVZNYEIWGAKMUSQO",   // III
];
/// Historical Reflector B
const REFLECTOR_WIRING: &str = "YRUHQSLDPXNGOKMIEBFZCWVJAT";

// *********************** Console *********************** //
// The three console calls enable_ansi needs, straight from the Windows API (no crates)
#[cfg(windows)]
#[link(name = "kernel32")]
extern "system" {
  fn GetStdHandle(handle: u32) -> *mut std::ffi::c_void;
  fn GetConsoleMode(handle: *mut std::ffi::c_void, mode: *mut u32) -> i32;
  fn SetConsoleMode(handle: *mut std::ffi::c_void, mode: u32) -> i32;
}

/// Turns on ANSI escape-code support in the Windows console.
/// Windows Terminal and Linux terminals understand escape codes already; the older
/// Windows console (conhost) only does after this is called. Call once at startup.
#[cfg(windows)]
fn enable_ansi() {
  const STD_OUTPUT_HANDLE: u32 = -11i32 as u32;
  const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
  unsafe {
    let out = GetStdHandle(STD_OUTPUT_HANDLE);
    let mut mode: u32 = 0;
    if GetConsoleMode(out, &mut mode) != 0 {
      SetConsoleMode(out, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }
  }
}

/// Does nothing outside Windows: those terminals understand escape codes already.
#[cfg(not(windows))]
fn enable_ansi() {}

/// Clears the console (and its scrollback) and moves the cursor to the top-left.
/// Requires enable_ansi() to have been called on Windows.
fn clear_screen() {
  print!("\x1b[2J\x1b[3J\x1b[H");
  io::stdout().flush().ok();
}

// *********************** Helpers *********************** //
/// Checks whether a character is a letter the machine has a key for (A-Z, either case).
/// Unlike char::is_alphabetic, this rejects accented letters (such as 'É') that have
/// no contact on the rotars.
fn is_letter(c: char) -> bool {
  c.is_ascii_alphabetic()
}

/// Converts a letter to its contact index: 'A'/'a' -> 0 ... 'Z'/'z' -> 25
fn to_index(c: char) -> usize {
  (c.to_ascii_uppercase() as u8 - b'A') as usize
}

/// Converts a contact index back to its uppercase letter: 0 -> 'A' ... 25 -> 'Z'
fn to_letter(idx: usize) -> char {
  (b'A' + idx as u8) as char
}

/// Formats a wiring table the way every display function prints it: 26 letters, each followed by a space
fn wiring_line(table: &[usize]) -> String {
  table.iter().map(|&idx| format!("{} ", to_letter(idx))).collect()
}

/// Shuffles a slice in place (Fisher-Yates).
/// The standard library has no random numbers, so the seed is borrowed from RandomState,
/// which the system keys differently on every run, and stretched with an xorshift generator.
fn shuffle(items: &mut [usize]) {
  let mut state: u64 = RandomState::new().build_hasher().finish() | 1;   // xorshift must not start at 0
  for i in (1..items.len()).rev() {
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    let j = (state % (i as u64 + 1)) as usize;
    items.swap(i, j);
  }
}

// *********************** Config *********************** //
/// Loads the plugs and positions settings from the shared enigma.ini file.
/// Reads simple key = value lines, skipping blank lines, comments (; or #), and
/// [section] headers. Any setting missing from the file keeps its default value:
/// plugs is empty (random cables) and positions is AAA. A missing file gives all defaults.
fn load_config(path: &Path) -> HashMap<String, String> {
  let mut config: HashMap<String, String> = HashMap::from([
    ("plugs".to_string(), "".to_string()),
    ("positions".to_string(), "AAA".to_string()),
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

// *********************** Rotar *********************** //
/// Two-way chaining translation matrix.
/// Receiving input from the Plugboard, each rotar translates an input index and passes it
/// along to the next rotar until it hits the reflector; the rotars then translate the
/// reflected index in reverse order until it reaches the Plugboard again.
/// The wiring never changes; turning the rotar only moves `position`, which the
/// translate functions apply as an offset. `start` is where reset() returns it to.
pub struct Rotar {
  label: String,
  start: usize,                // position the rotar begins at and resets to (0-25)
  position: usize,             // current position (0-25); a carry happens when it wraps to 0
  ingress_array: Vec<usize>,   // forward wiring: entry contact -> exit contact
  engress_array: Vec<usize>,   // inverse wiring: exit contact -> entry contact
}

impl Rotar {
  /// Constructor: builds a rotar with one of the historical wirings, starting at position 0.
  /// `label` is the name shown in messages and display(), e.g. "I".
  /// `config` picks the wiring: 0 = I, 1 = II, 2 = III.
  /// The inverse wiring is calculated from the forward wiring, so the two can never
  /// disagree. Prints a message if the config number is unknown, in which case the
  /// rotar has no wiring and must not be used.
  pub fn new(label: &str, config: usize) -> Rotar {
    println!("Rotar {} Loaded...", label);
    let mut ingress_array: Vec<usize> = Vec::new();
    let mut engress_array: Vec<usize> = Vec::new();
    match ROTAR_WIRINGS.get(config) {
      Some(wiring) => {
        ingress_array = wiring.chars().map(to_index).collect();
        engress_array = vec![0; SYMBOL_COUNT];
        for (entry_contact, &exit_contact) in ingress_array.iter().enumerate() {
          engress_array[exit_contact] = entry_contact;
        }
      }
      None => println!("Rotar {}: unknown config {} (expected 0-2)", label, config),
    }
    Rotar {
      label: label.to_string(),
      start: 0,
      position: 0,
      ingress_array,
      engress_array,
    }
  }

  /// Prints the forward wiring as 26 letters.
  /// The letter in slot 1 is where A exits, slot 2 where B exits, and so on. The wiring
  /// is shown as built; the current position is not applied.
  pub fn display(&self) {
    println!("Rotary {} Configuration", self.label);
    println!("{}", wiring_line(&self.ingress_array));
  }

  /// Advances the rotar one position.
  /// Returns true when the rotar wraps from position 25 back to 0 (carry into the next rotar).
  pub fn step(&mut self) -> bool {
    self.position = (self.position + 1) % SYMBOL_COUNT;
    self.position == 0
  }

  /// Turns the rotar back to its starting position.
  /// Decrypting needs the rotars where they were when encrypting began.
  pub fn reset(&mut self) {
    self.position = self.start;
  }

  /// Sets the position the rotar begins at (0-25, A = 0 ... Z = 25), and turns it there.
  pub fn set_start(&mut self, start: usize) {
    self.start = start % SYMBOL_COUNT;
    self.position = self.start;
  }

  /// The position the rotar begins at and resets to (0-25).
  pub fn start(&self) -> usize {
    self.start
  }

  /// Passes an index forward through the rotar at its current position: entry contact
  /// in, exit contact out (both 0-25).
  /// The disc turns but the wires don't: the signal enters wire (idx + p), and the
  /// wire's exit end has turned p places too, so p is subtracted on the way out.
  /// The + SYMBOL_COUNT keeps the unsigned subtraction from going below zero.
  pub fn translate_character(&self, idx: usize) -> usize {
    let wire = self.ingress_array[(idx + self.position) % SYMBOL_COUNT];
    (wire + SYMBOL_COUNT - self.position) % SYMBOL_COUNT
  }

  /// Passes an index backward through the rotar at its current position: the return
  /// trip after the reflector.
  /// Same position offset as translate_character, but looked up in the inverse wiring,
  /// so for any position reverse_character(translate_character(x)) == x.
  pub fn reverse_character(&self, idx: usize) -> usize {
    let wire = self.engress_array[(idx + self.position) % SYMBOL_COUNT];
    (wire + SYMBOL_COUNT - self.position) % SYMBOL_COUNT
  }
}

// *********************** Reflector *********************** //
/// Fixed, one-sided translation matrix (historical Reflector B).
/// Sits after the last rotar and sends the signal back through the rotars in reverse.
/// Its wiring is 13 swapped pairs, so it is its own inverse and no letter maps to
/// itself. It never steps and is applied once per key press.
pub struct Reflector {
  reflection: Vec<usize>,   // contact -> paired contact, same table both ways
}

impl Reflector {
  /// Constructor: loads the Reflector B wiring and checks it.
  /// Prints a message for any letter that breaks the two reflector rules: pairs only,
  /// and no letter to itself.
  pub fn new() -> Reflector {
    println!("Reflector Loaded...");
    let reflection: Vec<usize> = REFLECTOR_WIRING.chars().map(to_index).collect();
    // A valid reflector is made of pairs (applying it twice gets you back) and never maps a letter to itself
    for i in 0..SYMBOL_COUNT {
      if reflection[reflection[i]] != i || reflection[i] == i {
        println!("Reflector: invalid wiring at {}", to_letter(i));
      }
    }
    Reflector { reflection }
  }

  /// Prints the reflector wiring as 26 letters.
  /// The letter in slot 1 is A's partner, slot 2 is B's partner, and so on.
  pub fn display(&self) {
    println!("Reflector Configuration");
    println!("{}", wiring_line(&self.reflection));
  }

  /// Bounces an index back toward the rotars: the contact coming out of the last
  /// rotar in, its paired contact out. No position offset: the reflector doesn't turn.
  pub fn translate_character(&self, idx: usize) -> usize {
    self.reflection[idx]
  }
}

// *********************** Plugboard *********************** //
/// Swapped-pair translation matrix, passed on the way in and on the way out.
/// Each cable swaps two letters (A <-> V); letters without a cable pass through
/// unchanged. Up to 13 cables, 10 was standard. Because it is built from pairs it is
/// its own inverse, so the same table serves both passes.
pub struct Plugboard {
  pairs: String,               // current cables as "AV BS CG ...", reusable as a key
  ingress_array: Vec<usize>,   // letter -> swapped letter (itself when no cable is plugged)
}

impl Plugboard {
  /// Constructor: builds a plugboard with 10 random cables.
  /// Use set_pairs afterwards to plug in a known key instead.
  pub fn new() -> Plugboard {
    println!("Plugboard is Loaded...");
    let mut plugboard = Plugboard {
      pairs: String::new(),
      ingress_array: (0..SYMBOL_COUNT).collect(),
    };
    plugboard.random_config(10);
    plugboard
  }

  /// Prints the key, then the full table as 26 letters.
  /// The letter in slot 1 is what A becomes, slot 2 what B becomes, and so on.
  /// Unplugged letters show as themselves.
  pub fn display(&self) {
    println!("Plugboard Configuration ({})", self.pairs);
    println!("{}", wiring_line(&self.ingress_array));
  }

  /// Plugs in cables from a key-sheet style string: letter pairs, spaces optional,
  /// any case ("AV BS CG" or "avbscg").
  /// Builds the table into a scratch copy and only keeps it if every pair is valid,
  /// so a typo leaves the previous cables in place.
  /// Returns false (with a message) on a non-letter, a letter paired with itself, a
  /// letter used twice, or a leftover letter with no partner.
  pub fn set_pairs(&mut self, pairs: &str) -> bool {
    let mut table: Vec<usize> = (0..SYMBOL_COUNT).collect();   // no cables: every letter maps to itself

    let mut letters: Vec<char> = Vec::new();
    for c in pairs.chars() {
      if c.is_whitespace() { continue; }
      if !is_letter(c) {
        println!("Plugboard: '{}' is not a letter", c);
        return false;
      }
      letters.push(c.to_ascii_uppercase());
    }
    if letters.len() % 2 != 0 {
      println!("Plugboard: {} has no partner", letters[letters.len() - 1]);
      return false;
    }

    let mut cleaned: Vec<String> = Vec::new();
    for pair in letters.chunks(2) {
      let a = to_index(pair[0]);
      let b = to_index(pair[1]);
      if a == b {
        println!("Plugboard: {} can't be plugged into itself", pair[0]);
        return false;
      }
      if table[a] != a || table[b] != b {   // already swapped by an earlier cable
        println!("Plugboard: {}{} reuses a plugged letter", pair[0], pair[1]);
        return false;
      }
      table[a] = b;
      table[b] = a;
      cleaned.push(pair.iter().collect());
    }

    self.ingress_array = table;
    self.pairs = cleaned.join(" ");
    true
  }

  /// Plugs in random cables; `count` is the number of cables, clamped to 0-13.
  /// Shuffles the 26 letters and takes neighbours as pairs, (0,1), (2,3), ..., so no
  /// letter can land in two cables. Print pairs() to keep the key for decrypting.
  pub fn random_config(&mut self, count: usize) {
    let count = count.min(SYMBOL_COUNT / 2);
    let mut letters: Vec<usize> = (0..SYMBOL_COUNT).collect();
    shuffle(&mut letters);
    let pairs: String = letters[..count * 2].iter().map(|&idx| to_letter(idx)).collect();
    self.set_pairs(&pairs);
  }

  /// The current cables as a key string: uppercase pairs separated by spaces, e.g.
  /// "AV BS CG"; empty with no cables. Passing it back to set_pairs rebuilds the
  /// same plugboard.
  pub fn pairs(&self) -> &str {
    &self.pairs
  }

  /// Swaps an index for its cabled partner, or returns it unchanged when the letter
  /// has no cable. Used for both passes, keyboard -> rotars and rotars -> lamp.
  pub fn translate_character(&self, idx: usize) -> usize {
    self.ingress_array[idx]
  }
}

// *********************** Enigma *********************** //
/// The whole machine: a Plugboard, three Rotars and a Reflector, plus the command line.
/// Owns the parts, steps the rotars on each key press and runs the signal through
/// them. Encrypting and decrypting are the same operation: put the machine back in
/// the state it started in (same plugboard key, same start positions, rotars reset) and
/// type the ciphertext.
/// Stepping is a plain odometer carry, and there are no ring settings or rotar order
/// to choose, so output will not match a historical Enigma.
pub struct Enigma {
  plugs: Plugboard,
  reflector: Reflector,
  rotars: Vec<Rotar>,   // rotars[0] is the fast rotar, stepped on every key press
}

impl Enigma {
  /// Constructor: builds rotars I, II, III, Reflector B and a plugboard.
  /// `key` is the plugboard pairs, e.g. "AV BS CG". Empty keeps the random cables the
  /// plugboard starts with; so does a key that set_pairs rejects.
  /// `positions` is one start letter per rotar, rotar I first, e.g. "AAA". Empty, or a
  /// value set_positions rejects, leaves every rotar at A.
  /// Prints the plugboard key and the rotar start positions once, after they are
  /// settled, so they can be written down and used later to decrypt.
  pub fn new(key: &str, positions: &str) -> Enigma {
    let plugs = Plugboard::new();
    let reflector = Reflector::new();
    println!("Enigma is Loaded...");
    let rotars: Vec<Rotar> = ["I", "II", "III"]
      .iter()
      .enumerate()
      .map(|(config, name)| Rotar::new(name, config))
      .collect();
    let mut enigma = Enigma { plugs, reflector, rotars };
    if !key.is_empty() {
      enigma.set_plugs(key);
    }
    if !positions.is_empty() {
      enigma.set_positions(positions);
    }
    println!("Plugboard key: {}", enigma.plugs.pairs());
    println!("Rotar positions: {}", enigma.positions());
    enigma
  }

  /// Prints the wiring of every part: plugboard, each rotar, then the reflector
  pub fn display(&self) {
    self.plugs.display();
    for rotar in &self.rotars {
      rotar.display();
    }
    self.reflector.display();
  }

  /// Runs a line of text through the machine and prints the result.
  /// Each letter is one key press, so the rotars keep moving from wherever the last
  /// line left them. Non-letters are skipped and do not step the rotars. Prints one
  /// trace line per letter (see translate_character), then "Output:" with the result.
  pub fn process_input(&mut self, input: &str) {
    let mut output: String = String::new();
    for c in input.chars() {
      if is_letter(c) {
        output.push(self.translate_character(c));
      }
    }
    println!("Output: {}", output);
  }

  /// Reads lines until "exit" (or the end of input).
  /// Commands:   exit            quit
  ///             reset           turn the rotars back to their start positions
  ///             plugs           show the plugboard key
  ///             plugs AV BS ..  set the plugboard (also resets the rotars)
  ///             show            display every part's wiring
  /// Any other line is run through the machine; non-letters are skipped.
  /// To decrypt: reset (and set the same plugs), then type the ciphertext. In a new
  /// run the start positions must match too; those come from enigma.ini.
  /// A line that starts with a command word is always taken as the command, so
  /// those four words can't begin a message.
  /// `clear` wipes the console once before the first prompt and prints the plugboard
  /// key and rotar positions again; results stay on screen after that.
  pub fn run_cli(&mut self, clear: bool) {
    let prompt = ">> ";
    if clear {
      clear_screen();                                     // once, so results stay on screen between prompts
      println!("Plugboard key: {}", self.plugs.pairs());  // the startup copy was just cleared
      println!("Rotar positions: {}", self.positions());
    }
    let stdin = io::stdin();
    loop {
      print!("{}", prompt);
      io::stdout().flush().ok();
      let mut buf = String::new();
      match stdin.lock().read_line(&mut buf) {
        Ok(0) | Err(_) => break,   // end of input
        Ok(_) => {}
      }
      let line = buf.trim_end_matches(|c| c == '\r' || c == '\n');   // drop the trailing newline
      let (command, args) = line.split_once(' ').unwrap_or((line, ""));

      match command {
        "exit" => break,
        "reset" => {
          self.reset();
          println!("Rotars reset");
        }
        "plugs" => {
          if !args.is_empty() && self.set_plugs(args) {
            println!("Rotars reset");
          }
          println!("Plugboard key: {}", self.plugs.pairs());
        }
        "show" => self.display(),
        _ => self.process_input(line),
      }
    }
  }

  /// Steps the rotars like an odometer.
  /// The first rotar steps on every key press; each rotar that completes a full turn
  /// carries one step into the next.
  pub fn step_rotors(&mut self) {
    for rotar in self.rotars.iter_mut() {
      if !rotar.step() { break; }   // no full turn, so nothing carries further
    }
  }

  /// Turns every rotar back to its start position.
  /// The plugboard is left alone. Do this before typing ciphertext to decrypt it.
  pub fn reset(&mut self) {
    for rotar in self.rotars.iter_mut() {
      rotar.reset();
    }
  }

  /// Plugs in a new key and resets the rotars, so the machine starts from a known state.
  /// Returns false if the key was rejected; the previous cables and rotar positions
  /// stay as they were.
  pub fn set_plugs(&mut self, pairs: &str) -> bool {
    if !self.plugs.set_pairs(pairs) { return false; }
    self.reset();
    true
  }

  /// Sets where each rotar starts, and turns the rotars there.
  /// `positions` is one letter per rotar, rotar I (the fast rotar) first, either case:
  /// "AAA" is all at 0, "BAA" starts rotar I one step on.
  /// Returns false (with a message) unless it is exactly one letter per rotar; the
  /// rotars then stay as they were.
  pub fn set_positions(&mut self, positions: &str) -> bool {
    let letters: Vec<char> = positions.chars().collect();
    if letters.len() != self.rotars.len() || !letters.iter().all(|&c| is_letter(c)) {
      println!("Enigma: positions \"{}\" must be {} letters, one per rotar", positions, self.rotars.len());
      return false;
    }
    for (rotar, &letter) in self.rotars.iter_mut().zip(letters.iter()) {
      rotar.set_start(to_index(letter));
    }
    true
  }

  /// The rotar start positions as letters: one uppercase letter per rotar, rotar I
  /// first, e.g. "AAA".
  pub fn positions(&self) -> String {
    self.rotars.iter().map(|rotar| to_letter(rotar.start())).collect()
  }

  /// One key press: steps the rotars, then runs the full signal path.
  /// key -> plugboard -> I -> II -> III -> reflector -> III -> II -> I -> plugboard -> lamp
  /// Prints each stage, so the line reads left to right along that path: ten letters,
  /// the first being the key typed and the last the lamp.
  /// `c` must be a letter, either case. Returns the lit lamp (uppercase letter).
  pub fn translate_character(&mut self, c: char) -> char {
    self.step_rotors();                                   // rotors move before the signal passes through
    let mut idx = to_index(c);
    let mut trace: Vec<String> = vec![to_letter(idx).to_string()];
    idx = self.plugs.translate_character(idx);
    trace.push(to_letter(idx).to_string());
    for rotar in &self.rotars {
      idx = rotar.translate_character(idx);
      trace.push(to_letter(idx).to_string());
    }
    idx = self.reflector.translate_character(idx);
    trace.push(to_letter(idx).to_string());
    for rotar in self.rotars.iter().rev() {
      idx = rotar.reverse_character(idx);
      trace.push(to_letter(idx).to_string());
    }
    idx = self.plugs.translate_character(idx);            // same cables on the way out
    trace.push(to_letter(idx).to_string());
    println!("{}", trace.join(" => "));
    to_letter(idx)
  }
}

// *********************** main *********************** //
/// Starts the machine and its command line.
/// Usage: rustEnigma.exe [--test]
/// No option:  plugboard key and rotar start positions from enigma.ini (random key if
///             the ini leaves plugs empty), console cleared once.
/// --test:     ignores enigma.ini; fixed plugboard key, positions AAA and no clearing,
///             so every run starts in the same state and its output can be compared
///             with an earlier run.
/// enigma.ini is looked for beside this source file, by the path it was compiled with,
/// so run the program from the repository root.
/// "make rustEnigma" builds and then starts the program with no option; run
/// ./rustEnigma.exe --test yourself for test mode.
/// Exits with 0 normally, 1 on an unknown option.
fn main() {
  let args: Vec<String> = env::args().collect();
  let mut test_mode = false;
  for option in args.iter().skip(1) {
    if option == "--test" {
      test_mode = true;
    } else {
      println!("Unknown option: {}\nUsage: {} [--test]", option, args[0]);
      process::exit(1);
    }
  }

  enable_ansi();
  println!("Hello World");
  let mut key = TEST_KEY.to_string();
  let mut positions = "AAA".to_string();
  if !test_mode {
    // The ini lives beside this source file (file!() is the path given to rustc)
    let ini = Path::new(file!()).parent().unwrap_or(Path::new(".")).join("enigma.ini");
    let config = load_config(&ini);
    key = config["plugs"].clone();
    positions = config["positions"].clone();
  }
  let mut enigma = Enigma::new(&key, &positions);
  enigma.run_cli(!test_mode);
}
