.PHONY: all run gdb clean latest $(ALL)

RESULT = .result
$(shell > $(RESULT))

COLOR_RED   = \033[1;31m
COLOR_GREEN = \033[1;32m
COLOR_NONE  = \033[0m

# 默认路径（避免 AM_HOME 未设置导致 include /Makefile）
AM_HOME  ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../abstract-machine)
SIM_HOME ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../simulator)

ALL = $(basename $(notdir $(shell find tests/. -name "*.c")))

all: $(addprefix Makefile., $(ALL))
	@echo "test list [$(words $(ALL)) item(s)]:" $(ALL)

$(ALL): %: Makefile.%

Makefile.%: tests/%.c latest
	@/bin/echo -e "NAME = $*\nSRCS = $<\nAM_HOME := $(AM_HOME)\nSIM_HOME := $(SIM_HOME)\ninclude $(AM_HOME)/Makefile" > $@
	@if make -s -f $@ ARCH=$(ARCH) image; then \
		printf "[%14s] $(COLOR_GREEN)PASS$(COLOR_NONE)\n" $* >> $(RESULT); \
	else \
		printf "[%14s] $(COLOR_RED)***FAIL***$(COLOR_NONE)\n" $* >> $(RESULT); \
	fi
	-@rm -f Makefile.$*

run: all
	@cat $(RESULT)
	@rm $(RESULT)
sim:
	gtkwave $(SIM_HOME)/waveform.vcd

gdb: all

clean:
	rm -rf Makefile.* build/

latest:
