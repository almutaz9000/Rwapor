# Run registered indicator steps against a shared context

Executes `ctx$indicators` (and their registered dependencies) in
topological order. Pass `skip` to avoid re-running steps the engine has
already computed.

## Usage

``` r
wapor_run_indicator_steps(ctx, skip = character())
```

## Arguments

- ctx:

  Environment. Must contain `indicators` and `results`.

- skip:

  Character vector of step names to omit.

## Value

The same `ctx`, invisibly, with `results` updated.
