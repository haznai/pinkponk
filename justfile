default:
    just --list

pre-commit: format test

format:
    swift format . --recursive --in-place

test:
  tuist test

edit:
  tuist edit

generate:
  tuist generate
  

build:
  tuist build

update-schema:
    sqlite3def pinkponk/db/data.db < pinkponk/db/schema.sqlschema

delete-derived-data:
    rm -rf ~/Library/Developer/Xcode/DerivedData/
