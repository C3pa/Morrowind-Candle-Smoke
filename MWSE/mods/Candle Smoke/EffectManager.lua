local inspect = require("inspect")

local Class = require("Candle Smoke.Class")
local smokeOffset = require("Candle Smoke.data").smokeOffset
local util = require("Candle Smoke.util")


local log = mwse.Logger.new()
local BASEPATH = "e\\taitech\\candlesmoke_%d.nif"
local OFFSET = tes3vector3.new(0, 0, -2)
local parentNodeName = "CandleFlame Emitter"

-- A cache of loaded smoke effect meshes
--- @type table<string, niNode>
local loadedEffect = {}


---@class CandleSmoke.EffectManager
---@field activeEffects table<tes3reference, niNode[]>
---@field phase integer
local EffectManager = Class:new()

--- @return CandleSmoke.EffectManager
function EffectManager:new()
	local t = Class:new()
	setmetatable(t, self)

	t.activeEffects = {}
	t.phase = 1

	self.__index = self
	return t
end

--- Used to keep track of which smoke asset (of the 3 available) to spawn.
---@private
---@return integer newPhase
function EffectManager:incrementPhase()
	self.phase = self.phase + 1
	if self.phase > 3 then
		self.phase = 1
	end
	return self.phase
end

---@param color mwseColorTable
function EffectManager:updateEffectMaterial(color)
	-- Update the color of the already spawned vfx.
	for light, effects in pairs(self.activeEffects) do
		for _, effect in ipairs(effects) do
			util.updateNodeEmissive(effect, color)
		end
		util.updateNode(light.sceneNode)
	end

	-- Update the color of the loaded vfx.
	for _, effect in pairs(loadedEffect) do
		util.updateNodeEmissive(effect, color)
	end
end

---@private
---@param light tes3reference
---@param offsets tes3vector3[]?
function EffectManager:spawnSmokeVFX(light, offsets)
	if not offsets then
		log:info("No smoke offsets for %q.", light.mesh)
		return false
	end

	for node in table.traverse({ light.sceneNode }) do
		if node.name == parentNodeName then
			local path = string.format(BASEPATH, self:incrementPhase())
			local effect = loadedEffect[path]
			if not effect then
				loadedEffect[path] = tes3.loadMesh(path) --[[@as niNode]]
				effect = loadedEffect[path]
				effect.name = path
				-- Update loaded emissive color to the currently selected value.
				util.updateNodeEmissive(effect, util.getEmissiveColorFromConfig())
			end
			effect = effect:clone() --[[@as niNode]]
			effect.translation = OFFSET:copy()
			node:attachChild(effect)
			if not self.activeEffects[light] then
				self.activeEffects[light] = {}
			end
			table.insert(self.activeEffects[light], effect)
		end
	end
	util.updateNode(light.sceneNode)
end

---@param reference tes3reference
---@return boolean spawnedSmoke
function EffectManager:applyCandleSmokeEffect(reference)
	if not util.isLanternValid(reference) then
		return false
	end

	-- Don't apply the effect twice.
	if self.activeEffects[reference] then
		return false
	end
	local light = reference.object --[[@as tes3light]]
	local mesh = util.sanitizeMesh(light.mesh)
	local offsets = smokeOffset[mesh]
	return self:spawnSmokeVFX(reference, offsets)
end

---@private
function EffectManager:applySmokeOnAllCandles()
	for _, light in ipairs(util.getLights()) do
		self:applyCandleSmokeEffect(light)
	end
end


---@param light tes3reference
function EffectManager:detachSmokeEffect(light)
	local effects = self.activeEffects[light]
	if not effects then return end
	log:debug("Detaching smoke from: %q.", light.id)
	for _, effect in ipairs(effects) do
		effect.parent:detachChild(effect)
	end
	util.updateNode(light.sceneNode)
	self.activeEffects[light] = nil
end

---@private
function EffectManager:detachAllSmokeEffects()
	for light, _ in pairs(self.activeEffects) do
		self:detachSmokeEffect(light)
	end
end

function EffectManager:onCellChanged()
	log:trace("onCellChanged: before activeEffects = %s", inspect(self.activeEffects))
	self:applySmokeOnAllCandles()
	log:trace("onCellChanged: after activeEffects = %s", inspect(self.activeEffects))
end

-- Apply smoke effect if the player dropped a candle
-- TODO: remove
---@param e itemDroppedEventData
function EffectManager:onItemDropped(e)
	local ref = e.reference
	local object = ref.object
	if object.objectType ~= tes3.objectType.light then return end
	self:applyCandleSmokeEffect(ref)
end

return EffectManager
