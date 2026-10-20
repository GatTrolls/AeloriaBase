--!strict
--[[
	Fx

	Soft light effects from one small atlas: glows, rays, rings, sparkles, a falling star. They are
	white on transparent, so ImageColor3 gives them any colour, and they are the reason banners and
	wish results glow instead of looking flat. Like Icons, a missing atlas just means no effect.

	Slots are fixed: never reorder, only append.
]]

local Fx = {}

Fx.atlas = {
	image = "rbxassetid://129048485702322",
	cell = 256,
	columns = 4,
}

local NAMES = {
	"glow",
	"rays",
	"ring",
	"sparkle4",
	"sparkle8",
	"dot",
	"streak",
	"shine",
	"vignette",
	"bokeh",
	"star",
	"fallingStar",
	"swirl",
	"flare",
	"ringDouble",
	"burst",
}

local index: { [string]: number } = {}
for position, name in NAMES do
	index[name] = position - 1
end

function Fx.apply(label: ImageLabel, name: string): boolean
	local cell = index[name]
	if Fx.atlas.image == "" or cell == nil then
		return false
	end
	local atlas = Fx.atlas
	label.Image = atlas.image
	label.ImageRectSize = Vector2.new(atlas.cell, atlas.cell)
	label.ImageRectOffset =
		Vector2.new((cell % atlas.columns) * atlas.cell, math.floor(cell / atlas.columns) * atlas.cell)
	return true
end

export type Props = {
	parent: Instance?,
	name: string?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	color: Color3?,
	transparency: number?,
	rotation: number?,
	z: number?,
}

-- An effect sprite as a ready-made ImageLabel.
function Fx.image(effect: string, props: Props): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Active = false
	Fx.apply(image, effect)
	image.ImageColor3 = props.color or Color3.new(1, 1, 1)
	image.ImageTransparency = props.transparency or 0
	image.Size = props.size or UDim2.fromOffset(100, 100)
	image.Position = props.position or UDim2.new()
	image.AnchorPoint = props.anchor or Vector2.new(0.5, 0.5)
	image.Rotation = props.rotation or 0
	image.Name = props.name or effect
	if props.z then
		image.ZIndex = props.z
	end
	image.Parent = props.parent
	return image
end

return Fx
