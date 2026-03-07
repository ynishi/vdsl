--- Pack: Color — cross-cutting color vocabulary.
-- Catalogs for color palette, temperature, and saturation control.
--
-- Access: catalogs.color.palette.monochrome, catalogs.color.palette.warm_tones
-- Eager-loaded: pairs(catalogs.color) enumerates all sub-catalogs.

return {
  palette = require("vdsl.catalogs.color.palette"),
  hue     = require("vdsl.catalogs.color.hue"),
}
