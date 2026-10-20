extends Control
## Plancia del giocatore, come quella del tavolo: a sinistra le province (sulla carta della regione del
## suo Grande) con i Caballeros, a destra la corte, al centro la carta potere giocata con i punti sopra.

const D = preload("res://scripts/data/eg_data.gd")
const W := 740.0
const H := 186.0
const PROV := Rect2(16, 32, 250, 148)
const COURT := Rect2(474, 32, 250, 148)
const CARD := Rect2(339, 88, 62, 93)
const CUBE := 19.0
const STEP := Vector2(27, 29)
const COLS := 8

var eng: EGEngine
var seat := 0
var view
var bg: Texture2D
var t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	bg = UI.tex("res://assets/plancia_bg.jpg")
	mouse_filter = Control.MOUSE_FILTER_PASS


func _process(delta: float) -> void:
	if _active():
		t += delta
		queue_redraw()


func _active() -> bool:
	return eng != null and (eng.current == seat or eng.acting == seat) and not eng.game_over


func update_info() -> void:
	var p: Dictionary = eng.players[seat]
	var lines := ["%s%s" % [p["name"], " (IA)" if p["ai"] else ""]]
	lines.append("Grande in %s" % D.region_name(eng.grande[seat]))
	lines.append("Province %d · corte %d · sul tabellone %d" % [eng.prov[seat], eng.court[seat], eng.on_board(seat)])
	lines.append("Carte potere in mano: " + ", ".join(eng.hand[seat].map(func(v): return str(v))))
	if eng.veto_active(seat):
		lines.append("Ha il Veto!")
	tooltip_text = "\n".join(lines)
	queue_redraw()


## Centro (coordinate globali) della casella i delle province o della corte.
func prov_point(i := -1) -> Vector2:
	return global_position + _slot(PROV, i if i >= 0 else maxi(0, eng.prov[seat] - 1))


func court_point(i := -1) -> Vector2:
	return global_position + _slot(COURT, i if i >= 0 else maxi(0, eng.court[seat] - 1))


func _slot(fr: Rect2, i: int) -> Vector2:
	var rows := 4
	var cap := COLS * rows
	i = clampi(i, 0, cap - 1)
	var x0 := fr.position.x + (fr.size.x - (COLS - 1) * STEP.x) / 2.0
	# nelle province i cubetti lasciano leggere il nome della regione sulla carta
	var y0 := fr.position.y + (48 if fr == PROV else 26)
	return Vector2(x0 + (i % COLS) * STEP.x, y0 + (i / COLS) * STEP.y)


