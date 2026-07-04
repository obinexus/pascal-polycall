CC ?= gcc
AR ?= ar
FPC ?= fpc

CPPFLAGS ?=
CPPFLAGS += -Iinclude -Igenerated
CFLAGS ?= -O2
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic
PASCALFLAGS ?= -Mobjfpc -Sh -O2 -gl

BUILD_DIR := build
PASCAL_UNIT_DIR := $(BUILD_DIR)/pascal
LIB_DIR := lib
ADAPTER_OBJ := $(BUILD_DIR)/pascal_polycall.o
MOCK_OBJ := $(BUILD_DIR)/polycall_ffi_mock.o
STATIC_LIB := $(LIB_DIR)/libpascal_polycall.a
TEST_LINK_LIB := $(BUILD_DIR)/libpascal_polycall_test.a
NATIVE_TEST_BIN := $(BUILD_DIR)/pascal_polycall_adapter_test
PASCAL_TEST_BIN := $(BUILD_DIR)/pascal_polycall_smoke

ifeq ($(OS),Windows_NT)
EXE_EXT := .exe
FPC_PATH := $(shell where $(FPC) 2>nul)
else
EXE_EXT :=
FPC_PATH := $(shell command -v $(FPC) 2>/dev/null)
endif

NATIVE_TEST_BIN := $(NATIVE_TEST_BIN)$(EXE_EXT)
PASCAL_TEST_BIN := $(PASCAL_TEST_BIN)$(EXE_EXT)

.DEFAULT_GOAL := all

.PHONY: all
all: $(STATIC_LIB)

$(BUILD_DIR) $(PASCAL_UNIT_DIR) $(LIB_DIR):
ifeq ($(OS),Windows_NT)
	@if not exist "$@" mkdir "$@"
else
	@mkdir -p $@
endif

$(ADAPTER_OBJ): src/pascal_polycall.c include/pascal_polycall.h generated/polycall/polycall_ffi.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(MOCK_OBJ): tests/polycall_ffi_mock.c tests/polycall_ffi_mock.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) -Itests $(CFLAGS) -c $< -o $@

$(STATIC_LIB): $(ADAPTER_OBJ) | $(LIB_DIR)
	$(AR) rcs $@ $^

$(NATIVE_TEST_BIN): src/pascal_polycall.c tests/polycall_ffi_mock.c tests/pascal_polycall_adapter_test.c | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) -Itests $(CFLAGS) $^ -o $@

.PHONY: test
test: $(NATIVE_TEST_BIN)
	$(NATIVE_TEST_BIN)

.PHONY: pascal
pascal: | $(PASCAL_UNIT_DIR)
	$(FPC) $(PASCALFLAGS) -B -Fusrc -FU$(PASCAL_UNIT_DIR) -FE$(BUILD_DIR) src/PascalPolycall.pas

$(TEST_LINK_LIB): $(ADAPTER_OBJ) $(MOCK_OBJ) | $(BUILD_DIR)
	$(AR) rcs $@ $^

.PHONY: test-pascal
test-pascal: pascal $(TEST_LINK_LIB)
	$(FPC) $(PASCALFLAGS) -B -Fusrc -Fu$(PASCAL_UNIT_DIR) -FU$(PASCAL_UNIT_DIR) \
		-FE$(BUILD_DIR) -Fl$(BUILD_DIR) -k-lpascal_polycall_test \
		-o$(PASCAL_TEST_BIN) tests/pascal_polycall_smoke.pas
	$(PASCAL_TEST_BIN)

.PHONY: test-pascal-if-available
ifneq ($(strip $(FPC_PATH)),)
test-pascal-if-available: test-pascal
else
test-pascal-if-available:
	@echo Free Pascal compiler not found; skipping Pascal smoke test
endif

.PHONY: verify-dry
verify-dry:
ifeq ($(OS),Windows_NT)
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-dry.ps1
else
	sh scripts/verify-dry.sh
endif

.PHONY: clean
clean:
ifeq ($(OS),Windows_NT)
	@if exist "$(BUILD_DIR)" rmdir /s /q "$(BUILD_DIR)"
	@if exist "$(LIB_DIR)" rmdir /s /q "$(LIB_DIR)"
else
	rm -rf $(BUILD_DIR) $(LIB_DIR)
endif

-include $(ADAPTER_OBJ:.o=.d)
