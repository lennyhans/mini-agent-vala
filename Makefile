CC      = valac
CFLAGS  = -O2 -pipe -Wall -Wextra
LDLIBS  = --pkg libsoup-3.0 --pkg json-glib-1.0

main: main.vala
	$(CC) $(LDLIBS) $< -o $@ -X -Wno-incompatible-pointer-types -X -Wno-discarded-qualifiers

clean:
	rm --force main
