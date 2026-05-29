--- test_core_entity.lua: CoreEntity lifecycle (Phase 0)
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_core_entity.lua
--
-- Verifies the lifecycle added to the bare type system:
-- Core (value/aggregate) :clone/:with/:equals/:serialize + deserialize roundtrip,
-- Collection member-access + Entity.Collection.* statics, both via one impl.

local Entity = require("vdsl.entity")
local T      = require("harness")

-- ============================================================
-- Core: define_core synthetic entity
-- ============================================================
local Point = Entity.define_core("test_point")
function Point.new(x, y) return setmetatable({ x = x, y = y }, Point) end

local p = Point.new(1, 2)
T.ok("core: is type",        Entity.is(p, "test_point"))
T.eq("core: type_of",        Entity.type_of(p), "test_point")
T.ok("core: is_entity",      Entity.is_entity(p))

-- clone (independent deep copy, keeps type)
local c = p:clone()
T.ok("core: clone equals",   p:equals(c))
T.ok("core: clone is type",  Entity.is(c, "test_point"))
c.x = 99
T.ok("core: clone independent", not p:equals(c))
T.eq("core: orig unchanged", p.x, 1)

-- with (override → new instance, orig untouched)
local w = p:with({ y = 5 })
T.eq("core: with override",  w.y, 5)
T.eq("core: with keeps x",   w.x, 1)
T.eq("core: with orig kept", p.y, 2)
T.ok("core: with is type",   Entity.is(w, "test_point"))
T.err("core: with bad arg",  function() p:with("nope") end)

-- serialize → plain table tagged with _type; deserialize roundtrip
local ser = p:serialize()
T.eq("core: ser type tag",   ser._type, "test_point")
T.eq("core: ser is plain",   getmetatable(ser), nil)
local back = Entity.deserialize("test_point", ser)
T.ok("core: roundtrip eq",   p:equals(back))
T.ok("core: roundtrip type", Entity.is(back, "test_point"))
T.err("core: deser unknown", function() Entity.deserialize("nope_type", {}) end)

-- nested entity serialize/deserialize
local Line = Entity.define_core("test_line")
function Line.new(a, b) return setmetatable({ a = a, b = b }, Line) end
local l  = Line.new(Point.new(0, 0), Point.new(3, 4))
local ls = l:serialize()
T.eq("nested: inner tag",    ls.a._type, "test_point")
local lback = Entity.deserialize("test_line", ls)
T.ok("nested: roundtrip eq", l:equals(lback))
T.ok("nested: inner type",   Entity.is(lback.a, "test_point"))

-- ============================================================
-- Col: define_collection collection (member access + static lifecycle)
-- ============================================================
local PaletteMeta = Entity.define_collection("test_palette")
local pal = setmetatable({ red = "#f00", blue = "#00f" }, PaletteMeta)

T.ok("col: is type",         Entity.is(pal, "test_palette"))
T.eq("col: type_of",         Entity.type_of(pal), "test_palette")
T.eq("col: member access",   pal.red, "#f00")
T.eq("col: miss is nil",     pal.green, nil)
T.eq("col: no method index", pal.serialize, nil)   -- lifecycle is static, not on instance

local pc = Entity.Collection.clone(pal)
T.ok("col: clone equals",    Entity.Collection.equals(pal, pc))
T.eq("col: clone member",    pc.red, "#f00")

local pw = Entity.Collection.with(pal, { green = "#0f0" })
T.eq("col: with adds",       pw.green, "#0f0")
T.eq("col: with keeps",      pw.red, "#f00")
T.eq("col: with orig kept",  pal.green, nil)

local ps = Entity.Collection.serialize(pal)
T.eq("col: ser type tag",    ps._type, "test_palette")
local pback = Entity.deserialize("test_palette", ps)
T.ok("col: roundtrip eq",    Entity.Collection.equals(pal, pback))
T.ok("col: roundtrip type",  Entity.is(pback, "test_palette"))

T.summary()
