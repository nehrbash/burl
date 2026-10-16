.PHONY: check check-lifecycle
check:
	node --test tests/burl-*.mjs
	cmake -S . -B build/cli-check -G Ninja -DENABLE_MODULES=cli -DVERSION=0 -DGIT_REVISION=dev
	ninja -C build/cli-check
	ctest --test-dir build/cli-check --output-on-failure
	@for file in tests/hyprland-*.lua; do lua "$$file" || exit 1; done
check-lifecycle:
	RUN_QML_MOUSE=1 node --test tests/burl-mouse-settings-runtime.mjs
	RUN_QML_EFFECTS=1 node --test tests/burl-compositor-effects-runtime.mjs
	./scripts/qs-navigation-state.sh
	./scripts/qs-world-lifecycle.sh
	./scripts/qs-world-escape.sh
	./scripts/qs-launcher-editing.sh
	./scripts/qs-launcher-cycle.sh
	./scripts/qs-file-search-cycle.sh
	./scripts/qs-atmosphere-cycle.sh

check-burl:
	@files="$(FILES)"; \
	if [ -z "$$files" ]; then \
	  files=$$(git diff --name-only --diff-filter=ACMR HEAD -- '**/*.qml'); \
	fi; \
	if [ -z "$$files" ]; then echo "check-burl: no changed QML"; exit 0; fi; \
	status=0; \
	for f in $$files; do \
	  if grep -q '^pragma Singleton' "$$f" 2>/dev/null; then \
	    ./scripts/qs-smoke.sh --singleton "$$f" || status=1; \
	  else \
	    ./scripts/qs-smoke.sh "$$f" || status=1; \
	  fi; \
	done; \
	exit $$status
