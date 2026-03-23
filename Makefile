CC      = valac
CFLAGS  = -O2 -pipe -Wall -Wextra
LDLIBS  =
#LDLIBS  = --pkg sqlite3

main: main.vala
	$(CC) $(LDLIBS) $< -o $@

clean:
	rm --force main
