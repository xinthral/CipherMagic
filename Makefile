#/**************************************
# Author: Xinthral 
# This was meant to be a modular make file which can compile any number of components
# in a directory dynamically.
# pragma GCC diagnostic ignored "-Wmaybe-uniitialized"
#**************************************/

# Compiler: gcc for C programs, g++ for C++ programs
# emcc for embedded C programs, em++ for embedded C++ programs
CC := gcc
PP := g++
DOXYGEN := doxygen
RRM := rm -rf
SEPR := /
NASM := nasm

# Windows Variants
ifeq ($(OS), Windows_NT)
# Chocolatey mingw package install location (override with: make MINGW_BIN=...)
MINGW_BIN ?= C:/ProgramData/mingw64/mingw64/bin
CC := $(MINGW_BIN)/gcc.exe
PP := $(MINGW_BIN)/g++.exe
DOXYGEN := doxygen.exe
RM := del
RRM := del /S /Q /f
# Chocolatey nasm package install location
NASM := "C:/Program Files/NASM/nasm.exe"
SEPR := \\

endif

# https://gcc.gnu.org/onlinedocs/gcc/Warning-Options.html
# compiler flags:
# -g              - adds debugging information to the executable file
# -Wall           - is used to turn on most compiler warnings
# -Wextra         - turns on extra compiler checks unchecked by -Wall
# -O              - optimization level (ie -O3)
# -std            - compile with version compatibility
# -no-pie         - do not produce a position-independent executable
# -fPIC           - Format position-independent code
# Standard Compiler Options
CFLAGS = -g -Wno-format -Wno-sign-compare -Wno-uninitialized

# Extended Compiler Options
CXFLAGS := $(CFLAGS) -std=c++20

# Extra Compiler Options
CXXFLAGS := $(CXFLAGS) -Wall -pedantic -O3

# Set GNU Shell
# SHELL := /bin/bash

# Build targets
SOURCES := $(patsubst %.cpp, %.o, $(wildcard *.cpp))
MODULES := $($(SOURCES))

# GNU Make Compilation Macros: 
# https://stackoverflow.com/questions/3220277/what-do-the-makefile-symbols-and-mean#3220288
# all: library.cpp main.cpp
# $@ evaluates to all
# $< evaluates to library.cpp
# $^ evaluates to library.cpp main.cpp

help:
	@echo "##################################################################"
	@echo "  Build Information for the Ciphers                               "
	@echo "  Usage: make \<str:option\>                                      "
	@echo "    asmCeasar  - Builds the assembly version of the Cipher        "
	@echo "    bashCeasar - Builds the bash version of the Cipher            "
	@echo "    cppCeasar  - Builds the cpp version of the Cipher             "
	@echo "    javaCeasar - Builds the java version of the Cipher            "
	@echo "    luaCeasar  - Builds the lua version of the Cipher             "
	@echo "    pyCeasar   - Builds the py version of the Cipher              "
	@echo "    rustCeasar - Builds the rust version of the Cipher            "
	@echo "    cppEnigma  - Builds the cpp version of the Enigma machine     "
	@echo "    clean      - Clean up build files                             "
	@echo "##################################################################"

all: 
	$(MAKE) asmCeasar
	$(MAKE) bashCeasar
	$(MAKE) cppCeasar
	$(MAKE) javaCeasar
	$(MAKE) luaCeasar
	$(MAKE) rustCeasar
	$(MAKE) pyCeasar

cppCeasar: ceasar/ceasar.o
	$(PP) $(CFLAGS) $^ -o $@.exe
	./$@.exe

javaCeasar: ceasar/Ceasar.class
	java -cp ceasar Ceasar

pyCeasar:
	python3 ceasar/ceasar.py

rustCeasar:
	rustc -o $@.exe ceasar/ceasar.rs
	./$@.exe

luaCeasar:
	lua ceasar/ceasar.lua

bashCeasar:
	bash ceasar/ceasar.bash

cppEnigma: enigma/enigma.o
	$(PP) $(CFLAGS) $^ -o $@.exe
	./$@.exe

asmCeasar: ceasar/ceasar.obj
	/usr/bin/ld -g -o $@.exe $^
	./$@.exe

# Link up Assembly Objects
%.obj: %.asm
	$(NASM) -f elf64 -g -F dwarf -o $@ $<

# Dynamically Compile any object files from requested cpp files
%.o: %.cpp
	$(PP) $(CXXFLAGS) -o $@ -c $<

%.class: %.java
	javac $<

# Clean up Object Files
clean:
	$(MAKE) cleanobjs
	$(MAKE) cleanbin

# Clean up audiosuite and graph data
cleanobjs:
	$(RRM) *.o ceasar$(SEPR)*.o enigma$(SEPR)*.o
	$(RRM) *.obj ceasar$(SEPR)*.obj
	$(RRM) *.class ceasar$(SEPR)*.class
	$(RRM) *.pdb

# Clean up binary files
cleanbin:
	$(RM) *.exe

.PHONY: all clean cleanbin cleanobjs asmCeasar cppCeasar cppEnigma javaCeasar pyCeasar rustCeasar luaCeasar bashCeasar help