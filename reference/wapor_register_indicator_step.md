# Register an Indicator Step

Register an Indicator Step

## Usage

``` r
wapor_register_indicator_step(
  name,
  step_fn,
  depends = character(0),
  description = ""
)
```

## Arguments

- name:

  Character. Unique identifier of the indicator step.

- step_fn:

  Function. Step execution function accepting `ctx`.

- depends:

  Character vector. Optional prerequisite step names.

- description:

  Character. Human-readable description.

## Value

Invisible list of registered steps.
