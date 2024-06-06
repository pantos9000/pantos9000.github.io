SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo Check Makefile for targets.

.PHONY: build
build:
	@echo ==== MAKE BUILD ====
	zola build

.PHONY: check
check:
	@echo ==== MAKE CHECK ====
	zola check

.PHONY: serve
serve:
	@echo ==== MAKE SERVE ====
	zola serve

.PHONY: mdl
mdl:
	@echo === MAKE mdl ====
	mdl -s markdownlint.rb $(shell find -iname "*.md" -not -path "./themes/*")

.PHONY: ubuntu-install-dependencies
ubuntu-install-dependencies:
	@echo ==== MAKE ubuntu-install-dependencies ====
	sudo apt-get install -y markdownlint
