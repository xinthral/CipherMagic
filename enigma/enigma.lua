#!/usr/bin/env lua

--[[
  The Enigma machine is a rotor cipher: every key press steps the rotars, so the
  same letter comes out differently each time it is typed.
  This is a port of enigma.cpp, with the same parts, commands and output.

  Signal path for one key press:
    key -> Plugboard -> Rotar I -> II -> III -> Reflector -> III -> II -> I -> Plugboard -> lamp
  Every stage on the way back undoes its partner on the way in, with the Reflector's pairs in
  the middle, so the same settings both encrypt and decrypt.

  Run from the repository root (see the Makefile):
    make luaEnigma                 starts the machine
    lua enigma/enigma.lua --test   fixed plugboard key and no screen clearing, for repeatable runs

  Starting settings (plugboard key, rotar start positions) come from enigma.ini, which sits
  beside this file and is shared with the other language versions. --test ignores it.

  Contact indexes run 0-25 (A = 0 ... Z = 25) as in the other versions, so the wiring
  tables here are keyed 0-25 rather than Lua's usual 1-26.
]]

local SYMBOL_COUNT = 26
-- 1941 key-sheet example; with it and positions AAA, HELLOWORLD -> TUBEYQMVQC
local TEST_KEY = "AV BS CG DL FU HZ IN KM OW RX"

-- Historical rotar wirings: the letter in slot 1 is where A exits, slot 2 where B exits, and so on
local ROTAR_WIRINGS = {
  [0] = "EKMFLGDQVZNTOWYHXUSPAIBRCJ",   -- I
  [1] = "AJDKSIRUXBLHWTMCQGZNPYFVOE",   -- II
  [2] = "BDFHJLCPRTXVZNYEIWGAKMUSQO",   -- III
}
-- Historical Reflector B
local REFLECTOR_WIRING = "YRUHQSLDPXNGOKMIEBFZCWVJAT"

-- *********************** Console *********************** --
--[[!
  @brief Turns on ANSI escape-code support in the Windows console.

  Windows Terminal and Linux terminals understand escape codes already; the older
  Windows console (conhost) only does after a call into the system shell.
  Does nothing on Linux. Call once at startup.

  @return void
]]
local function enable_ansi()
  if package.config:sub(1, 1) == "\\" then
    os.execute("")
  end
end

--[[!
  @brief Clears the console (and its scrollback) and moves the cursor to the top-left.

  @return void

  @note Requires enable_ansi() to have been called on Windows.
]]
local function clear_screen()
  io.write("\27[2J\27[3J\27[H")
  io.flush()
end

-- *********************** Helpers *********************** --
--[[!
  @brief Checks whether a character is a letter the machine has a key for (A-Z, either case).

  @param c The character to check.
  @return True if the character is between 'A' and 'Z' or 'a' and 'z'.
]]
local function is_letter(c)
  return c:match("^[A-Za-z]$") ~= nil
end

--[[!
  @brief Converts a letter to its contact index.

  @param c A single letter, either case.
  @return The index, 'A'/'a' -> 0 ... 'Z'/'z' -> 25.
]]
local function to_index(c)
  return c:upper():byte() - 65
end

--[[!
  @brief Converts a contact index back to its uppercase letter.

  @param idx The index, 0-25.
  @return The letter, 0 -> 'A' ... 25 -> 'Z'.
]]
local function to_letter(idx)
  return string.char(65 + idx)
end

--[[!
  @brief Turns a wiring string into a table of contact indexes.

  @param wiring 26 letters, e.g. "EKMFLGDQVZNTOWYHXUSPAIBRCJ".
  @return A table keyed 0-25: entry contact -> exit contact.
]]
local function to_wiring(wiring)
  local output = {}
  for i = 0, SYMBOL_COUNT - 1 do
    output[i] = to_index(wiring:sub(i + 1, i + 1))
  end
  return output
end

--[[!
  @brief Formats a wiring table the way every display function prints it.

  @param wiring A table keyed 0-25.
  @return The 26 letters, each followed by a space.
]]
local function wiring_line(wiring)
  local output = {}
  for i = 0, SYMBOL_COUNT - 1 do
    table.insert(output, to_letter(wiring[i]) .. " ")
  end
  return table.concat(output)
