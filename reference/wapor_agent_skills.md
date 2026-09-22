# Load the Rwapor Agent Skills Reference

Returns the path to (or content of) the canonical agent skills markdown
file that describes available workflows, data sources, and preprocessing
steps for the Rwapor package. Intended for use with AI coding assistants
(e.g., Claude Code, GitHub Copilot) — load this text into the
assistant's context to enable package-aware suggestions.

## Usage

``` r
wapor_agent_skills(as_text = TRUE)
```

## Arguments

- as_text:

  Logical. If `TRUE` (default), returns the file content as a single
  character string. If `FALSE`, returns only the file path.

## Value

Character. The full markdown text (`as_text = TRUE`) or the file path
(`as_text = FALSE`).

## AI assistant usage

Pass the returned text as context to an LLM:

    skills_text <- wapor_agent_skills()
    # paste skills_text into your AI assistant's context window

## Examples

``` r
# Get path (e.g., to pass to an LLM context loader)
path <- wapor_agent_skills(as_text = FALSE)

# Read content directly
skills_text <- wapor_agent_skills()
cat(substr(skills_text, 1, 300))
#> # Rwapor Agent Skills Reference
#> 
#> > **For AI Agents**: This file is the canonical guide for using the Rwapor R package in automated analysis workflows. Read this first. It tells you which functions to call, in what order, with what inputs, and what to watch out for. All code blocks are executable R; 
```
