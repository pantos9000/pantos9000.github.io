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
