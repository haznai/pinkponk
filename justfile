default:
  just --list

pre-commit: format test

format: 
  swift format pinkponk --recursive --in-place

test:
  xcodebuild test

update-schema:
  sqlite3def pinkponk/db/data.db < pinkponk/db/schema.sql
