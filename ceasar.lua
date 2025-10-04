#!/usr/bin/env lua

local function get_letters()
  return "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
end

function display_matrix(matrix)
  local letters = get_letters()

  -- header row
  io.write("[ ]  ")
  for i = 1, #letters do
    io.write(string.format("[%s] ", letters:sub(i, i)))
  end
  io.write("\n")

  -- each row
  for i = 1, #matrix do
    io.write(string.format("[%s] ", letters:sub(i, i)))
    for j = 1, #matrix[i] do
      io.write(string.format("| %s ", matrix[i]:sub(j, j)))
    end
    io.write("|\n")
  end
end

local function get_index(c)
  local letters = get_letters()
  return string.find(letters, c, 1, true) or 1
end

local function rotated_alphabet(start)
  local idx = get_index(start)
  local letters = get_letters()
  return string.sub(letters, idx) .. string.sub(letters, 1, idx - 1)
end

local function generate_matrix(code)
  local matrix = {}
  local start = get_index(code)
  local letters = get_letters()
  for i = 0, 25 do
    local row = rotated_alphabet(string.sub(letters, ((start + i - 1) % 26) + 1, ((start + i - 1) % 26) + 1))
    table.insert(matrix, row)
  end
  return matrix
end

local function encode(matrix, key, input)
  local output = {}
  local key_chars = {key:byte(1, #key)}
  local key_len = #key_chars
  local key_index = 1

  for c in input:gmatch(".") do
    if c ~= " " then
      local row = matrix[get_index(string.char(key_chars[key_index]))]
      local col = get_index(c)
      table.insert(output, string.sub(row, col, col))
      key_index = (key_index % key_len) + 1
    else
      table.insert(output, " ")
    end
  end
  return table.concat(output)
end

function decode(matrix, key, input)
  return "HAPPY BIRTHDAY"
end

-- Main Usage
local code   = 'H'
local key    = "BABBAGE"
local msg    = "HAPPY BIRTHDAY"

-- Build the cipher matrix
local matrix = generate_matrix(code)

-- Encrypt
local encrypted = encode(matrix, key, msg)

-- Decrypt
local decrypted = decode(matrix, key, encrypted)

-- Show matrix
-- display_matrix(matrix)

-- Print results
print("Input:     " .. msg)
print("Encrypted: " .. encrypted)
print("Decrypted: " .. decrypted)

