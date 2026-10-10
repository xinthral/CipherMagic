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
# Linker for the assembly targets, and the prefix needed to run what it builds
LD := /usr/bin/ld
LINUX :=
NOINPUT := < /dev/null

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
# The assembly targets are Linux programs: Windows nasm can assemble them, but they
# have to be linked and run inside WSL (wsl starts in the current directory).
# ld is named without its path because Git Bash would rewrite /usr/bin/ld into a Windows path.
LD := wsl ld
LINUX := wsl
# wsl passes its input on to the program it runs, so without this the link step would
# use up anything piped into make before the built program could read it
NOINPUT := < NUL
# Under Git Bash (MSYSTEM is set) make runs commands with sh, which has no NUL
ifdef MSYSTEM
NOINPUT := < /dev/null
endif

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
# -MMD            - also write a .d file listing the (non-system) headers each .cpp includes
# -MP             - add an empty target per header, so a deleted header doesn't break the build
# Standard Compiler Options
CFLAGS = -g -Wno-format -Wno-sign-compare -Wno-uninitialized

# Extended Compiler Options
CXFLAGS := $(CFLAGS) -std=c++20

# Extra Compiler Options
CXXFLAGS := $(CXFLAGS) -Wall -pedantic -O3

# Header Dependency Tracking Options
DEPFLAGS := -MMD -MP

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
	@echo "    jsCeasar   - Builds the js version of the Cipher              "
	@echo "    luaCeasar  - Builds the lua version of the Cipher             "
	@echo "    perlCeasar - Builds the perl version of the Cipher            "
	@echo "    phpCeasar  - Builds the php version of the Cipher             "
	@echo "    pyCeasar   - Builds the py version of the Cipher              "
	@echo "    rCeasar    - Builds the R version of the Cipher               "
	@echo "    rustCeasar - Builds the rust version of the Cipher            "
	@echo "    cppEnigma  - Builds the cpp version of the Enigma machine     "
	@echo "                 (test mode: ./cppEnigma.exe --test)              "
	@echo "    pyEnigma   - Builds the py version of the Enigma machine      "
	@echo "                 (test mode: python3 enigma/enigma.py --test)     "
	@echo "    rustEnigma - Builds the rust version of the Enigma machine    "
	@echo "                 (test mode: ./rustEnigma.exe --test)             "
	@echo "    luaEnigma  - Builds the lua version of the Enigma machine     "
	@echo "                 (test mode: lua enigma/enigma.lua --test)        "
	@echo "    javaEnigma - Builds the java version of the Enigma machine    "
	@echo "                 (test mode: java -cp enigma Enigma --test)       "
	@echo "    bashEnigma - Builds the bash version of the Enigma machine    "
	@echo "                 (test mode: bash enigma/enigma.bash --test)      "
	@echo "    jsEnigma   - Builds the js version of the Enigma machine      "
	@echo "                 (test mode: node enigma/enigma.js --test)        "
	@echo "    asmEnigma  - Builds the assembly version of the Enigma machine"
	@echo "                 (test mode: ./asmEnigma.exe --test, under WSL)   "
	@echo "    perlEnigma - Builds the perl version of the Enigma machine    "
	@echo "                 (test mode: perl enigma/enigma.pl --test)        "
	@echo "    rEnigma    - Builds the R version of the Enigma machine       "
	@echo "                 (test mode: Rscript enigma/enigma.R --test)      "
	@echo "    phpEnigma  - Builds the php version of the Enigma machine     "
	@echo "                 (test mode: php enigma/enigma.php --test)        "
	@echo "    clean      - Clean up build files                             "
	@echo "##################################################################"

all: 
	$(MAKE) asmCeasar
	$(MAKE) bashCeasar
	$(MAKE) cppCeasar
	$(MAKE) javaCeasar
	$(MAKE) jsCeasar
	$(MAKE) luaCeasar
	$(MAKE) perlCeasar
	$(MAKE) phpCeasar
	$(MAKE) pyCeasar
	$(MAKE) rCeasar
	$(MAKE) rustCeasar

cppCeasar: ceasar/ceasar.o
	$(PP) $(CFLAGS) $^ -o $@.exe
	./$@.exe

javaCeasar: ceasar/Ceasar.class
	java -cp ceasar Ceasar

jsCeasar:
	node ceasar/ceasar.js

perlCeasar:
	perl ceasar/ceasar.pl

phpCeasar:
	php ceasar/ceasar.php

pyCeasar:
	python3 ceasar/ceasar.py

rCeasar:
	Rscript ceasar/ceasar.R

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

pyEnigma:
	python3 enigma/enigma.py

rustEnigma:
	rustc -o $@.exe enigma/enigma.rs
	./$@.exe

luaEnigma:
	lua enigma/enigma.lua

javaEnigma: enigma/Enigma.class
	java -cp enigma Enigma

bashEnigma:
	bash enigma/enigma.bash

jsEnigma:
	node enigma/enigma.js

perlEnigma:
	perl enigma/enigma.pl

rEnigma:
	Rscript enigma/enigma.R

phpEnigma:
	php enigma/enigma.php

asmEnigma: enigma/enigma.obj
	$(LD) -g -o $@.exe $^ $(NOINPUT)
	$(LINUX) ./$@.exe

asmCeasar: ceasar/ceasar.obj
	$(LD) -g -o $@.exe $^ $(NOINPUT)
	$(LINUX) ./$@.exe

# Link up Assembly Objects
%.obj: %.asm
	$(NASM) -f elf64 -g -F dwarf -o $@ $<

# Dynamically Compile any object files from requested cpp files
%.o: %.cpp
	$(PP) $(CXXFLAGS) $(DEPFLAGS) -o $@ -c $<

# Pull in the generated .d files, so each object file also depends on the headers its
# .cpp includes. The leading dash keeps make quiet when none exist yet (first build).
-include $(wildcard *.d */*.d)

%.class: %.java
	javac $<

# Clean up Object Files
clean:
	$(MAKE) cleanobjs
	$(MAKE) cleanbin

# Clean up audiosuite and graph data
cleanobjs:
	$(RRM) *.o ceasar$(SEPR)*.o enigma$(SEPR)*.o
	$(RRM) *.d ceasar$(SEPR)*.d enigma$(SEPR)*.d
	$(RRM) *.obj ceasar$(SEPR)*.obj enigma$(SEPR)*.obj
	$(RRM) *.class ceasar$(SEPR)*.class enigma$(SEPR)*.class
	$(RRM) *.pdb

# Clean up binary files
cleanbin:
	$(RM) *.exe

.PHONY: all clean cleanbin cleanobjs asmCeasar asmEnigma cppCeasar cppEnigma pyEnigma rustEnigma luaEnigma javaEnigma bashEnigma jsEnigma perlEnigma rEnigma phpEnigma javaCeasar jsCeasar perlCeasar phpCeasar pyCeasar rCeasar rustCeasar luaCeasar bashCeasar help