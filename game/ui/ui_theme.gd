class_name UITheme
extends RefCounted
## The Campfire (shell UI): the one Theme every menu/panel/HUD wears.
## Gouache palette lifted from the water shader (color_a/color_b pinks)
## and the paper/ink pair the panels already used. Apply with
## UITheme.apply(control) on each screen's root Control — CanvasLayers
## aren't Controls, so the theme rides the first Control under them.
## Placeholder: StyleBoxFlat panels/buttons → her painted 9-slice
## textures (assets/ui/, same slots) when the UI kit is painted.

const PAPER := Color(0.96, 0.93, 0.865)
const PAPER_DIM := Color(0.93, 0.885, 0.81)
const INK := Color(0.30, 0.17, 0.16)
const INK_SOFT := Color(0.30, 0.17, 0.16, 0.55)
const BORDER := Color(0.45, 0.32, 0.24)
const PINK_DEEP := Color(0.93, 0.55, 0.60)   # water.gdshader color_a
const PINK_SHALLOW := Color(0.99, 0.76, 0.77)  # water.gdshader color_b
const TEAL := Color(0.62, 0.82, 0.80)
const CREAM := Color(1.0, 0.96, 0.9)
const SHADOW := Color(0, 0, 0, 0.7)
const DUSK_DIM := Color(0.08, 0.06, 0.08, 0.72)

static var _theme: Theme


static func theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func apply(root: Control) -> void:
	root.theme = theme()


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16

	# Panels — paper card with a soft painterly drop.
	t.set_stylebox("panel", "PanelContainer", _panel_box())
	t.set_stylebox("panel", "Panel", _panel_box())

	# Labels default to ink (paper panels); HUD overrides to cream itself.
	t.set_color("font_color", "Label", INK)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", 30)
	t.set_color("font_color", "TitleLabel", INK)
	t.set_type_variation("SubtleLabel", "Label")
	t.set_font_size("font_size", "SubtleLabel", 13)
	t.set_color("font_color", "SubtleLabel", INK_SOFT)

	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font_size("normal_font_size", "RichTextLabel", 16)

	# Buttons — ink on cream, pink wash on hover, deep pink when pressed,
	# and a fat pink focus ring so gamepad focus is unmissable.
	t.set_stylebox("normal", "Button", _button_box(PAPER_DIM, BORDER))
	t.set_stylebox("hover", "Button", _button_box(PINK_SHALLOW, BORDER))
	t.set_stylebox("pressed", "Button", _button_box(PINK_DEEP, INK))
	t.set_stylebox("disabled", "Button", _button_box(PAPER_DIM, INK_SOFT))
	t.set_stylebox("focus", "Button", _focus_ring())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", INK_SOFT)
	t.set_font_size("font_size", "Button", 17)

	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_hover_color", "CheckButton", INK)
	t.set_color("font_focus_color", "CheckButton", INK)
	t.set_stylebox("focus", "CheckButton", _focus_ring())

	# Sliders — cream track, pink filled span.
	var track := StyleBoxFlat.new()
	track.bg_color = PAPER_DIM.darkened(0.12)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4.0
	track.content_margin_bottom = 4.0
	t.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = PINK_DEEP
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 4.0
	fill.content_margin_bottom = 4.0
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var slider_focus := _focus_ring()
	slider_focus.set_expand_margin_all(4.0)
	t.set_stylebox("focus", "HSlider", slider_focus)

	return t


static func _panel_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PAPER
	s.border_color = BORDER
	s.set_border_width_all(3)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(26)
	s.shadow_color = Color(0.1, 0.05, 0.08, 0.35)
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 4)
	return s


static func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	s.content_margin_left = 18.0
	s.content_margin_right = 18.0
	s.content_margin_top = 9.0
	s.content_margin_bottom = 9.0
	return s


static func _focus_ring() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = PINK_DEEP
	s.set_border_width_all(3)
	s.set_corner_radius_all(10)
	s.set_expand_margin_all(2.0)
	return s
