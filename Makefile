# pascal-polycall -- GNU Make + Free Pascal (fpc >= 3.2). The unit declares
# the core's functions as cdecl externals of library 'polycall'; the linker
# finds libpolycall through pkg-config (PKG_CONFIG_PATH=<prefix>/lib/pkgconfig).
FPC ?= fpc
PKG_CONFIG ?= pkg-config

POLYCALL_LIBDIR ?= $(shell $(PKG_CONFIG) --variable=libdir polycall 2>/dev/null)
PASCALFLAGS ?= -Mobjfpc -Sh -O2 -gl
FPC_LIBFLAGS := $(if $(strip $(POLYCALL_LIBDIR)),-Fl$(POLYCALL_LIBDIR))

BUILD_DIR := build
UNIT_DIR := $(BUILD_DIR)/units
TEST_BIN := $(BUILD_DIR)/pascal_polycall_test
LOADER_BIN := $(BUILD_DIR)/loader_check
EXAMPLE_BIN := $(BUILD_DIR)/basic

ifeq ($(OS),Windows_NT)
TEST_BIN := $(TEST_BIN).exe
LOADER_BIN := $(LOADER_BIN).exe
EXAMPLE_BIN := $(EXAMPLE_BIN).exe
endif

VALGRIND ?= valgrind
VALGRIND_FLAGS ?= --error-exitcode=99 --leak-check=full --errors-for-leak-kinds=definite --track-origins=yes

.DEFAULT_GOAL := all

# A missing compiler is a SKIP (exit 77), never a success.
.PHONY: check-toolchain
check-toolchain:
	@command -v $(FPC) >/dev/null 2>&1 || { echo "SKIP: Free Pascal compiler '$(FPC)' not found"; exit 77; }

.PHONY: check-core
check-core:
	@test -n "$(POLYCALL_LIBDIR)" || { echo "pascal-polycall: pkg-config cannot find polycall (>= 1.1.0); set PKG_CONFIG_PATH=<prefix>/lib/pkgconfig" >&2; exit 2; }

$(UNIT_DIR):
	@mkdir -p $@

.PHONY: all pascal
all pascal: check-toolchain | $(UNIT_DIR)
	$(FPC) $(PASCALFLAGS) -Fusrc -FU$(UNIT_DIR) src/PascalPolycall.pas

.PHONY: build-tests
build-tests: check-toolchain check-core | $(UNIT_DIR)
	$(FPC) $(PASCALFLAGS) $(FPC_LIBFLAGS) -Fusrc -FU$(UNIT_DIR) -FE$(BUILD_DIR) \
		-o$(TEST_BIN) tests/pascal_polycall_test.pas

# Real-core test incl. interop with the C CLI (exit 77 = SKIP without it).
.PHONY: test test-pascal
test test-pascal: build-tests
	sh tests/run-real.sh $(TEST_BIN) .

# Missing library, old library without ABI v1 symbols, ABI mismatch
# (Linux; exit 77 = SKIP elsewhere). See tests/loader-errors.sh.
.PHONY: test-loader
test-loader: check-toolchain check-core | $(UNIT_DIR)
	$(FPC) $(PASCALFLAGS) $(FPC_LIBFLAGS) -Fusrc -FU$(UNIT_DIR) -FE$(BUILD_DIR) \
		-o$(LOADER_BIN) tests/loader_check.pas
	sh tests/loader-errors.sh $(LOADER_BIN) .

# The real-core test under valgrind memcheck (exit 77 = SKIP without it).
.PHONY: memcheck
memcheck: build-tests
	@command -v $(VALGRIND) >/dev/null 2>&1 || { echo "SKIP: $(VALGRIND) not found"; exit 77; }
	sh tests/run-real.sh $(VALGRIND) $(VALGRIND_FLAGS) $(TEST_BIN) .

.PHONY: example
example: check-toolchain check-core | $(UNIT_DIR)
	$(FPC) $(PASCALFLAGS) $(FPC_LIBFLAGS) -Fusrc -FU$(UNIT_DIR) -FE$(BUILD_DIR) \
		-o$(EXAMPLE_BIN) examples/basic.pas
	$(EXAMPLE_BIN)

.PHONY: verify-dry
verify-dry:
	sh scripts/verify-dry.sh

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR) lib
