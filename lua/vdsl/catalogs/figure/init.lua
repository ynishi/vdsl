--- Pack: Figure — human/creature figure vocabulary.
-- Catalogs for body position, gaze, gesture, and facial expression.
--
-- Access: catalogs.figure.pose.standing, catalogs.figure.expression.smile
-- Eager-loaded: pairs(catalogs.figure) enumerates all sub-catalogs.

return {
  pose       = require("vdsl.catalogs.figure.pose"),
  expression = require("vdsl.catalogs.figure.expression"),
  body       = require("vdsl.catalogs.figure.body"),
  hair       = require("vdsl.catalogs.figure.hair"),
  eyes       = require("vdsl.catalogs.figure.eyes"),
  species    = require("vdsl.catalogs.figure.species"),
  accessory  = require("vdsl.catalogs.figure.accessory"),
  clothing   = require("vdsl.catalogs.figure.clothing"),
}
