#' Round-trip a raster through a reprojection
#'
#' Exists only to give the self-test something that touches proj.db.
#'
#' @return A reprojected `SpatRaster`.
#' @export
fixture_reproject <- function() {
  r <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 1,
                   ymin = 0, ymax = 1, crs = "EPSG:4326")
  terra::values(r) <- seq_len(16)
  terra::project(r, "EPSG:3857")
}
