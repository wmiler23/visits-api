# Every command the pipeline runs is a make target, so you can run the same
# thing on your laptop before you push.
SHELL := /bin/bash
PYTHON ?= python3

.PHONY: help install lint lint-cfn lint-sh lint-workflows test check package bootstrap github teardown clean

help:  ## Show the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

install:  ## Install lint and test tools into the current Python environment
	$(PYTHON) -m pip install -r requirements-dev.txt

lint: lint-cfn lint-sh lint-workflows  ## Run every linter

lint-cfn:  ## cfn-lint on all templates (paths in .cfnlintrc.yaml)
	cfn-lint

lint-sh:  ## shellcheck on the scripts
	shellcheck -x scripts/*.sh

lint-workflows:  ## actionlint on .github/workflows (also shellchecks run: blocks)
	actionlint

test:  ## Unit tests (no AWS needed: DynamoDB is mocked)
	$(PYTHON) -m pytest

check: lint test  ## What CI runs on a pull request

package:  ## Build dist/app.zip
	$(PYTHON) scripts/package.py dist/app.zip

bootstrap:  ## One-time AWS setup (admin credentials)
	scripts/bootstrap_aws.sh

github:  ## One-time GitHub setup (environments, secrets, branch protection)
	scripts/configure_github.sh

teardown:  ## Delete everything in AWS
	scripts/teardown.sh

clean:  ## Remove build output
	rm -rf dist .pytest_cache
	find . -name __pycache__ -type d -prune -exec rm -rf {} +
