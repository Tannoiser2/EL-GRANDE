extends Control
## Plancia del giocatore, come quella del tavolo: a sinistra le province (sulla carta della regione del
## suo Grande) con i Caballeros, a destra la corte, al centro la carta potere giocata. In alto il nome
## con i punti vittoria. Le misure si adattano allo spazio (più giocatori, plance più basse).

const D = preload("res://scripts/data/eg_data.gd")
const HEAD := 32.0
const COLS := 6

var eng: EGEngine
var seat := 0
var view
var bg: Texture2D
var t := 0.0
var S := 150.0                  # lato dei riquadri quadrati
var prov_r := Rect2()
var court_r := Rect2()
var card_r := Rect2()


func setup(w: float, h: float) -> void:
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	S = h - HEAD - 8
	var cw := S * 0.67
	var gap := (w - 2 * S - cw) / 4.0
	prov_r = Rect2(gap, HEAD + 2, S, S)
	card_r = Rect2(gap * 2 + S, HEAD + 2, cw, S)
	court_r = Rect2(gap * 3 + S + cw, HEAD + 2, S, S)


func _ready() -> void:
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
	return global_position + _slot(prov_r, i if i >= 0 else maxi(0, eng.prov[seat] - 1))


func court_point(i := -1) -> Vector2:
	return global_position + _slot(court_r, i if i >= 0 else maxi(0, eng.court[seat] - 1))


func _step() -> float:
	return (S - 14) / float(COLS)


func _slot(fr: Rect2, i: int) -> Vector2:
	var st := _step()
	i = clampi(i, 0, COLS * 6 - 1)
	return fr.position + Vector2(7 + st * (i % COLS) + st / 2.0, 9 + st * (i / COLS) + st / 2.0)


func _draw() -> void:
	if eng == null:
		return
	var p: Dictionary = eng.players[seat]
	var col := UI.pcol(p["color"])
	var light := UI.plight(p["color"])
	var full := Rect2(Vector2.ZERO, size)
	# sfondo seppia (striscia centrale del paesaggio)
	var src_h := minf(380.0, 1208.0 * size.y / size.x)
	draw_texture_rect_region(bg, full, Rect2(0, (380.0 - src_h) / 2.0, 1208, src_h))
	draw_rect(full, Color(0.12, 0.07, 0.03, 0.10))
	# intestazione: nome e punti vittoria
	draw_rect(Rect2(0, 0, size.x, HEAD), Color(0.1, 0.06, 0.03, 0.82))
	var f := UI.font_sc_b
	var nm: String = p["name"] + (" · IA" if p["ai"] else "")
	var x := 12.0
	_text(nm, 22, Vector2(x, 24), light)
	x += f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 18
	var pv := str(eng.score[seat])
	_text(pv, 30, Vector2(x, 27), UI.GOLD)
	x += f.get_string_size(pv, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x + 5
	_text("PV", 17, Vector2(x, 26), UI.GOLD.darkened(0.15))
	var rx := size.x - 10
	if eng.veto_active(seat):
		rx = _tag_right(rx, "VETO", UI.RED, Color.WHITE)
	if eng.start_seat == seat and eng.phase == "power":
		rx = _tag_right(rx, "inizia il round", Color(0.25, 0.16, 0.08), UI.GOLD)
	# nastri dalle province alla carta e dalla carta alla corte
	var rib := Color(col.r, col.g, col.b, 0.3)
	var mid := prov_r.position.y + S * 0.5
	_ribbon(Vector2(prov_r.end.x - 8, mid), Vector2(card_r.position.x + 4, mid), rib)
	_ribbon(Vector2(card_r.end.x - 4, mid), Vector2(court_r.position.x + 8, mid), rib)
	# riquadri quadrati
	for fr in [prov_r, court_r]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 0.97, 0.9, 0.35)
		sb.border_color = col
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(10)
		sb.shadow_color = Color(col.r, col.g, col.b, 0.35)
		sb.shadow_size = 4
		draw_style_box(sb, fr)
	# carta della regione del Grande, sotto i Caballeros delle province
	var g: int = eng.grande[seat]
	if g >= 0:
		draw_texture_rect(UI.tex("res://assets/regions/r%d.jpg" % g), prov_r.grow(-6), false, Color(1, 1, 1, 0.92))
	# Caballeros
	var cs := _step() * 0.78
	var outline := Color(0.08, 0.04, 0.0, 0.85)
	for i in eng.prov[seat]:
		UI.draw_cube(self, _slot(prov_r, i), cs, col, outline)
	for i in eng.court[seat]:
		UI.draw_cube(self, _slot(court_r, i), cs, col, outline)
	# numeri nell'angolo dei riquadri
	_corner(prov_r, "Province", eng.prov[seat], light)
	_corner(court_r, "Corte", eng.court[seat], light)
	# carta potere giocata (o il dorso), grande quanto i riquadri
	var v: int = eng.played[seat]
	var ct: Texture2D = UI.power_tex(p["color"], v) if v > 0 else UI.tex("res://assets/backs/power.jpg")
	draw_rect(card_r.grow(2), Color(0, 0, 0, 0.5))
	draw_texture_rect(ct, card_r, false, Color.WHITE if v > 0 else Color(0.75, 0.7, 0.62))
	# bordo: più marcato per chi è di turno
	var bw := 2.0
	var bc := Color(col.r, col.g, col.b, 0.7)
	if _active():
		bw = 4.0
		bc = light.lerp(Color.WHITE, 0.25 + 0.25 * sin(t * 4.0))
	draw_rect(full.grow(-1), bc, false, bw)


func _text(s: String, fs: int, pos: Vector2, col: Color) -> void:
	draw_string_outline(UI.font_sc_b, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.05, 0.02, 0.0, 0.9))
	draw_string(UI.font_sc_b, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _tag_right(rx: float, s: String, bgc: Color, fg: Color) -> float:
	var w := UI.font_sc_b.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 14
	var r := Rect2(Vector2(rx - w, 5), Vector2(w, 22))
	draw_rect(r, bgc)
	draw_rect(r, UI.GOLD, false, 1.0)
	draw_string(UI.font_sc_b, Vector2(r.position.x, r.position.y + 17), s, HORIZONTAL_ALIGNMENT_CENTER, w, 16, fg)
	return rx - w - 8


## Numero nell'angolo in basso a destra del riquadro, con il nome della zona.
func _corner(fr: Rect2, label: String, q: int, col: Color) -> void:
	var f := UI.font_sc_b
	var num := str(q)
	var wn := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var wl := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var r := Rect2(fr.end - Vector2(wn + wl + 22, 30), Vector2(wn + wl + 16, 25))
	draw_rect(r, Color(0.1, 0.06, 0.03, 0.85))
	draw_rect(r, col, false, 1.0)
	draw_string(f, Vector2(r.position.x + 6, r.position.y + 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#e8d8b8"))
	draw_string(f, Vector2(r.position.x + 10 + wl, r.position.y + 21), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)


## Nastro con punta di freccia (come sulle plance del gioco).
func _ribbon(a: Vector2, b: Vector2, col: Color) -> void:
	draw_line(a, b - Vector2(10, 0), col, 14.0, true)
	draw_colored_polygon(PackedVector2Array([b + Vector2(4, 0), b - Vector2(14, 14), b - Vector2(14, -14)]), col)
