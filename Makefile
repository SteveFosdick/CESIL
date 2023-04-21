CFLAGS = -g -O2 -Wall

all: cesil

cesil: cesil.asm
	laxasm -o cesil -l cesil.lst cesil.asm
