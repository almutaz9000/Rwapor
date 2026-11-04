test_that("map file-set publication replaces outputs after staging succeeds", {
  root <- withr::local_tempdir()
  stage_dir <- file.path(root, "stage")
  dir.create(stage_dir)
  targets <- file.path(root, c("one.tif", "two.tif"))
  staged <- file.path(stage_dir, basename(targets))
  writeLines("old one", targets[[1]])
  writeLines("old two", targets[[2]])
  writeLines("new one", staged[[1]])
  writeLines("new two", staged[[2]])

  result <- Rwapor:::.wapor_publish_file_set(staged, targets)

  expect_identical(result, targets)
  expect_identical(readLines(targets[[1]]), "new one")
  expect_identical(readLines(targets[[2]]), "new two")
  expect_false(any(file.exists(staged)))
  expect_length(list.files(root, pattern = "[.]backup$"), 0L)
})

test_that("map file-set publication rolls back earlier replacements after failure", {
  root <- withr::local_tempdir()
  stage_dir <- file.path(root, "stage")
  dir.create(stage_dir)
  targets <- file.path(root, c("one.tif", "two.tif"))
  staged <- file.path(stage_dir, basename(targets))
  writeLines("old one", targets[[1]])
  writeLines("old two", targets[[2]])
  writeLines("new one", staged[[1]])
  writeLines("new two", staged[[2]])

  rename_calls <- 0L
  rename_fn <- function(from, to) {
    rename_calls <<- rename_calls + 1L
    if (rename_calls == 4L) return(FALSE)
    file.rename(from, to)
  }
  expect_error(
    Rwapor:::.wapor_publish_file_set(staged, targets, rename_fn = rename_fn),
    "Could not publish"
  )

  expect_identical(readLines(targets[[1]]), "old one")
  expect_identical(readLines(targets[[2]]), "old two")
  expect_length(list.files(root, pattern = "[.]backup$"), 0L)
})
