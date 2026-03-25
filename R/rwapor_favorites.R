#' Get Path to Rwanda WaPOR Favorites File
#'
#' @return Character path to the favorites JSON file
#' @keywords internal
get_favorites_path <- function() {
  file.path(Sys.getenv("USERPROFILE") %||% Sys.getenv("HOME"), ".rwapor_favorites.json")
}

#' Load Favorites from Local Storage
#'
#' @return A data frame of favorites with 'path' and 'type' columns
#' @export
rwapor_get_favorites <- function() {
  path <- get_favorites_path()
  if (!file.exists(path)) {
    return(data.frame(path = character(0), type = character(0), stringsAsFactors = FALSE))
  }
  
  tryCatch({
    favs <- jsonlite::fromJSON(path)
    if (!is.data.frame(favs)) {
      return(data.frame(path = character(0), type = character(0), stringsAsFactors = FALSE))
    }
    favs
  }, error = function(e) {
    data.frame(path = character(0), type = character(0), stringsAsFactors = FALSE)
  })
}

#' Add a Path to Favorites
#'
#' @param path Character. Path to a directory or file.
#' @param type Character. One of "directory" or "file".
#' @return Logical. TRUE if successful.
#' @export
rwapor_add_favorite <- function(path, type = c("directory", "file")) {
  type <- match.arg(type)
  if (is.null(path) || !nzchar(path)) return(FALSE)
  
  # Normalize path
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  
  favs <- rwapor_get_favorites()
  
  if (path %in% favs$path) {
    return(TRUE) # Already exists
  }
  
  new_favs <- rbind(favs, data.frame(path = path, type = type, stringsAsFactors = FALSE))
  
  tryCatch({
    jsonlite::write_json(new_favs, get_favorites_path(), pretty = TRUE)
    TRUE
  }, error = function(e) FALSE)
}

#' Remove a Path from Favorites
#'
#' @param path Character. Path to remove.
#' @return Logical. TRUE if successful.
#' @export
rwapor_remove_favorite <- function(path) {
  if (is.null(path) || !nzchar(path)) return(FALSE)
  
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  favs <- rwapor_get_favorites()
  
  if (!path %in% favs$path) {
    return(TRUE) # Already removed
  }
  
  new_favs <- favs[favs$path != path, ]
  
  tryCatch({
    jsonlite::write_json(new_favs, get_favorites_path(), pretty = TRUE)
    TRUE
  }, error = function(e) FALSE)
}

#' Check if a Path is Favorited
#'
#' @param path Character. Path to check.
#' @return Logical. TRUE if favorited.
#' @export
rwapor_is_favorite <- function(path) {
  if (is.null(path) || !nzchar(path)) return(FALSE)
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  favs <- rwapor_get_favorites()
  path %in% favs$path
}
