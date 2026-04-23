# Atari 2600 Game

A homebrew Atari 2600 game built with 6502 assembly and DASM.

## Prerequisites

- **DASM** assembler — `brew install dasm` (macOS) or grab it from [the DASM repo](https://github.com/dasm-assembler/dasm)
- **Stella** emulator — `brew install --cask stella` or from [stella-emu.github.io](https://stella-emu.github.io)

## Build

```bash
make
```

This produces `game.bin` — a 4KB Atari 2600 ROM.

## Run

```bash
make run
# or directly:
open -a Stella game.bin
```

## Controls

- Joystick (arrow keys in Stella) to move the player sprite
- The sprite is a simple 8-pixel-tall face

## Project Structure

| File       | Description                              |
|------------|------------------------------------------|
| game.asm   | Main game source                         |
| vcs.h      | TIA + RIOT register definitions          |
| macro.h    | Standard macros (CLEAN_START, etc.)      |
| Makefile   | Build automation                         |
