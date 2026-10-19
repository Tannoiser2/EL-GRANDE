extends Control
## Carta azione disegnata in italiano: illustrazione originale, titolo, testo e Caballeros da piazzare.

const D = preload("res://scripts/data/eg_data.gd")

var ci := 0
var big := false
var dim := false
var owner_color := -1          # colore di chi l'ha presa (-1 = libera)
var glow := false
var t := 0.0


func setup(card_index: int, sz: Vector2, is_big := false) -> void:
	ci = card_index
	big = is_big
	custom_minimum_size = sz
	size = sz
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _process(delta: float) -> void:
	if glow:
		t += delta
		queue_redraw()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var cd: Dictionary = D.CARDS[ci]
	var pad := 10.0 if big else 5.0
	var art := UI.icon_rect(UI.action_art(ci), Vector2(size.x - 2 * pad, (size.x - 2 * pad) * 172.0 / 352.0))
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = Vector2(pad, pad)
	add_child(art)
	var y := art.position.y + art.size.y + (6 if big else 2)
	var ttl := UI.label(cd["title"], 26 if big else 13, Color("#5a1a10"), UI.font_sc_b)
	ttl.position = Vector2(pad, y)
	ttl.custom_minimum_size = Vector2(size.x - 2 * pad, 0)
	ttl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not big:
		ttl.add_theme_constant_override("line_spacing", -4)
	ttl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ttl)
	var txt := UI.label(cd["text"], 21 if big else 12, UI.INK, UI.font_body)
	var two_lines: bool = not big and UI.font_sc_b.get_string_size(cd["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > size.x - 2 * pad
	txt.position = Vector2(pad + 2, y + (36 if big else (34 if two_lines else 18)))
	txt.custom_minimum_size = Vector2(size.x - 2 * pad - 4, 0)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not big:
		txt.add_theme_constant_override("line_spacing", -3)
	add_child(txt)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sb := UI.paper_style(8 if big else 5)
	sb.bg_color = Color("#f2e0b4")
	draw_style_box(sb, r)
	# Caballeros da piazzare (in basso)
	var cd: Dictionary = D.CARDS[ci]
	var k: int = cd["pile"]
	var cs := 22.0 if big else 12.0
	var x0 := size.x / 2.0 - (k * (cs + 5)) / 2.0 + cs / 2.0
	for i in k:
		UI.draw_cube(self, Vector2(x0 + i * (cs + 5), size.y - cs * 0.9 - 4), cs, Color("#3a2a1a"), Color(0.95, 0.85, 0.6, 0.9))
	if owner_color >= 0:
		draw_rect(r, Color(0, 0, 0, 0.45))
		UI.draw_cube(self, Vector2(size.x / 2.0, size.x * 0.27), 34 if not big else 60, UI.pcol(owner_color), Color(1, 0.95, 0.8))
	elif dim:
		draw_rect(r, Color(0, 0, 0, 0.35))
	if glow:
		var a := 0.55 + 0.45 * sin(t * 4.0)
		draw_rect(r.grow(2), Color(1, 0.85, 0.3, a), false, 4.0)
