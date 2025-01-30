default:
  just --list

pre-commit: format test

format: 
  swift format pinkponk --recursive --in-place

test:
  xcodebuild test
