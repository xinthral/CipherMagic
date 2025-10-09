#!/usr/bin/env lua

--[[
  The Ceasar Cipher is a simple rotational cryptographic algorithm.
  However, it is enhanced with the additions of Vigenère modifications.
]]


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

local function encode(matrix, salt, input)
  local output = {}
  local salt_chars = {salt:byte(1, #salt)}
  local salt_len = #salt_chars
  local salt_index = 1

  for c in input:gmatch(".") do
    if c ~= " " then
      local row = matrix[get_index(string.char(salt_chars[salt_index]))]
      local col = get_index(c)
      table.insert(output, string.sub(row, col, col))
    else
      table.insert(output, " ")
    end
    salt_index = (salt_index % salt_len) + 1
  end
  return table.concat(output)
end

function decode(matrix, salt, input)
  -- local output = "HAPPY BIRTHDAY"
  local output = {}
  local salt_chars = {salt:byte(1, #salt)}
  local salt_len = #salt_chars
  local salt_index = 1
  local letters = get_letters()
  
  for c in input:gmatch(".") do
    if c ~= " " then
      local row = matrix[get_index(string.char(salt_chars[salt_index]))]
      for j = 1, #row do
        local choice = string.sub(row, j, j)
        if choice == c then
          local letter = string.sub(letters, j, j)
          table.insert(output, letter)
          break
        end
      end
    else
      table.insert(output, ' ')
    end
    salt_index = (salt_index % salt_len) + 1
  end
  return table.concat(output)
end

-- Main Usage
local code   = 'H'
local salt   = "BABBAGE"
local msg    = "HAPPY BIRTHDAY"

-- Build the cipher matrix
local matrix = generate_matrix(code)

-- Encrypt
local encrypted = encode(matrix, salt, msg)

-- Decrypt
local decrypted = decode(matrix, salt, encrypted)

-- Show matrix
display_matrix(matrix)

-- Print results
print("Input:     " .. msg)
print("Encrypted: " .. encrypted)
print("Decrypted: " .. decrypted)

