# Order indicator steps by declared dependencies

Returns a topological order of `wanted` plus any registered
dependencies. Errors if a cycle is present.

## Usage

``` r
wapor_ordered_indicator_steps(wanted)
```

## Arguments

- wanted:

  Character vector of step names to run.

## Value

Character vector of step names, dependencies first.
