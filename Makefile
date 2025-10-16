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
CC := cc
PP := c++
DOXYGEN := doxygen.exe
RM := del
RRM := del /S /Q /f
NASM := "C:\\Users\\PC\\Applications\\Perl\\c\\bin\\nasm.exe"
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
	@echo "    cppCeasar  - Builds the cpp version of the Ceasar Cipher      "
	@echo "    javaCeasar - Builds the java version of the Ceasar Cipher     "
	@echo "    pyCeasar   - Builds the py version of the Ceasar Cipher       "
	@echo "    clean      - Clean up build files                             "
	@echo "##################################################################"

all: cppCeasar javaCeasar pyCeasar rustCeasar luaCeasar bashCeasar

cppCeasar: ceasar.o
	$(PP) $(CFLAGS) $^ -o $@.exe
	./$@.exe

javaCeasar: Ceasar.class
	java Ceasar

pyCeasar:
	python3 ceasar.py

rustCeasar:
	rustc -o ceasar.exe ceasar.rs
	./ceasar.exe

luaCeasar:
	lua ceasar.lua

bashCeasar:
	bash ceasar.bash

asmCeasar: ceasar.o
	/usr/bin/ld -o ceasar.exe $^
	./ceasar.exe

# Link up Assembly Objects
ceasar.o: ceasar.asm
	$(NASM) -f elf64 -g -F dwarf -o $@ $<

# Dynamically Compile any object files from requested cpp files
%.o: %.cpp %.h
	$(PP) $(CXXFLAGS) -o $@ -c $^

%.class: %.java
	javac $<

# Clean up Object Files
clean:
	$(MAKE) cleanobjs
	$(MAKE) cleanbin

# Clean up audiosuite and graph data
cleanobjs:
	$(RRM) *.o
	$(RRM) *.obj
	$(RRM) *.class
	$(RRM) *.pdb

# Clean up binary files
cleanbin:
	$(RM) *.exe

.PHONY: all clean cleanbin cleanobjs cppCeasar javaCeasar pyCeasar rustCeasar luaCeasar bashCeasar help