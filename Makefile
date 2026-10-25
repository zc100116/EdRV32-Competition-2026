.PHONY: smoke full lint
smoke:
	python3 tools/regress.py smoke
full:
	python3 tools/regress.py full
lint:
	python3 tools/check/verilog_style.py rtl/
	@set -e; for source in rtl/common/*.v; do tools/check/lint.sh -Irtl/common "$$source"; done
