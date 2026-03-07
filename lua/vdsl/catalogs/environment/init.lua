--- Pack: Environment — scene and setting vocabulary.
-- Catalogs for location, weather, and temporal context.
--
-- Access: catalogs.environment.setting.forest, catalogs.environment.weather.rain
-- Eager-loaded: pairs(catalogs.environment) enumerates all sub-catalogs.

return {
  setting = require("vdsl.catalogs.environment.setting"),
  weather = require("vdsl.catalogs.environment.weather"),
  time    = require("vdsl.catalogs.environment.time"),
}
