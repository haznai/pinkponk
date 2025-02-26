default:
    just --list

pre-commit: format test static-analysis

format:
    swift format . --recursive --in-place

test:
  tuist test --retry-count 1

static-analysis:
  rg todo

edit:
  tuist edit

generate:
  tuist generate

build:
  tuist build

tres-panos:
  tmuxinator local

update-schema:
    devbox run sqlite3def  ~/Documents/db.sqlite  < pinkponk/Resources/ApplicationDatabase.sql
    @echo -e "\033[1;31mWarning: The ApplicationDatabase.swift file now has to be recreated.\033[0m"

delete-derived-data:
    sudo rm -rf ~/Library/Developer/Xcode/DerivedData/

start-console:
  devbox run npm run claude
