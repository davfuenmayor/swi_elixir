ERL_INCLUDE ?= $(shell erl +S 1:1 -noshell -eval 'io:format("~s/usr/include", [code:root_dir()]), halt().')
SWI_HOME ?= priv/swipl
SWI_LIBDIR ?= $(firstword $(wildcard $(SWI_HOME)/lib/*) $(SWI_HOME)/bin)
NIF_EXT ?= so
TARGET ?= $(SWI_HOME)/bin/swi_nif.$(NIF_EXT)
CFLAGS ?= -O2 -Wall -Wextra -Werror

ifeq ($(NIF_EXT),dll)
LINK_FLAGS = -shared -static -static-libgcc
SWI_LINK = -l:libswipl.dll.a
else ifeq ($(shell uname -s),Darwin)
LINK_FLAGS = -bundle -undefined dynamic_lookup -Wl,-headerpad_max_install_names -Wl,-rpath,@loader_path/../lib/$(notdir $(SWI_LIBDIR))
SWI_LINK = -lswipl
else
LINK_FLAGS = -shared -pthread -Wl,-rpath,'$$ORIGIN/../lib/$(notdir $(SWI_LIBDIR))' -ldl
SWI_LINK = -lswipl
endif

$(TARGET): c_src/swi_nif.c
	$(CC) $(CFLAGS) -std=c11 -fPIC -I"$(ERL_INCLUDE)" -I"$(SWI_HOME)/include" $< -o "$@" -L"$(SWI_LIBDIR)" $(LINK_FLAGS) $(SWI_LINK)

.PHONY: clean
clean:
	rm -f "$(SWI_HOME)/bin/swi_nif.so" "$(SWI_HOME)/bin/swi_nif.dll"
