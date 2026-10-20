extends Control
## Tabellone: mappa della Spagna con Caballeros, Grandi, Re, Castillo, segna-punti mobili,
## scala del successo e segna-turno. Tutto disegnato sopra l'immagine del tabellone.

signal region_clicked(r: int, button: int)
signal region_hovered(r: int)

const D = preload("res://scripts/data/eg_data.gd")
const CAS := 9

var eng: EGEngine
var view                        # game_view: anteprime e regioni evidenziate
var sc := 1.0
var hover := -1
var t := 0.0
var board_tex: Texture2D
var crown: Texture2D
var flash := {}                  # regione -> istante della valutazione (per il bagliore)


func _ready() -> void:
	board_tex = UI.tex("res://assets/board.jpg")
	crown = UI.tex("res://assets/crown.png")
	mouse_filter = Control.MOUSE_FILTER_STOP
	sc = size.x / D.BOARD_SIZE.x
	clip_contents = true


func _process(delta: float) -> void:
	t += delta
	if view != null and (not view.allowed_regions().is_empty() or not flash.is_empty()):
		queue_redraw()


func bp(p: Vector2) -> Vector2:
	return p * sc


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var r := D.region_at(ev.position / sc)
		if r >= 0 and not _region_hit(r, ev.position / sc):
			r = -1
		if r != hover:
			hover = r
			region_hovered.emit(r)
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed:
		var r := D.region_at(ev.position / sc)
		if r >= 0 and _region_hit(r, ev.position / sc):
			region_clicked.emit(r, ev.button_index)
			accept_event()


## Il punto cade davvero sulla terra della regione? (le aree di mare lontane non contano)
func _region_hit(r: int, p: Vector2) -> bool:
	if r == CAS or r == D.SHIP_G:
		return eng != null and (r == CAS or eng.grandissimo)
	if eng != null and not (r in eng.map_regions()):
		return false
	for a in D.ANCHORS[r]:
		if p.distance_to(a) < 110:
			return true
	return D.REGIONS[r]["rect"].grow(10).has_point(p)


func _draw() -> void:
	if eng == null:
		return
	draw_texture_rect(board_tex, Rect2(Vector2.ZERO, size), false)
	var allowed: Array = view.allowed_regions() if view != null else []
	var counts: Array = view.display_counts() if view != null else eng.cab
	# regione del Re: velo dorato
	_draw_region_frame(eng.king, Color(1, 0.84, 0.3, 0.0), Color(0.95, 0.75, 0.2, 0.9), 3.0)
	# regioni selezionabili
	var pulse := 0.5 + 0.5 * sin(t * 4.0)
	for r in allowed:
		_draw_region_frame(r, Color(1, 0.9, 0.5, 0.10 + 0.10 * pulse), Color(1, 0.92, 0.55, 0.6 + 0.4 * pulse), 4.0)
	if hover >= 0:
		_draw_region_frame(hover, Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.8) if hover in allowed else Color(1, 1, 1, 0.35), 2.0)
	# bagliore delle valutazioni recenti
	for r in flash.keys():
		var age: float = t - flash[r]
		if age > 2.2:
			flash.erase(r)
			continue
		var a := 1.0 - age / 2.2
		_draw_region_frame(r, Color(1, 0.8, 0.2, 0.25 * a), Color(1, 0.85, 0.3, a), 6.0)
	# segna-punti mobili
	for m in 2:
		if eng.mobile[m] >= 0:
			_draw_mobile(m, D.REGIONS[eng.mobile[m]]["box"])
	# Grandissimo: Portogallo, nave, prigione, Caballeros neri dell'Inquisitore
	if eng.grandissimo:
		_draw_grandissimo(counts)
	# Intrigo & il Re: ponte, «Prendi 6!», quarantena, protezione
	if eng.intrigo:
		_draw_intrigo()
	# Castillo
	_draw_castillo(counts[CAS])
	# Caballeros nelle regioni
	for r in eng.map_regions():
		_draw_cabs(r, counts[r])
	# Grandi
	var by_reg := {}
	for s in eng.n:
		var g: int = eng.grande[s]
		if g >= 0 and g != CAS:
			if not by_reg.has(g):
				by_reg[g] = []
			by_reg[g].append(s)
	for g in by_reg:
		var lst: Array = by_reg[g]
		var rr: Rect2 = D.REGIONS[g]["rect"]
		for i in lst.size():
			var c := bp(Vector2(rr.position.x + 10 + i * 38, rr.position.y + 18))
			UI.draw_cube(self, c + Vector2(16, 0), 34 * sc, UI.pcol(eng.players[lst[i]]["color"]), Color(0.1, 0.06, 0, 0.95))
			draw_arc(c + Vector2(16, 0), 22 * sc, 0, TAU, 24, Color(1, 0.85, 0.35, 0.9), 2.0, true)
	# Re (con la Rivoluzione è il Grande scelto: la pedina del Re resta nel Castillo)
	var kr: Rect2 = D.REGIONS[eng.king]["rect"]
	var kc := bp(kr.position + Vector2(kr.size.x - 8, -6))
	if eng.revolution >= 0:
		_draw_king(bp(D.CASTILLO_POS + Vector2(52, -40)))
		draw_texture_rect(crown, Rect2(kc + Vector2(-22, -10) * sc, Vector2(44, 30) * sc), false)
	else:
		_draw_king(kc)
	# Grandi nel Castillo (Cospirazione)
	var gi := 0
	for s in eng.n:
		if eng.grande[s] == CAS:
			var gc := bp(D.CASTILLO_POS + Vector2(-60 + gi * 34, 62))
			UI.draw_cube(self, gc, 30 * sc, UI.pcol(eng.players[s]["color"]), Color(0.1, 0.06, 0, 0.95))
			draw_arc(gc, 20 * sc, 0, TAU, 24, Color(1, 0.85, 0.35, 0.9), 2.0, true)
			gi += 1
	# segna-turno
	if eng.cur_round > 0:
		UI.draw_cube(self, bp(Vector2(D.ROUND_X - 4, D.ROUND_Y[eng.cur_round])), 20 * sc, Color("#1a1a1a"), Color(1, 0.9, 0.6, 0.9))
	# scala del successo
	_draw_scores()


