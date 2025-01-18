default:
  just --list

pre-commit: test
  ruff format src
  ruff check src
  pyright
  tryceratops src

test:
  pytest
