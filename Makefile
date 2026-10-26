.PHONY: smoke full lint
smoke:
	python3 tools/regress.py smoke $(REGRESS_ARGS)
full:
	python3 tools/regress.py full $(REGRESS_ARGS)
lint:
	python3 tools/check/verilog_style.py rtl/
	@set -e; for source in rtl/common/*.v; do tools/check/lint.sh -Irtl/common "$$source"; done