func _draw_region_frame(r: int, fill: Color, border: Color, w: float) -> void:
	var rr: Rect2 = D.REGIONS[r]["rect"]
	var rect := Rect2(bp(rr.position), rr.size * sc).grow(4)
	if fill.a > 0:
		draw_rect(rect, fill, true)
	draw_rect(rect, border, false, w)


func _draw_cabs(r: int, counts: Array) -> void:
	var rr: Rect2 = D.REGIONS[r]["rect"]
	var present := []
	for s in eng.n:
		if counts[s] > 0:
			present.append(s)
	if present.is_empty():
		return
	var cols := 3 if present.size() > 2 else present.size()
	var cell := Vector2(rr.size.x / 3.0, 50)
	var y0 := rr.position.y + minf(52.0, rr.size.y * 0.45)
	for i in present.size():
		var s: int = present[i]
		var row := i / 3
		var col := i % 3
		var in_row := mini(3, present.size() - row * 3)
		var x0 := rr.position.x + (rr.size.x - in_row * cell.x) / 2.0
		var c := bp(Vector2(x0 + col * cell.x + cell.x / 2.0, y0 + row * cell.y + 18))
		_badge(c, s, counts[s])


func _badge(c: Vector2, s: int, q: int, hidden := false) -> void:
	var colr := UI.pcol(eng.players[s]["color"])
	# piccola pila: fino a 3 cubi sovrapposti
	var k := mini(3, q)
	for j in k:
		UI.draw_cube(self, c + Vector2(-10 * sc + j * 3 * sc, -j * 6 * sc), 26 * sc, colr)
	var txt := "?" if hidden else str(q)
	var f := UI.font_sc_b
	var fs := int(24 * sc)
	var p := c + Vector2(10 * sc, 16 * sc)
	draw_string_outline(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.9))
	draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_intrigo() -> void:
	if not eng.bridge.is_empty():
		var a := bp(D.REGIONS[eng.bridge["a"]]["rect"].get_center())
		var b := bp(D.REGIONS[eng.bridge["b"]]["rect"].get_center())
		var col := UI.pcol(eng.players[eng.bridge["owner"]]["color"])
		draw_line(a, b, Color(0.25, 0.15, 0.05, 0.85), 14 * sc, true)
		draw_line(a, b, Color("#c8a46a"), 9 * sc, true)
		for i in 7:
			var p := a.lerp(b, (i + 0.5) / 7.0)
			var d := (b - a).normalized().orthogonal() * 6 * sc
			draw_line(p - d, p + d, Color(0.3, 0.18, 0.06), 2.0)
		var mid := a.lerp(b, 0.5)
		if eng.bridge.get("guard", false):
			UI.draw_cube(self, mid, 22 * sc, col, Color(1, 0.95, 0.8))
	for r in eng.limit6:
		var rr: Rect2 = D.REGIONS[r]["rect"]
		var c := bp(rr.position + Vector2(rr.size.x - 22, rr.size.y - 20))
		var box := Rect2(c - Vector2(20, 26) * sc, Vector2(40, 52) * sc)
		draw_rect(box, Color("#f4ead2"))
		draw_rect(box, UI.pcol(eng.players[eng.limit6[r]]["color"]), false, 3.0)
		draw_string(UI.font_sc_b, Vector2(box.position.x, box.position.y + box.size.y * 0.72), "6", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, int(32 * sc), Color("#5a1a10"))
	if not eng.quarantine.is_empty():
		var rr: Rect2 = D.REGIONS[eng.quarantine[0]]["rect"]
		var r2 := Rect2(bp(rr.position), rr.size * sc).grow(-6)
		draw_line(r2.position, r2.end, Color(0.6, 0.05, 0.05, 0.8), 6.0, true)
		draw_line(Vector2(r2.end.x, r2.position.y), Vector2(r2.position.x, r2.end.y), Color(0.6, 0.05, 0.05, 0.8), 6.0, true)
		draw_string(UI.font_sc_b, bp(rr.position + Vector2(6, 22)), "Quarantena", HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * sc), Color("#7a1010"))
	for r in eng.protected:
		var rr: Rect2 = D.REGIONS[r]["rect"]
		_draw_region_frame(r, Color(0.9, 0.8, 0.4, 0.12), Color(0.95, 0.8, 0.3, 0.9), 3.0)
		draw_string(UI.font_sc_b, bp(rr.position + Vector2(6, 22)), "Protetta", HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * sc), Color("#6a4a10"))


