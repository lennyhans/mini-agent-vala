CC      = valac
VALAFLAGS = --vapidir vala-extra-vapis
CFLAGS = -X -Wno-incompatible-pointer-types -X -Wno-discarded-qualifiers
LDLIBS  = --pkg libcurl --pkg json-glib-1.0

main: main.vala
	$(CC) $(VALAFLAGS) $(LDLIBS) $< -o $@ --cc=/usr/bin/gcc-14 $(CFLAGS)

clean:
	rm --force main
