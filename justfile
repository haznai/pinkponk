default:
  just --list

pre-commit:
  ruff format src
  ruff check src
  pyright