func _draw_grandissimo(counts: Array) -> void:
	# segnapunti del Portogallo (5 / – / –)
	var pb: Texture2D = UI.tex("res://assets/grandissimo/portugal_board.jpg")
	if not (D.PORTUGAL in eng.mobile):
		var c := bp(D.REGIONS[D.PORTUGAL]["box"])
		draw_texture_rect(pb, Rect2(c - Vector2(52, 20) * sc, Vector2(104, 40) * sc), false)
	# nave
	var sp := bp(D.SHIP_G_POS)
	var st: Texture2D = UI.tex("res://assets/grandissimo/ship_token.jpg")
	draw_circle(sp, 48 * sc, Color(0.1, 0.2, 0.35, 0.55))
	draw_texture_rect(st, Rect2(sp - Vector2(42, 35) * sc, Vector2(84, 70) * sc), false)
	draw_arc(sp, 48 * sc, 0, TAU, 32, Color(0.85, 0.75, 0.5, 0.9), 2.0, true)
	var present := []
	for s in eng.n:
		if counts[D.SHIP_G][s] > 0:
			present.append(s)
	for i in present.size():
		_badge(sp + Vector2(-40 + i * 34, 52) * sc, present[i], counts[D.SHIP_G][present[i]])
	# prigione
	var jp := bp(D.JAIL_POS)
	draw_texture_rect(UI.tex("res://assets/grandissimo/jail.jpg"), Rect2(jp - Vector2(44, 45) * sc, Vector2(88, 90) * sc), false)
	draw_rect(Rect2(jp - Vector2(44, 45) * sc, Vector2(88, 90) * sc), Color("#3a2414"), false, 2.0)
	present = []
	for s in eng.n:
		if counts[D.JAIL][s] > 0:
			present.append(s)
	for i in present.size():
		_badge(jp + Vector2(-30 + (i % 3) * 30, -20 + (i / 3) * 34) * sc, present[i], counts[D.JAIL][present[i]])
	# Caballeros neri dell'Inquisitore
	if eng.inq_pos >= 0:
		var rr: Rect2 = D.REGIONS[eng.inq_pos]["rect"]
		var c2 := bp(rr.position + Vector2(18, rr.size.y - 14))
		UI.draw_cube(self, c2, 22 * sc, Color("#151515"), Color(0.9, 0.85, 0.75, 0.9))
		UI.draw_cube(self, c2 + Vector2(20, 4) * sc, 22 * sc, Color("#151515"), Color(0.9, 0.85, 0.75, 0.9))