end

--[[!
  @brief Builds a table with no swaps: every index maps to itself.

  @return A table keyed 0-25 where output[i] == i.
]]
local function identity_table()
  local output = {}
  for i = 0, SYMBOL_COUNT - 1 do
    output[i] = i
  end
  return output
end

--[[!
  @brief Seeds the random number generator differently on every run.

  os.time() only changes once a second, so the clock and the address of a fresh table
  are mixed in; two runs started in the same second still get different plugboards.
  The first few numbers after seeding are thrown away because some Lua 5.1 builds
  return nearly the same first value for nearby seeds.

  @return void
]]
local function seed_random()
  local address = tonumber(tostring({}):match("(%x+)$"), 16) or 0
  math.randomseed((os.time() + math.floor(os.clock() * 1000000) + address) % 2147483647)
  for _ = 1, 3 do math.random() end
end
seed_random()   -- once, when the file is loaded

-- *********************** Config *********************** --
--[[!
  @brief Loads the plugs and positions settings from the shared enigma.ini file.

  Reads simple key = value lines, skipping blank lines, comments (; or #), and
  [section] headers. Any setting missing from the file keeps its default value:
  plugs is empty (random cables) and positions is AAA. A missing file gives all defaults.

  @param path The path to the ini file.
  @return A table holding plugs and positions.
]]
local function load_config(path)
  local config = { plugs = "", positions = "AAA" }
  local file = io.open(path, "r")
  if not file then return config end

  for line in file:lines() do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^[;#%[]") then
      local key, value = line:match("^(.-)%s*=%s*(.-)$")
      if key and config[key] then config[key] = value end
    end
  end
  file:close()

  return config
end

-- *********************** Rotar *********************** --
--[[!
  @brief Two-way chaining translation matrix.

  Receiving input from the Plugboard, each rotar translates an input index and passes it
  along to the next rotar until it hits the reflector; the rotars then translate the
  reflected index in reverse order until it reaches the Plugboard again.
  The wiring never changes; turning the rotar only moves position, which the translate
  functions apply as an offset. start is where reset() returns it to.

  Fields:
    label          Name shown in messages and display(), e.g. "I"
    start          Position the rotar begins at and resets to (0-25)
    position       Current position (0-25); a carry happens when it wraps to 0
    ingress_array  Forward wiring: entry contact -> exit contact
    engress_array  Inverse wiring: exit contact -> entry contact
]]
local Rotar = {}
Rotar.__index = Rotar

--[[!
  @brief Builds a rotar with one of the historical wirings, starting at position 0.

  The inverse wiring is calculated from the forward wiring, so the two can never
  disagree. Prints a message if the config number is unknown, in which case the
  rotar has no wiring and must not be used.

  @param label  Name shown in messages and display(), e.g. "I".
  @param config Which wiring: 0 = I, 1 = II, 2 = III.
  @return The new rotar.
]]
function Rotar.new(label, config)
  print(string.format("Rotar %s Loaded...", label))
  local self = setmetatable({}, Rotar)
  self.label = label
  self.start = 0
  self.position = 0
  self.ingress_array = {}
  self.engress_array = {}
  if ROTAR_WIRINGS[config] then
    self.ingress_array = to_wiring(ROTAR_WIRINGS[config])
    for entry_contact = 0, SYMBOL_COUNT - 1 do
      self.engress_array[self.ingress_array[entry_contact]] = entry_contact
    end
  else
    print(string.format("Rotar %s: unknown config %s (expected 0-2)", label, tostring(config)))
  end
  return self
end

--[[!
  @brief Prints the forward wiring as 26 letters.

  The letter in slot 1 is where A exits, slot 2 where B exits, and so on. The wiring
  is shown as built; the current position is not applied.

  @return void
]]
function Rotar:display()
  print(string.format("Rotary %s Configuration", self.label))
  print(wiring_line(self.ingress_array))
end

--[[!
  @brief Advances the rotar one position.

  Only the position changes; the wiring stays fixed, and the translate functions
  apply the position offset.

  @return True when the rotar wraps from position 25 back to 0 (carry into the next rotar).
]]
function Rotar:step()
  self.position = (self.position + 1) % SYMBOL_COUNT
  return self.position == 0
end

--[[!
  @brief Turns the rotar back to its starting position.

  Decrypting needs the rotars where they were when encrypting began.

  @return void
]]
function Rotar:reset()
  self.position = self.start
end

--[[!
  @brief Sets the position the rotar begins at, and turns it there.

  @param start Start position, 0-25 (A = 0 ... Z = 25).
  @return void
]]
function Rotar:set_start(start)
  self.start = start % SYMBOL_COUNT
  self.position = self.start
end

--[[!
  @brief Passes an index forward through the rotar at its current position.

  The disc turns but the wires don't: the signal enters wire (idx + p), and the
  wire's exit end has turned p places too, so p is subtracted on the way out.

  @param idx Entry contact, 0-25.
  @return Exit contact, 0-25.
]]
function Rotar:translate_character(idx)
  local wire = self.ingress_array[(idx + self.position) % SYMBOL_COUNT]
  return (wire - self.position) % SYMBOL_COUNT
end

--[[!
  @brief Passes an index backward through the rotar at its current position.

  The return trip after the reflector. Same position offset as translate_character,
  but looked up in the inverse wiring, so for any position
  reverse_character(translate_character(x)) == x.

  @param idx Contact the signal comes back in on (an exit contact of the forward pass), 0-25.
  @return Contact it leaves on (the matching entry contact of the forward pass), 0-25.
]]
function Rotar:reverse_character(idx)
  local wire = self.engress_array[(idx + self.position) % SYMBOL_COUNT]
  return (wire - self.position) % SYMBOL_COUNT
end

-- *********************** Reflector *********************** --
--[[!
  @brief Fixed, one-sided translation matrix (historical Reflector B).

  Sits after the last rotar and sends the signal back through the rotars in reverse.
  Its wiring is 13 swapped pairs, so it is its own inverse and no letter maps to
  itself. It never steps and is applied once per key press.

  Fields:
    reflection  Contact -> paired contact, the same table both ways
]]
local Reflector = {}
Reflector.__index = Reflector

--[[!
  @brief Loads the Reflector B wiring and checks it.

  Prints a message for any letter that breaks the two reflector rules: pairs only,
  and no letter to itself.

  @return The new reflector.
]]
function Reflector.new()
  print("Reflector Loaded...")
  local self = setmetatable({}, Reflector)
  self.reflection = to_wiring(REFLECTOR_WIRING)
  -- A valid reflector is made of pairs (applying it twice gets you back) and never maps a letter to itself
  for i = 0, SYMBOL_COUNT - 1 do
    if self.reflection[self.reflection[i]] ~= i or self.reflection[i] == i then
      print(string.format("Reflector: invalid wiring at %s", to_letter(i)))
    end
  end
  return self
end

--[[!
  @brief Prints the reflector wiring as 26 letters.

  The letter in slot 1 is A's partner, slot 2 is B's partner, and so on.

  @return void
]]
function Reflector:display()
  print("Reflector Configuration")
  print(wiring_line(self.reflection))
end

--[[!
  @brief Bounces an index back toward the rotars.

  No position offset: the reflector doesn't turn.

  @param idx Contact coming out of the last rotar, 0-25.
  @return Paired contact to send back through the rotars, 0-25.
]]
function Reflector:translate_character(idx)
  return self.reflection[idx]
end

-- *********************** Plugboard *********************** --
--[[!
  @brief Swapped-pair translation matrix, passed on the way in and on the way out.

  Each cable swaps two letters (A <-> V); letters without a cable pass through
  unchanged. Up to 13 cables, 10 was standard. Because it is built from pairs it is
  its own inverse, so the same table serves both passes.

  Fields:
    pairs          The current cables as "AV BS CG ...", reusable as a key
    ingress_array  Letter -> swapped letter (itself when no cable is plugged)
]]
local Plugboard = {}
Plugboard.__index = Plugboard

--[[!
  @brief Builds a plugboard with 10 random cables.

  Use set_pairs afterwards to plug in a known key instead.

  @return The new plugboard.
]]
function Plugboard.new()
  print("Plugboard is Loaded...")
  local self = setmetatable({}, Plugboard)
  self.pairs = ""
  self.ingress_array = identity_table()
  self:random_config()
  return self
end

--[[!
  @brief Prints the key, then the full table as 26 letters.

  The letter in slot 1 is what A becomes, slot 2 what B becomes, and so on.
  Unplugged letters show as themselves.

  @return void
]]
function Plugboard:display()
  print(string.format("Plugboard Configuration (%s)", self.pairs))
  print(wiring_line(self.ingress_array))
end

--[[!
  @brief Plugs in cables from a key-sheet style string.

  Builds the table into a scratch copy and only keeps it if every pair is valid,
  so a typo leaves the previous cables in place.

  @param pairs Letter pairs, spaces optional, any case: "AV BS CG" or "avbscg".
  @return False (with a message) on a non-letter, a letter paired with itself, a letter
          used twice, or a leftover letter with no partner.
]]
function Plugboard:set_pairs(pairs)
  local wiring = identity_table()   -- no cables: every letter maps to itself

  local letters = {}
  for c in pairs:gmatch(".") do
    if not c:match("%s") then
      if not is_letter(c) then
        print(string.format("Plugboard: '%s' is not a letter", c))
        return false
      end
      table.insert(letters, c:upper())
    end
  end
  if #letters % 2 ~= 0 then
    print(string.format("Plugboard: %s has no partner", letters[#letters]))
    return false
  end

  local cleaned = {}
  for i = 1, #letters, 2 do
    local a = to_index(letters[i])
    local b = to_index(letters[i + 1])
    if a == b then
      print(string.format("Plugboard: %s can't be plugged into itself", letters[i]))
      return false
    end
    if wiring[a] ~= a or wiring[b] ~= b then   -- already swapped by an earlier cable
      print(string.format("Plugboard: %s%s reuses a plugged letter", letters[i], letters[i + 1]))
      return false
    end
    wiring[a] = b
    wiring[b] = a
    table.insert(cleaned, letters[i] .. letters[i + 1])
  end

  self.ingress_array = wiring
  self.pairs = table.concat(cleaned, " ")
  return true
end

--[[!
  @brief Plugs in random cables.

  Shuffles the 26 letters and takes neighbours as pairs, (1,2), (3,4), ..., so no
  letter can land in two cables. Print the pairs field to keep the key for decrypting.

  @param count Number of cables, clamped to 0-13. Defaults to 10.
  @return void
]]
function Plugboard:random_config(count)
  count = math.max(0, math.min(count or 10, SYMBOL_COUNT / 2))
  local letters = {}
  for i = 1, SYMBOL_COUNT do
    letters[i] = to_letter(i - 1)
  end
  for i = SYMBOL_COUNT, 2, -1 do   -- Fisher-Yates shuffle
    local j = math.random(i)
    letters[i], letters[j] = letters[j], letters[i]
  end
  self:set_pairs(table.concat(letters, "", 1, count * 2))
end

--[[!
  @brief Swaps an index for its cabled partner.

  Used for both passes, keyboard -> rotars and rotars -> lamp.

  @param idx Letter index, 0-25.
  @return The partner's index, or idx itself when the letter has no cable.
]]
function Plugboard:translate_character(idx)
  return self.ingress_array[idx]
end

-- *********************** Enigma *********************** --
--[[!
  @brief The whole machine: a Plugboard, three Rotars and a Reflector, plus the command line.

  Owns the parts, steps the rotars on each key press and runs the signal through
  them. Encrypting and decrypting are the same operation: put the machine back in
  the state it started in (same plugboard key, same start positions, rotars reset) and
  type the ciphertext.

  Fields:
    plugs      The Plugboard
    reflector  The Reflector
    rotars     The three Rotars; rotars[1] is the fast rotar, stepped on every key press

  @note Stepping is a plain odometer carry, and there are no ring settings or rotar
        order to choose, so output will not match a historical Enigma.
]]
local Enigma = {}
Enigma.__index = Enigma

--[[!
  @brief Builds the machine: rotars I, II, III, Reflector B and a plugboard.

  Prints the plugboard key and the rotar start positions once, after they are
  settled, so they can be written down and used later to decrypt.

  @param key       Plugboard pairs, e.g. "AV BS CG". Empty or nil keeps the random cables
                   the plugboard starts with; so does a key that set_pairs rejects.
  @param positions One start letter per rotar, rotar I first, e.g. "AAA". Empty, nil, or a
                   value set_positions rejects, leaves every rotar at A.
  @return The new machine.
]]
function Enigma.new(key, positions)
  local self = setmetatable({}, Enigma)
  self.plugs = Plugboard.new()
  self.reflector = Reflector.new()
  print("Enigma is Loaded...")
  self.rotars = {}
  for config, name in ipairs({"I", "II", "III"}) do
    table.insert(self.rotars, Rotar.new(name, config - 1))
  end
  if key and key ~= "" then
    self:set_plugs(key)
  end
  if positions and positions ~= "" then
    self:set_positions(positions)
  end
  print(string.format("Plugboard key: %s", self.plugs.pairs))
  print(string.format("Rotar positions: %s", self:positions()))
  return self
end

--[[!
  @brief Prints the wiring of every part: plugboard, each rotar, then the reflector.

  @return void
]]
function Enigma:display()
  self.plugs:display()
  for _, rotar in ipairs(self.rotars) do
    rotar:display()
  end
  self.reflector:display()
end

--[[!
  @brief Runs a line of text through the machine and prints the result.

  Each letter is one key press, so the rotars keep moving from wherever the last
  line left them. Non-letters are skipped and do not step the rotars. Prints one
  trace line per letter (see translate_character), then "Output:" with the result.

  @param input Text to encrypt or decrypt, any case.
  @return void
]]
function Enigma:process_input(input)
  local output = {}
  for c in input:gmatch(".") do
    if is_letter(c) then
      table.insert(output, self:translate_character(c))
    end
  end
  print(string.format("Output: %s", table.concat(output)))
end

--[[!
  @brief Reads lines until "exit" (or the end of input).

  Commands:   exit            quit
              reset           turn the rotars back to their start positions
              plugs           show the plugboard key
              plugs AV BS ..  set the plugboard (also resets the rotars)
              show            display every part's wiring
  Any other line is run through the machine; non-letters are skipped.
  To decrypt: reset (and set the same plugs), then type the ciphertext. In a new
  run the start positions must match too; those come from enigma.ini.
  A line that starts with a command word is always taken as the command, so
  those four words can't begin a message.

  @param clear True wipes the console once before the first prompt and prints the
               plugboard key and rotar positions again; results stay on screen after that.
  @return void
]]
function Enigma:run_cli(clear)
  local prompt = ">> "
  if clear then
    clear_screen()                                               -- once, so results stay on screen between prompts
    print(string.format("Plugboard key: %s", self.plugs.pairs))  -- the startup copy was just cleared
    print(string.format("Rotar positions: %s", self:positions()))
  end
  while true do
    io.write(prompt)
    io.flush()
    local line = io.read()
    if not line then break end        -- end of input
    line = line:gsub("[\r\n]+$", "")  -- drop the trailing newline
    local command, args = line:match("^([^ ]*) (.*)$")
    if not command then
      command, args = line, ""
    end

    if command == "exit" then
      break
    elseif command == "reset" then
      self:reset()
      print("Rotars reset")
    elseif command == "plugs" then
      if args ~= "" and self:set_plugs(args) then
        print("Rotars reset")
      end
      print(string.format("Plugboard key: %s", self.plugs.pairs))
    elseif command == "show" then
      self:display()
    else
      self:process_input(line)
    end
  end
end

--[[!
  @brief Steps the rotars like an odometer.

  The first rotar steps on every key press; each rotar that completes a full turn
  carries one step into the next.

  @return void
]]
function Enigma:step_rotors()
  for _, rotar in ipairs(self.rotars) do
    if not rotar:step() then break end   -- no full turn, so nothing carries further
  end
end

--[[!
  @brief Turns every rotar back to its start position.

  The plugboard is left alone. Do this before typing ciphertext to decrypt it.

  @return void
]]
function Enigma:reset()
  for _, rotar in ipairs(self.rotars) do
    rotar:reset()
  end
end

--[[!
  @brief Plugs in a new key and resets the rotars, so the machine starts from a known state.

  @param pairs Letter pairs, e.g. "AV BS CG".
  @return False if the key was rejected; the previous cables and rotar positions stay as they were.
]]
function Enigma:set_plugs(pairs)
  if not self.plugs:set_pairs(pairs) then return false end
  self:reset()
  return true
end

--[[!
  @brief Sets where each rotar starts, and turns the rotars there.

  @param positions One letter per rotar, rotar I (the fast rotar) first, either case:
                   "AAA" is all at 0, "BAA" starts rotar I one step on.
  @return False (with a message) unless it is exactly one letter per rotar; the rotars
          then stay as they were.
]]
function Enigma:set_positions(positions)
  if #positions ~= #self.rotars or positions:match("[^A-Za-z]") then
    print(string.format('Enigma: positions "%s" must be %d letters, one per rotar', positions, #self.rotars))
    return false
  end
  for i, rotar in ipairs(self.rotars) do
    rotar:set_start(to_index(positions:sub(i, i)))
  end
  return true
end

--[[!
  @brief The rotar start positions as letters.

  @return One uppercase letter per rotar, rotar I first, e.g. "AAA".
]]
function Enigma:positions()
  local output = {}
  for _, rotar in ipairs(self.rotars) do
    table.insert(output, to_letter(rotar.start))
  end
  return table.concat(output)
end

--[[!
  @brief One key press: steps the rotars, then runs the full signal path.

  key -> plugboard -> I -> II -> III -> reflector -> III -> II -> I -> plugboard -> lamp
  Prints each stage, so the line reads left to right along that path: ten letters,
  the first being the key typed and the last the lamp.

  @param c The key pressed; must be a letter, either case.
  @return The lit lamp (uppercase letter).
]]
function Enigma:translate_character(c)
  self:step_rotors()                                -- rotors move before the signal passes through
  local idx = to_index(c)
  local trace = { to_letter(idx) }
  idx = self.plugs:translate_character(idx)
  table.insert(trace, to_letter(idx))
  for _, rotar in ipairs(self.rotars) do
    idx = rotar:translate_character(idx)
    table.insert(trace, to_letter(idx))
  end
  idx = self.reflector:translate_character(idx)
  table.insert(trace, to_letter(idx))
  for i = #self.rotars, 1, -1 do
    idx = self.rotars[i]:reverse_character(idx)
    table.insert(trace, to_letter(idx))
  end
  idx = self.plugs:translate_character(idx)         -- same cables on the way out
  table.insert(trace, to_letter(idx))
  print(table.concat(trace, " => "))
  return to_letter(idx)
end

-- *********************** main *********************** --
--[[!
  @brief Starts the machine and its command line.

  Usage: lua enigma.lua [--test]
  No option:  plugboard key and rotar start positions from enigma.ini (random key if
              the ini leaves plugs empty), console cleared once.
  --test:     ignores enigma.ini; fixed plugboard key, positions AAA and no clearing,
              so every run starts in the same state and its output can be compared
              with an earlier run.
  enigma.ini is looked for beside this script.

  @param argv The command line options (without the script name).
  @param script_dir The directory this script is in, ending in a slash.
  @return 0 normally, 1 on an unknown option.
]]
local function main(argv, script_dir)
  local test_mode = false
  for _, option in ipairs(argv) do
    if option == "--test" then
      test_mode = true
    else
      print(string.format("Unknown option: %s\nUsage: %s [--test]", option, argv[0]))
      return 1
    end
  end

  enable_ansi()
  print("Hello World")
  local key = TEST_KEY
  local positions = "AAA"
  if not test_mode then
    local config = load_config(script_dir .. "enigma.ini")
    key = config.plugs
    positions = config.positions
  end
  local enigma = Enigma.new(key, positions)
  enigma:run_cli(not test_mode)
  return 0
end

-- Main Usage (only when run directly: then the script name lua was given is this file).
-- ceasar.lua's `if not ...` test can't be used here, because `...` also holds --test.
local source = debug.getinfo(1, "S").source
if arg and arg[0] and source == "@" .. arg[0] then
  -- The ini lives beside this script
  os.exit(main(arg, source:match("^@(.*[/\\])") or "./"))
end

return {
  Rotar = Rotar,
  Reflector = Reflector,
  Plugboard = Plugboard,
  Enigma = Enigma,
  load_config = load_config,
}
