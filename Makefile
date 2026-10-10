.PHONY: check check-lifecycle
check:
	node --test tests/burl-*.mjs
	python3 tests/theme-schemes.py
	python3 tests/theme-hyprland.py
	@for file in tests/hyprland-*.lua; do lua "$$file" || exit 1; done
check-lifecycle:
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
