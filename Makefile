SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo Check Makefile for targets.

.PHONY: build
build:
	@echo ==== MAKE BUILD ====
	zola build

.PHONY: serve
serve:
	@echo ==== MAKE SERVE ====
	zola serve

.PHONY: mdl
mdl:
	@echo === MAKE mdl ====
	mdl -s markdownlint.rb $(shell find -iname "*.md" -not -path "./themes/*")
