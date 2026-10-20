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
	for ch in get_children():
		ch.queue_free()
	tooltip_text = "" if big else "%s: %s" % [D.CARDS[ci]["title"], D.CARDS[ci]["text"]]
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# carta italiana scansionata (illustrazione, titolo, testo e spiegazione)
	draw_rect(r.grow(1), Color(0, 0, 0, 0.5))
	draw_texture_rect(UI.tex(D.card_tex_path(ci)), r, false)
	if owner_color >= 0:
		draw_rect(r, Color(0, 0, 0, 0.45))
		UI.draw_cube(self, Vector2(size.x / 2.0, size.x * 0.27), 34 if not big else 60, UI.pcol(owner_color), Color(1, 0.95, 0.8))
	elif dim:
		draw_rect(r, Color(0, 0, 0, 0.35))
	if glow:
		var a := 0.55 + 0.45 * sin(t * 4.0)
		draw_rect(r.grow(2), Color(1, 0.85, 0.3, a), false, 4.0)
