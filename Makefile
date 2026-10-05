.DEFAULT_GOAL := help

help:
	@awk 'BEGIN {FS = ":.*##"} \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next } \
		/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

##@ Start here — one entry point per direction
run:     ## Run the app locally
	python3 app/main.py
deploy:  ## Deploy (manual / docker / cloud)
	@echo "TODO: deployment entry point"
monitor: ## Tail logs / health (monitoring)
	@echo "TODO: monitoring entry point"
debug:   ## Run with verbose logging / replay (debugging)
	@echo "TODO: debugging entry point"
check:   ## Tests + lint (quality & continuous development)
	@echo "TODO: quality / dev entry point"

##@ More
setup:   ## Install dependencies
	@echo "TODO: dependency install (uv sync / pip install -r requirements.txt)"

.PHONY: help run deploy monitor debug check setup