func _draw_castillo(counts: Array) -> void:
	var c := bp(D.CASTILLO_POS)
	# torre
	var w := 46 * sc
	var h := 70 * sc
	var base := c + Vector2(0, 20 * sc)
	var body := Rect2(base - Vector2(w / 2, h), Vector2(w, h))
	draw_rect(body.grow(2), Color(0.1, 0.06, 0.02, 0.9))
	draw_rect(body, Color("#cdbb93"))
	for i in 4:
		var bx := body.position.x + i * w / 3.5
		draw_rect(Rect2(Vector2(bx, body.position.y - 9 * sc), Vector2(w / 6.0, 10 * sc)), Color("#cdbb93"))
	draw_rect(Rect2(base - Vector2(8 * sc, 22 * sc), Vector2(16 * sc, 22 * sc)), Color("#3a2414"))
	for i in 3:
		draw_line(Vector2(body.position.x, body.position.y + (i + 1) * h / 4), Vector2(body.end.x, body.position.y + (i + 1) * h / 4), Color(0.4, 0.3, 0.2, 0.5), 1.0)
	# contenuto
	var present := []
	for s in eng.n:
		if counts[s] > 0:
			present.append(s)
	var hidden: bool = eng.castillo_hidden
	for i in present.size():
		var s: int = present[i]
		var ang := -PI / 2 + (i - (present.size() - 1) / 2.0) * 0.62
		var p := c + Vector2(cos(ang), sin(ang)) * 74 * sc + Vector2(0, 18 * sc)
		var hid: bool = hidden and view != null and not view.can_see_castillo(s)
		_badge(p, s, counts[s], hid)


func _draw_mobile(m: int, box: Vector2) -> void:
	var c := bp(box)
	var r := Rect2(c - Vector2(52, 22) * sc, Vector2(104, 44) * sc)
	draw_rect(r.grow(3), Color("#5a3a12"))
	draw_rect(r, Color("#f3dfae"))
	draw_rect(r, Color("#8a5a20"), false, 2.0)
	var v: Array = D.MOBILE[m]
	for i in 3:
		var cell := Rect2(r.position + Vector2(i * r.size.x / 3, 0), Vector2(r.size.x / 3, r.size.y))
		draw_rect(cell, Color("#8a5a20"), false, 1.0)
		var s := str(v[i])
		var fs := int(30 * sc)
		draw_string(UI.font_sc_b, Vector2(cell.position.x, cell.position.y + cell.size.y * 0.78), s, HORIZONTAL_ALIGNMENT_CENTER, cell.size.x, fs, Color("#5a1a10"))


func _draw_king(c: Vector2) -> void:
	# pedina nera con corona
	var s := sc
	draw_circle(c + Vector2(0, 26 * s), 18 * s, Color(0, 0, 0, 0.35))
	var body := PackedVector2Array([c + Vector2(-16, 26) * s, c + Vector2(-9, -2) * s, c + Vector2(9, -2) * s, c + Vector2(16, 26) * s])
	draw_colored_polygon(body, Color("#15110e"))
	draw_circle(c + Vector2(0, -8 * s), 11 * s, Color("#15110e"))
	draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[0]]), Color(1, 0.85, 0.4, 0.8), 1.5, true)
	draw_texture_rect(crown, Rect2(c + Vector2(-22, -40) * s, Vector2(44, 30) * s), false)


func _draw_scores() -> void:
	var at := {}
	for s in eng.n:
		var sc_v: int = eng.score[s]
		var key := posmod(sc_v, 100)
		var k: int = at.get(key, 0)
		at[key] = k + 1
		var p := bp(D.track_pos(sc_v)) + Vector2(0, -k * 9 * sc)
		UI.draw_cube(self, p, 24 * sc, UI.pcol(eng.players[s]["color"]), Color(1, 0.95, 0.8, 0.9))
