SHELL := /bin/bash

.PHONY: help install uninstall verify doctor test temporal-dev taskd

define SKIP_FLAGS
SKIP_NORM=" $(SKIP) "; \
SKIP_NORM="$${SKIP_NORM//,/ }"; \
SKIP_FLAGS=""; \
if [[ "$$SKIP_NORM" =~ [[:space:]]claude[[:space:]] ]]; then SKIP_FLAGS+=" --no-claude"; fi; \
if [[ "$$SKIP_NORM" =~ [[:space:]]codex[[:space:]] ]]; then SKIP_FLAGS+=" --no-codex"; fi; \
if [[ "$$SKIP_NORM" =~ [[:space:]]gemini[[:space:]] ]]; then SKIP_FLAGS+=" --no-gemini"; fi;
endef

help:
	@echo "Targets:"
	@echo "  install   Install loopy> for Claude/Codex/Gemini"
	@echo "  uninstall Remove loopy> from Claude/Codex/Gemini"
	@echo "  verify    Verify dependencies and installation"
	@echo "  doctor    Install then verify (best-effort sanity check)"
	@echo "  test      Run installer tests (isolated temp dirs)"
	@echo "  temporal-dev  Start a local Temporal dev server"
	@echo "  taskd     Start the loopy task worker"
	@echo ""
	@echo "Options:"
	@echo "  SKIP=claude,codex,gemini   Skip one or more targets"

install:
	@$(SKIP_FLAGS) \
	./scripts/install.sh $$SKIP_FLAGS

uninstall:
	@$(SKIP_FLAGS) \
	./scripts/install.sh --uninstall $$SKIP_FLAGS

verify:
	@$(SKIP_FLAGS) \
	./scripts/verify.sh $$SKIP_FLAGS

doctor:
	@$(SKIP_FLAGS) \
	./scripts/install.sh $$SKIP_FLAGS; \
	./scripts/verify.sh $$SKIP_FLAGS

test:
	@./scripts/test.sh

temporal-dev:
	@./scripts/temporal-dev.sh

taskd:
	@loopy-taskd
