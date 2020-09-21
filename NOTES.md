# Development Notes

## How to make a release

- Run all tests
- `bin/bibscrape --help >HELP.txt`
- Commit everything
- Update `version` in `META6.json`
- Commit the edit with message "Version 20.09.21"
- `git tag v20.09.21`
- `git push origin master`
- `git push origin v20.09.21`
  - ?? `git push origin master v20.09.21`