func _draw() -> void:
	if eng == null:
		return
	var p: Dictionary = eng.players[seat]
	var col := UI.pcol(p["color"])
	var light := UI.plight(p["color"])
	var full := Rect2(Vector2.ZERO, size)
	# sfondo seppia (la striscia centrale del paesaggio)
	var src_h := 1208.0 * H / W
	draw_texture_rect_region(bg, full, Rect2(0, (380.0 - src_h) / 2.0, 1208, src_h))
	draw_rect(full, Color(0.12, 0.07, 0.03, 0.12))
	var active := _active()
	# nastri dalle province alla carta e dalla carta alla corte
	var rib := Color(col.r, col.g, col.b, 0.28)
	_ribbon(Vector2(PROV.end.x - 30, PROV.position.y + 70), Vector2(CARD.position.x + 6, CARD.position.y + 40), rib)
	_ribbon(Vector2(CARD.end.x - 6, CARD.position.y + 40), Vector2(COURT.position.x + 30, COURT.position.y + 70), rib)
	# riquadri
	for fr in [PROV, COURT]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 0.97, 0.9, 0.38)
		sb.border_color = col
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		sb.shadow_color = Color(col.r, col.g, col.b, 0.35)
		sb.shadow_size = 5
		sb.shadow_offset = Vector2(0, 0)
		draw_style_box(sb, fr)
	# carta della regione del Grande, sotto i Caballeros delle province
	var g: int = eng.grande[seat]
	if g >= 0:
		var rt := UI.tex("res://assets/regions/r%d.jpg" % g)
		var cs := PROV.size.y - 14
		draw_texture_rect(rt, Rect2(PROV.position + Vector2((PROV.size.x - cs) / 2.0, 7), Vector2(cs, cs)), false, Color(1, 1, 1, 0.95))
	# Caballeros
	var outline := Color(0.08, 0.04, 0.0, 0.85)
	for i in eng.prov[seat]:
		UI.draw_cube(self, _slot(PROV, i), CUBE, col, outline)
	for i in eng.court[seat]:
		UI.draw_cube(self, _slot(COURT, i), CUBE, col, outline)
	# etichette dei riquadri
	_tag(Vector2(PROV.position.x + 10, 4), "Province  %d" % eng.prov[seat], light)
	_tag(Vector2(COURT.position.x + 10, 4), "Corte  %d" % eng.court[seat], light)
	# centro: nome, punti, carta potere
	var f := UI.font_sc_b
	var nm: String = p["name"] + (" · IA" if p["ai"] else "")
	_center_text(nm, 20, Vector2(370, 22), light, 160)
	var pv := str(eng.score[seat])
	_center_text(pv, 46, Vector2(358, 74), UI.GOLD, 120, 7)
	draw_string(f, Vector2(358 + f.get_string_size(pv, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x / 2.0 + 4, 74), "PV", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.GOLD.darkened(0.15))
	var v: int = eng.played[seat]
	var ct: Texture2D = UI.power_tex(p["color"], v) if v > 0 else UI.tex("res://assets/backs/power.jpg")
	draw_rect(CARD.grow(3), Color(0, 0, 0, 0.45))
	draw_texture_rect(ct, CARD, false, Color.WHITE if v > 0 else Color(0.75, 0.7, 0.62))
	if v > 0:
		_center_text("%d cab." % D.POWER_CAB[v], 14, Vector2(CARD.get_center().x, CARD.end.y + 1), Color("#fff2d0"), 80, 4)
	if eng.veto_active(seat):
		var vr := Rect2(Vector2(CARD.end.x + 6, CARD.position.y + 20), Vector2(56, 24))
		draw_rect(vr, UI.RED)
		draw_rect(vr, UI.GOLD, false, 1.5)
		draw_string(f, Vector2(vr.position.x, vr.position.y + 18), "VETO", HORIZONTAL_ALIGNMENT_CENTER, vr.size.x, 16, Color.WHITE)
	if eng.start_seat == seat and eng.phase == "power":
		var ir := Rect2(Vector2(CARD.position.x - 62, CARD.position.y + 20), Vector2(56, 24))
		draw_rect(ir, Color(0.1, 0.06, 0.03, 0.85))
		draw_rect(ir, UI.GOLD, false, 1.0)
		draw_string(f, Vector2(ir.position.x, ir.position.y + 18), "inizia", HORIZONTAL_ALIGNMENT_CENTER, ir.size.x, 16, UI.GOLD)
	# bordo: più marcato per chi è di turno
	var bw := 2.0
	var bc := Color(col.r, col.g, col.b, 0.7)
	if active:
		bw = 4.0
		bc = light.lerp(Color.WHITE, 0.25 + 0.25 * sin(t * 4.0))
	draw_rect(full.grow(-1), bc, false, bw)


func _tag(pos: Vector2, text: String, col: Color) -> void:
	var f := UI.font_sc_b
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var r := Rect2(pos, Vector2(w + 16, 25))
	draw_rect(r, Color(0.1, 0.06, 0.03, 0.82))
	draw_rect(r, col, false, 1.0)
	draw_string(f, pos + Vector2(8, 19), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("#f6e8c8"))


func _center_text(text: String, fs: int, base: Vector2, col: Color, w: float, outline := 5) -> void:
	var f := UI.font_sc_b
	var p := Vector2(base.x - w / 2.0, base.y)
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, outline, Color(0.08, 0.04, 0.0, 0.9))
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)


## Nastro curvo con punta di freccia (come sulle plance del gioco).
func _ribbon(a: Vector2, b: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	var c1 := a + Vector2((b.x - a.x) * 0.5, -10)
	var c2 := b + Vector2(-(b.x - a.x) * 0.5, 10)
	for i in 21:
		var u := i / 20.0
		var p := a.bezier_interpolate(c1, c2, b, u)
		pts.append(p)
	draw_polyline(pts, col, 16.0, true)
	var dir := (b - pts[18]).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([b + dir * 12, b - dir * 6 + nrm * 16, b - dir * 6 - nrm * 16]), col)
