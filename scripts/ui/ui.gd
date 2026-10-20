class_name UI
extends RefCounted
## Helper grafici condivisi: palette castigliana (pergamena, oro, rosso), caratteri gotici e rinascimentali.

const GOLD := Color("#d9b45a")
const GOLD_D := Color("#8a6a2a")
const DARK := Color("#1a0f08")
const LEATHER := Color("#2a1a10")
const PANEL := Color("#21150d")
const PAPER := Color("#f1e3c2")
const INK := Color("#3a2414")
const RED := Color("#a3251a")
const RED_L := Color("#e0563f")
const GREEN := Color("#79c46a")
const TEXT := Color("#efe4cc")
const MUTED := Color("#b9a988")

static var _tex := {}
static var font_title: Font      # gotico (titoli)
static var font_sc: Font         # maiuscoletto (intestazioni, pulsanti)
static var font_sc_b: Font
static var font_body: Font
static var font_bold: Font
static var font_italic: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	font_title = load("res://assets/fonts/UnifrakturMaguntia-Book.ttf")
	font_sc = _var(load("res://assets/fonts/AlegreyaSC-Regular.ttf"), 0)
	font_sc_b = _var(load("res://assets/fonts/AlegreyaSC-Bold.ttf"), 0)
	var body: FontFile = load("res://assets/fonts/Alegreya.ttf")
	font_body = _var(body, 500)
	font_bold = _var(body, 760)
	font_italic = _var(load("res://assets/fonts/Alegreya-Italic.ttf"), 500)


## Variante del carattere con le cifre "allineate" (Alegreya di serie usa cifre in stile antico,
## dove lo 0 sembra una o) e, se serve, il peso.
static func _var(f: Font, weight: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = f
	if weight > 0:
		fv.variation_opentype = {"wght": weight}
	var ts := TextServerManager.get_primary_interface()
	fv.opentype_features = {ts.name_to_tag("lnum"): 1}
	return fv


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


static func power_tex(color_id: int, v: int) -> Texture2D:
	return tex("res://assets/power/%s_%d.jpg" % [EGData.COLORS[color_id]["key"], v])


static func pcol(color_id: int) -> Color:
	return EGData.COLORS[color_id]["col"]


static func plight(color_id: int) -> Color:
	return EGData.COLORS[color_id]["light"]


static func panel_style(bg: Color, border: Color, bw := 1, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	return sb


static func paper_style(radius := 6) -> StyleBoxFlat:
	var sb := panel_style(PAPER, GOLD_D, 2, radius)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	return sb


static func label(text: String, size := 20, col := TEXT, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 40, col := GOLD) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	return l


static func heading(text: String, size := 26, col := GOLD) -> Label:
	init_fonts()
	return label(text, size, col, font_sc_b)


static func wrap(l: Label, w: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l


static func icon_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, w := 200.0, h := 54.0, size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size)
	return b


static func primary(b: Button) -> Button:
	var n := panel_style(RED, GOLD, 2, 6)
	n.shadow_color = Color(0, 0, 0, 0.4)
	n.shadow_size = 4
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", panel_style(Color("#c3382a"), Color("#ffe39a"), 2, 6))
	b.add_theme_stylebox_override("pressed", panel_style(GOLD, GOLD, 2, 6))
	b.add_theme_color_override("font_color", Color("#fff3d6"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	return b


## Disegna un cubo in assonometria (Caballero o Grande) centrato in c.
static func draw_cube(ci: CanvasItem, c: Vector2, sz: float, col: Color, outline := Color(0, 0, 0, 0.75)) -> void:
	var h := sz * 0.5
	var d := sz * 0.28
	# facce: davanti, sopra, lato
	var f0 := c + Vector2(-h, -h + d)
	var front := PackedVector2Array([f0, f0 + Vector2(sz - d, 0), f0 + Vector2(sz - d, sz - d), f0 + Vector2(0, sz - d)])
	var top2 := PackedVector2Array([f0, f0 + Vector2(d, -d), f0 + Vector2(sz, -d), f0 + Vector2(sz - d, 0)])
	var side := PackedVector2Array([f0 + Vector2(sz - d, 0), f0 + Vector2(sz, -d), f0 + Vector2(sz, sz - 2 * d), f0 + Vector2(sz - d, sz - d)])
	ci.draw_colored_polygon(front, col)
	ci.draw_colored_polygon(top2, col.lightened(0.35))
	ci.draw_colored_polygon(side, col.darkened(0.35))
	var w := maxf(1.0, sz / 18.0)
	ci.draw_polyline(PackedVector2Array([front[0], front[1], front[2], front[3], front[0]]), outline, w, true)
	ci.draw_polyline(PackedVector2Array([top2[0], top2[1], top2[2], top2[3]]), outline, w, true)
	ci.draw_polyline(PackedVector2Array([side[1], side[2], side[3]]), outline, w, true)


static func make_theme() -> Theme:
	init_fonts()
	var th := Theme.new()
	th.default_font = font_body
	th.default_font_size = 21
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#3a2414")
	sb.border_color = GOLD_D
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	th.set_stylebox("normal", "Button", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color("#5a3820")
	sbh.border_color = GOLD
	th.set_stylebox("hover", "Button", sbh)
	var sbp := sb.duplicate()
	sbp.bg_color = GOLD
	th.set_stylebox("pressed", "Button", sbp)
	var sbd := sb.duplicate()
	sbd.bg_color = Color("#22160e")
	sbd.border_color = Color("#4a3a2a")
	th.set_stylebox("disabled", "Button", sbd)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color("#f6e8c8"))
	th.set_color("font_hover_color", "Button", Color("#ffe39a"))
	th.set_color("font_pressed_color", "Button", DARK)
	th.set_color("font_disabled_color", "Button", Color("#7a6a55"))
	th.set_font("font", "Button", font_sc_b)
	th.set_font_size("font_size", "Button", 22)
	th.set_color("font_color", "Label", TEXT)
	var pn := StyleBoxFlat.new()
	pn.bg_color = PANEL
	pn.border_color = Color("#000000")
	pn.set_border_width_all(1)
	th.set_stylebox("panel", "Panel", pn)
	th.set_stylebox("panel", "PanelContainer", pn)
	th.set_font("normal_font", "RichTextLabel", font_body)
	th.set_font("bold_font", "RichTextLabel", font_bold)
	th.set_font("italics_font", "RichTextLabel", font_italic)
	th.set_font_size("normal_font_size", "RichTextLabel", 21)
	th.set_font_size("bold_font_size", "RichTextLabel", 21)
	th.set_font_size("italics_font_size", "RichTextLabel", 21)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_font("font", "LineEdit", font_bold)
	th.set_font_size("font_size", "LineEdit", 24)
	th.set_stylebox("normal", "LineEdit", panel_style(Color("#140c06"), GOLD_D, 1, 4))
	th.set_stylebox("focus", "LineEdit", panel_style(Color("#140c06"), GOLD, 2, 4))
	th.set_font("font", "TooltipLabel", font_body)
	th.set_font_size("font_size", "TooltipLabel", 19)
	var tp := StyleBoxFlat.new()
	tp.bg_color = Color("#1a0f08ee")
	tp.border_color = GOLD
	tp.set_border_width_all(1)
	tp.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", tp)
	th.set_font("font", "CheckBox", font_sc_b)
	th.set_font_size("font_size", "CheckBox", 22)
	return th
