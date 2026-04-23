DASM = dasm
SOURCE = game.asm
OUTPUT = game.bin
SYMBOL = game.sym
LIST = game.lst

all: $(OUTPUT)

$(OUTPUT): $(SOURCE) vcs.h macro.h
	$(DASM) $(SOURCE) -f3 -o$(OUTPUT) -s$(SYMBOL) -l$(LIST)
	cp $(OUTPUT) cyloid.rom

clean:
	rm -f $(OUTPUT) $(SYMBOL) $(LIST) cyloid.rom

run: $(OUTPUT)
	@echo "Open $(OUTPUT) in Stella emulator to play!"
	@echo "  macOS: open -a Stella $(OUTPUT)"
	@echo "  Linux: stella $(OUTPUT)"

.PHONY: all clean run
