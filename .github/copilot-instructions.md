# Rwapor Workspace Instructions

## R Version Requirement

**MANDATORY**: Always use the specified R version for all operations:

- **R Version**: 4.5.3
- **R Path**: `C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3`
- **Rscript Path**: `C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe`

### When Running R Commands

Never use generic `Rscript` command. Always use the full path:

```powershell
# CORRECT
C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe -e "devtools::test()"

# INCORRECT - DO NOT USE
Rscript -e "devtools::test()"
```

### For Terminal Sessions

Set the R path at the beginning of any terminal session:

```powershell
$env:PATH = "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin;" + $env:PATH
```

## Package Development Standards

Refer to [CLAUDE.md](../CLAUDE.md) for complete development guidelines.

### Core Rules
- Use `terra` (not `raster`) for all raster operations
- Never manually edit NAMESPACE - use `devtools::document()`
- Run `devtools::test()` before finalizing changes
- Always use `@export` tag for public functions

## Agent-Specific Notes

All custom agents (Rwapor-dev, Rwapor-test, Rwapor-docs, Rwapor-perf) must use the R 4.5.3 installation specified above when executing R commands.
