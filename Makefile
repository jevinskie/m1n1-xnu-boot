ARCH ?= aarch64-none-elf-

ifeq ($(shell uname),DarwinIgnoreMe)
USE_CLANG ?= 1
$(info INFO: Building on Darwin)
ifeq ($(shell uname -p),arm)
TOOLCHAIN ?= /opt/homebrew/opt/llvm/bin/
else
TOOLCHAIN ?= /usr/local/opt/llvm/bin/
endif
$(info INFO: Toolchain path: $(TOOLCHAIN))
endif

ifeq ($(USE_CLANG),1)
CC := $(TOOLCHAIN)clang --target=$(ARCH)
CXX := $(TOOLCHAIN)clang++ --target=$(ARCH)
AS := $(TOOLCHAIN)clang --target=$(ARCH)
AR := $(TOOLCHAIN)llvm-ar --target=$(ARCH)
LD := $(TOOLCHAIN)ld.lld
OBJCOPY := $(TOOLCHAIN)llvm-objcopy
CLANG_FORMAT := $(TOOLCHAIN)clang-format
EXTRA_CFLAGS ?=
else
CC := $(TOOLCHAIN)$(ARCH)gcc
CXX := $(TOOLCHAIN)$(ARCH)g++
AS := $(TOOLCHAIN)$(ARCH)gcc
AR := $(TOOLCHAIN)$(ARCH)ar
LD := $(TOOLCHAIN)$(ARCH)ld
OBJCOPY := $(TOOLCHAIN)$(ARCH)objcopy
CLANG_FORMAT := clang-format
EXTRA_CFLAGS ?= -Wstack-usage=1024
endif

CFLAGS := -O2 -Wall -g -Wundef -Werror=strict-prototypes -fno-common -fno-PIE \
	-Werror=implicit-function-declaration -Werror=implicit-int \
	-Wsign-compare -Wunused-parameter -Wno-multichar \
	-ffreestanding -fpic -ffunction-sections -fdata-sections \
	-nostdinc -isystem $(shell $(CC) -print-file-name=include) -isystem sysinc \
	-fno-stack-protector -mgeneral-regs-only -mstrict-align -march=armv8.2-a \
	$(EXTRA_CFLAGS)

CFLAGS += -I jevmachopp/include

LDFLAGS := -T m1n1.ld -EL -maarch64elf --no-undefined -X -Bsymbolic \
	-z notext --no-apply-dynamic-relocs --orphan-handling=warn \
	-z nocopyreloc --gc-sections -pie

MINILZLIB_OBJECTS := $(patsubst %,minilzlib/%, \
	dictbuf.o inputbuf.o lzma2dec.o lzmadec.o rangedec.o xzstream.o)

TINF_OBJECTS := $(patsubst %,tinf/%, \
	adler32.o crc32.o tinfgzip.o tinflate.o tinfzlib.o)

DLMALLOC_OBJECTS := dlmalloc/malloc.o

LIBFDT_OBJECTS := $(patsubst %,libfdt/%, \
	fdt_addresses.o fdt_empty_tree.o fdt_ro.o fdt_rw.o fdt_strerror.o fdt_sw.o \
	fdt_wip.o fdt.o)

OBJECTS := \
	adt.o \
	aic.o \
	bootlogo_128.o bootlogo_256.o \
	chickens.o \
	cpufreq.o \
	dart.o \
	exception.o exception_asm.o \
	fb.o font.o font_retina.o \
	gxf.o gxf_asm.o \
	heapblock.o \
	hv.o hv_vm.o hv_exc.o hv_vuart.o hv_wdt.o hv_asm.o hv_aic.o \
	i2c.o \
	iodev.o \
	kboot.o \
	main.o \
	mcc.o \
	memory.o memory_asm.o \
	payload.o \
	pcie.o \
	pmgr.o \
	proxy.o \
	ringbuffer.o \
	smp.o \
	start.o \
	startup.o \
	string.o \
	tunables.o \
	tps6598x.o \
	uart.o \
	uartproxy.o \
	usb.o usb_dwc3.o \
	utils.o utils_asm.o \
	vsprintf.o \
	wdt.o \
	$(MINILZLIB_OBJECTS) $(TINF_OBJECTS) $(DLMALLOC_OBJECTS) $(LIBFDT_OBJECTS)

DTS := t8103-j274.dts

BUILD_OBJS := $(patsubst %,build/%,$(OBJECTS))
DTBS := $(patsubst %.dts,build/dtb/%.dtb,$(DTS))

NAME := m1n1
TARGET := m1n1.macho

DEPDIR := build/.deps
ROOTDIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))

.PHONY: all clean format update_tag jevmachopp
all: build/$(TARGET) $(DTBS)
clean:
	rm -rf build/*
format:
	$(CLANG_FORMAT) -i src/*.c src/*.h sysinc/*.h
format-check:
	$(CLANG_FORMAT) --dry-run --Werror src/*.c src/*.h sysinc/*.h

build/dtb/%.dts: dts/%.dts
	@echo "  DTCPP $@"
	@mkdir -p "$(dir $@)"
	$(CC) -E -nostdinc -I dts -x assembler-with-cpp -o $@ $<

build/dtb/%.dtb: build/dtb/%.dts
	@echo "  DTC   $@"
	@mkdir -p "$(dir $@)"
	dtc -I dts -i dts $< -o $@

build/%.o: src/%.S
	@echo "  AS    $@"
	@mkdir -p $(DEPDIR)
	@mkdir -p "$(dir $@)"
	$(AS) -c $(CFLAGS) -MMD -MF $(DEPDIR)/$(*F).d -MQ "$@" -MP -o $@ $<

build/%.o: src/%.c
	@echo "  CC    $@"
	@mkdir -p $(DEPDIR)
	@mkdir -p "$(dir $@)"
	$(CC) -c $(CFLAGS) -MMD -MF $(DEPDIR)/$(*F).d -MQ "$@" -MP -o $@ $<

build/$(NAME).elf: $(BUILD_OBJS) build/jevmachopp/libjevmachopp.a m1n1.ld
	@echo "  LD    $@"
	$(LD) $(LDFLAGS) -o $@ $(BUILD_OBJS) build/jevmachopp/libjevmachopp.a

build/$(NAME).macho: build/$(NAME).elf
	@echo "  MACHO $@"
	$(OBJCOPY) -O binary --strip-debug $< $@

update_tag:
	@echo "#define BUILD_TAG \"$$(git describe --always --dirty)\"" > build/build_tag.tmp
	@cmp -s build/build_tag.h build/build_tag.tmp 2>/dev/null || \
	( mv -f build/build_tag.tmp build/build_tag.h && echo "  TAG   build/build_tag.h" )

build/build_tag.h: update_tag

build/%.bin: data/%.png
	@echo "  IMG   $@"
	@convert $< -background black -flatten -depth 8 rgba:$@

build/%.o: build/%.bin
	@echo "  BIN   $@"
	@$(OBJCOPY) -I binary -B aarch64 -O elf64-littleaarch64 $< $@

build/%.bin: font/%.bin
	@echo "  CP    $@"
	@cp $< $@

build/main.o: build/build_tag.h src/main.c
build/usb_dwc3.o: build/build_tag.h src/usb_dwc3.c

-include jevmachopp/Makefile

-include $(DEPDIR)/*
