ERL_INCLUDE ?= $(shell erl +S 1:1 -noshell -eval 'io:format("~s/usr/include", [code:root_dir()]), halt().')
SWIPL_PKG ?= swipl
CFLAGS ?= -O2 -Wall -Wextra -Werror

priv/swi_nif.so: c_src/swi_nif.c
	$(CC) $(CFLAGS) -std=c11 -fPIC -shared -pthread -I$(ERL_INCLUDE) $(shell pkg-config --cflags $(SWIPL_PKG)) $< -o $@ $(shell pkg-config --libs $(SWIPL_PKG)) -Wl,-rpath,$(shell pkg-config --variable=libdir $(SWIPL_PKG)) -ldl

.PHONY: clean
clean:
	rm -f priv/swi_nif.so
