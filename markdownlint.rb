# https://github.com/markdownlint/markdownlint/blob/main/docs/RULES.md

all

rule 'MD003', :style => :atx
rule 'MD004', :style => :sublist
rule 'MD007', :indent => 4
rule 'MD009', :br_spaces => 0
rule 'MD010', :ignore_code_blocks => true
exclude_rule 'MD012'
rule 'MD013', :line_length => 100
rule 'MD024', :allow_different_nesting => true
exclude_rule 'MD025'
rule 'MD026', :punctuation => '.,;:'
rule 'MD033', :allowed_elements => 'br'
rule 'MD035', :style => '---'
exclude_rule 'MD041'

