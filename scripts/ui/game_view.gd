extends Control
## Vista di gioco: tabellone a sinistra; a destra round, giocatori, carte azione del round e cronaca.
## Sotto il tabellone la barra dei comandi con le istruzioni della scelta in corso.

const D = preload("res://scripts/data/eg_data.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const BoardView = preload("res://scripts/ui/board_view.gd")
const Plancia = preload("res://scripts/ui/plancia.gd")
const CAS := 9
const BOARD_POS := Vector2(10, 10)
const BOARD_W := 1230.0
const RX := 1252.0
const RW := 658.0
var CARD_W := 126.0
var CARD_H := 177.0
const LOW_Y := 920.0          # sotto la mappa: istruzioni e cronaca

var main
var config: Dictionary
var engine: EGEngine
var online = null
var humans: Array = []
var viewer := -1
var pending: Dictionary = {}

# scelte in costruzione
var place_d := {}               # piazzamento: regione -> quanti
var moves: Array = []           # spostamenti [da, a, posto]
var move_src := -1              # regione d'origine scelta
var move_col := -1              # colore scelto
var take_d := {}                # rimozione: sorgente -> quanti (-1 = corte)

# nodi
var board: Control
var header_lbl: Label
var sub_lbl: Label
var rows_box: VBoxContainer
var plance := []
var cards_box: HBoxContainer
var chron: RichTextLabel
var msg_lbl: Label
var btn_row: HBoxContainer
var modal: Control
var toast: Control
var popup: Control
var log_panel: PanelContainer
var log_text: RichTextLabel
var online_lbl: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(1920, 1080)
	online = config.get("online", null)
	var bg := ColorRect.new()
	bg.color = Color("#160d07")
	bg.size = size
	add_child(bg)
	var vign := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.25, 0.14, 0.07, 1))
	g.set_color(1, Color(0.05, 0.03, 0.02, 1))
	grad.gradient = g
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.45)
	grad.fill_to = Vector2(1.1, 1.1)
	vign.texture = grad
	vign.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vign.size = size
	add_child(vign)

	engine = EGEngine.new()
	add_child(engine)
	engine.setup(config)
	engine.ai_delay = config.get("ai_delay", 0.6)
	for s in engine.n:
		engine.ais[s] = EGAI.new(int(engine.players[s]["level"]), int(config.get("seed", 0)) * 7 + s + 1)
	if online != null:
		humans = [online.seat]
		online.view = self
		add_child(online)
		engine.online = online
		if online.role != "host":
			online.heartbeat_loop()
	else:
		for s in engine.n:
			if not engine.players[s]["ai"]:
				humans.append(s)
	viewer = humans[0] if humans.size() > 0 else 0
	engine.pause_enabled = humans.size() > 0

	_build_board()
	_build_side()
	_build_bottom()
	_build_log()
	modal = Control.new()
	modal.size = size
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal)
	popup = Control.new()
	popup.size = size
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup)
	toast = Control.new()
	toast.size = size
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	_build_online_label()

	engine.changed.connect(refresh)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.pause_requested.connect(_on_pause)
	engine.game_ended.connect(_on_game_end)
	engine.fx.connect(_on_fx)
	refresh()
	if online != null and online.catchup:
		online_status("Riprendo la partita dal punto in cui era…")
	engine.run.call_deferred()


func _exit_tree() -> void:
	if engine != null:
		engine.abort = true


# =================================================================== costruzione

func _build_board() -> void:
	var h := BOARD_W * D.BOARD_SIZE.y / D.BOARD_SIZE.x
	var frame := Panel.new()
	frame.position = BOARD_POS - Vector2(5, 5)
	frame.size = Vector2(BOARD_W + 10, h + 10)
	var st := UI.panel_style(Color("#0b0603"), UI.GOLD_D, 3, 6)
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 12
	frame.add_theme_stylebox_override("panel", st)
	add_child(frame)
	board = BoardView.new()
	board.position = BOARD_POS
	board.size = Vector2(BOARD_W, h)
	board.eng = engine
	board.view = self
	add_child(board)
	board.region_clicked.connect(_on_region_click)
	board.region_hovered.connect(_on_region_hover)


func _build_side() -> void:
	var head := PanelContainer.new()
	head.position = Vector2(RX, 6)
	head.custom_minimum_size = Vector2(RW, 92)
	head.add_theme_stylebox_override("panel", UI.panel_style(Color("#1e120a"), UI.GOLD_D, 2, 8))
	add_child(head)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -4)
	head.add_child(tv)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	tv.add_child(hb)
	header_lbl = UI.title("El Grande", 38)
	header_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(header_lbl)
	for b in [["Regole", _show_rules_popup], ["Cronaca", _toggle_log], ["Menu", _ask_quit]]:
		var bt := UI.button(b[0], 104, 40, 19)
		bt.pressed.connect(b[1])
		bt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(bt)
	sub_lbl = UI.label("", 18, UI.MUTED, UI.font_sc)
	sub_lbl.clip_text = true
	sub_lbl.custom_minimum_size.x = RW - 24
	tv.add_child(sub_lbl)

	# plance dei giocatori
	rows_box = VBoxContainer.new()
	rows_box.position = Vector2(RX, 80)
	rows_box.add_theme_constant_override("separation", 6)
	add_child(rows_box)
	var ncards := 7 if (engine.grandissimo or engine.intrigo or engine.colonie) else 5
	if engine.intrigo:
		ncards = 2 + D.IK_CAB[clampi(engine.n, 2, 5)].size() + (2 if engine.colonie else 0)
	CARD_W = minf(126.0, floorf((RW - 6 * (ncards - 1)) / ncards))
	CARD_H = roundf(CARD_W * (1.617 if engine.intrigo else 1.405))
	var cards_y := 1072.0 - CARD_H
	var ph := minf(215.0, (cards_y - 8 - 80 - 6 * (engine.n - 1)) / engine.n)
	for s in engine.n:
		var pl := Plancia.new()
		pl.eng = engine
		pl.seat = s
		pl.view = self
		pl.setup(RW, ph)
		rows_box.add_child(pl)
		plance.append(pl)

	# carte azione del round, sotto le plance
	cards_box = HBoxContainer.new()
	cards_box.position = Vector2(RX, cards_y)
	cards_box.add_theme_constant_override("separation", 6)
	add_child(cards_box)

	# cronaca, sotto la mappa a destra
	var cp := PanelContainer.new()
	cp.position = Vector2(BOARD_POS.x + 620, LOW_Y)
	cp.custom_minimum_size = Vector2(BOARD_W - 620 + 4, 1072 - LOW_Y)
	cp.size = cp.custom_minimum_size
	cp.add_theme_stylebox_override("panel", UI.panel_style(Color("#140b06"), Color("#3a2614"), 1, 6))
	add_child(cp)
	chron = RichTextLabel.new()
	chron.bbcode_enabled = true
	chron.scroll_following = true
	chron.add_theme_font_size_override("normal_font_size", 18)
	chron.add_theme_font_size_override("bold_font_size", 18)
	chron.add_theme_color_override("default_color", Color("#d8c8a6"))
	cp.add_child(chron)


func _build_bottom() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(BOARD_POS.x - 4, LOW_Y)
	p.custom_minimum_size = Vector2(612, 1072 - LOW_Y)
	p.size = p.custom_minimum_size
	var st := UI.panel_style(Color("#24150b"), UI.GOLD_D, 2, 8)
	p.add_theme_stylebox_override("panel", st)
	add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	msg_lbl = UI.label("", 22, UI.TEXT, UI.font_body)
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(msg_lbl)
	btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(btn_row)


func _build_log() -> void:
	log_panel = PanelContainer.new()
	log_panel.position = Vector2(300, 90)
	log_panel.custom_minimum_size = Vector2(900, 820)
	log_panel.size = Vector2(900, 820)
	log_panel.add_theme_stylebox_override("panel", UI.panel_style(Color("#140b06f4"), UI.GOLD, 2, 10))
	log_panel.visible = false
	add_child(log_panel)
	var vb := VBoxContainer.new()
	log_panel.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_child(UI.title("Cronaca della partita", 34))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	var cl := UI.button("Chiudi", 120, 44, 20)
	cl.pressed.connect(_toggle_log)
	hb.add_child(cl)
	vb.add_child(hb)
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(log_text)


func _toggle_log() -> void:
	log_panel.visible = not log_panel.visible
	if log_panel.visible:
		move_child(log_panel, get_child_count() - 1)


func _fmt_log(t: String) -> String:
	var line := t
	for s in engine.n:
		var nm: String = engine.pname(s)
		line = line.replace(nm, "[color=#%s][b]%s[/b][/color]" % [UI.plight(engine.players[s]["color"]).to_html(false), nm])
	if t.begins_with("—") or t.begins_with("=="):
		line = "[color=#d9b45a][b]%s[/b][/color]" % t
	elif t.begins_with("Valutazione"):
		line = "[color=#f0d08a]%s[/color]" % line
	return line


func _on_log(t: String) -> void:
	var f := _fmt_log(t)
	chron.append_text(f + "\n")
	log_text.append_text(f + "\n")


# =================================================================== aggiornamento

func refresh() -> void:
	if engine == null:
		return
	_refresh_header()
	_refresh_rows()
	_refresh_cards()
	board.queue_redraw()


func _refresh_header() -> void:
	var tot: int = engine.rounds.size()
	if engine.cur_round == 0:
		sub_lbl.text = "Preparazione"
		return
	var ph: String = {"power": "si giocano le carte potere", "turn": "turni dei giocatori", "scoring": "valutazione generale", "over": "partita finita"}.get(engine.phase, "")
	var nxt := 3
	for k in [3, 6, 9]:
		if engine.cur_round <= k:
			nxt = k
			break
	sub_lbl.text = "Round %d di 9 · %s · valutazione dopo il %d°" % [engine.cur_round, ph, nxt]
	if tot < 9:
		sub_lbl.text = "Round %d (%d° di %d) · %s · valutazione dopo il %d°" % [engine.cur_round, engine.round_i + 1, tot, ph, nxt]
	if engine.phase == "over":
		sub_lbl.text = "Partita finita"


func _refresh_rows() -> void:
	for pl in plance:
		pl.update_info()


func _refresh_cards() -> void:
	for c in cards_box.get_children():
		c.queue_free()
	if engine.intrigo:
		_refresh_ik_cards()
		return
	var choosing: bool = pending.get("type", "") == "action"
	for ci in engine.showing:
		var cv := CardView.new()
		cv.setup(ci, Vector2(CARD_W, CARD_H))
		if engine.taken.has(ci):
			cv.owner_color = engine.players[engine.taken[ci]]["color"]
		if choosing and ci in pending["cards"]:
			cv.glow = true
		cv.gui_input.connect(func(ev): _on_card_input(ev, ci))
		cv.mouse_entered.connect(func(): _card_popup(ci, true))
		cv.mouse_exited.connect(func(): _card_popup(ci, false))
		cards_box.add_child(cv)


## Intrigo & il Re: carta del Re, dell'Intrigo e carte Caballero del round, con chi le ha.
func _refresh_ik_cards() -> void:
	var items := [[D.IK_KING, "", engine.king_holder], [D.IK_INTRIGUE, "", engine.intrigue_holder]]
	var cabs: Array = D.IK_CAB[clampi(engine.n, 2, 5)]
	for i in cabs.size():
		var who := -1
		for s in engine.n:
			if engine.cab_card[s] == cabs[i] and engine.phase != "power":
				who = s
		items.append([D.IK_KING, "res://assets/intrigo/c%d.jpg" % cabs[i], who])
	if engine.colonie:
		for c2 in engine.showing:
			items.append([c2, "", engine.taken.get(c2, -1)])
	for it in items:
		var cv := CardView.new()
		cv.tex_override = it[1]
		cv.setup(it[0], Vector2(CARD_W, CARD_W * 1.617))
		if it[2] >= 0:
			cv.owner_color = engine.players[it[2]]["color"]
		var ci: int = it[0]
		var tx: String = it[1]
		cv.mouse_entered.connect(func(): _card_popup(ci, true, "blue", Vector2(-1, -1), tx))
		cv.mouse_exited.connect(func(): _card_popup(ci, false))
		cards_box.add_child(cv)


func _card_popup(ci: int, on: bool, ckey := "blue", pos := Vector2(-1, -1), tex := "") -> void:
	for c in popup.get_children():
		c.queue_free()
	if not on:
		return
	var cv := CardView.new()
	cv.color_key = ckey
	cv.tex_override = tex
	var sz := Vector2(360, 506) if ci < D.IK_FIRST else Vector2(330, 534)
	cv.setup(ci, sz, true)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.position = pos if pos.x >= 0 else Vector2(RX - sz.x - 12, 1072 - sz.y - 10)
	popup.add_child(cv)
	popup.move_to_front()


func _on_card_input(ev: InputEvent, ci: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if pending.get("type", "") == "action" and ci in pending["cards"]:
			_card_popup(ci, false)
			_provide(ci)


# =================================================================== supporto al tabellone

func allowed_regions() -> Array:
	if pending.is_empty():
		return []
	match str(pending["type"]):
		"region":
			return pending["allowed"]
		"place":
			return pending["targets"] if _placed() < int(pending["n"]) else []
		"moves":
			if move_src < 0:
				return _move_sources()
			return _move_dests()
		"take":
			var out := []
			if _taken() < int(pending["n"]):
				var counts := display_counts()
				for src in pending["sources"]:
					if int(src) >= 0 and counts[int(src)][int(pending["seat"])] > 0:
						out.append(int(src))
			return out
	return []


## Caballeros mostrati sul tabellone: quelli del motore più le scelte non ancora confermate.
func display_counts() -> Array:
	var c: Array = engine.cab.duplicate(true)
	if pending.is_empty():
		return c
	var s: int = pending["seat"]
	for r in place_d:
		c[r][s] += place_d[r]
	for m in moves:
		c[m[0]][m[2]] -= 1
		c[m[1]][m[2]] += 1
	for src in take_d:
		if src >= 0:
			c[src][s] -= take_d[src]
	return c


## Carte coperte di un giocatore (Boicottaggio, Re in incognito): le vede solo lui.
func can_see_secret(s: int) -> bool:
	if engine.game_over:
		return true
	if online != null:
		return s == online.seat
	return s in humans and humans.size() == 1 or (s == engine.current and s in humans)


func can_see_castillo(s: int) -> bool:
	if not engine.castillo_hidden:
		return true
	return s == viewer or engine.phase == "over"


func _placed() -> int:
	var t := 0
	for r in place_d:
		t += place_d[r]
	return t


func _taken() -> int:
	var t := 0
	for k in take_d:
		t += take_d[k]
	return t


func _move_counts() -> Array:
	var own := 0
	var foe := 0
	for m in moves:
		if m[2] == pending["seat"]:
			own += 1
		else:
			foe += 1
	return [own, foe]


func _move_ok(a: int, b: int, p: int) -> bool:
	var spec: Dictionary = pending["spec"]
	var s: int = pending["seat"]
	var counts := display_counts()
	var oc := _move_counts()
	if moves.size() >= int(spec["max"]):
		return false
	if a == b or not (a in engine.move_sources(spec)) or not (b in engine.move_dests(spec)):
		return false
	if spec.has("caps") and spec["caps"].has(a):
		var used := 0
		for m in moves:
			if m[0] == a:
				used += 1
		if used >= int(spec["caps"][a]):
			return false
	if engine.colonie and b == 11:
		var totf := 0
		for t in engine.n:
			totf += counts[b][t]
		if totf >= 3:
			return false
	if counts[a][p] <= 0:
		return false
	var fr := int(spec.get("from", -1))
	if fr >= 0 and a != fr:
		return false
	if spec.has("to") and b != int(spec["to"]):
		return false
	if spec.has("pair") and not (a in spec["pair"] and b in spec["pair"]):
		return false
	if engine.limit6.has(b):
		var tot := 0
		for t in engine.n:
			tot += counts[b][t]
		if tot >= 6:
			return false
	if spec.get("single", false) and not moves.is_empty() and moves[0][0] != a:
		return false
	if p == s and oc[0] >= int(spec["own"]):
		return false
	if p != s and oc[1] >= int(spec["foe"]):
		return false
	return true


func _movable_colors(a: int) -> Array:
	var out := []
	for p in engine.n:
		for b in 17:
			if _move_ok(a, b, p):
				out.append(p)
				break
	return out


func _move_sources() -> Array:
	var out := []
	for a in 17:
		if not _movable_colors(a).is_empty():
			out.append(a)
	return out


func _move_dests() -> Array:
	var out := []
	for b in 17:
		if _move_ok(move_src, b, move_col):
			out.append(b)
	return out


# =================================================================== clic sulla mappa

func _on_region_hover(r: int) -> void:
	if r < 0:
		board.tooltip_text = ""
		return
	var counts := display_counts()
	var lines := ["%s" % D.region_name(r)]
	var mapr: bool = r in engine.map_regions()
	if r == D.SHIP_G:
		lines.append("Chi ha un gettone nave può piazzarvi i Caballeros della corte, ovunque sia il Re;")
		lines.append("all'inizio del suo turno li sbarca in una regione costiera. Non si valuta.")
	elif r == D.JAIL:
		lines.append("Prigionieri: li libera chi prende la carta del Re.")
	else:
		var v := engine.vals(r)
		lines.append("Valori %d / %d / %d" % [v[0], v[1], v[2]] + (" (segna-punti mobile)" if r in engine.mobile else ""))
	if engine.taboo(r):
		lines.append("Regione del Re: nessuno può entrare o uscire.")
	elif mapr:
		lines.append("Confina con: " + ", ".join(engine.adj(r).map(func(x): return D.region_name(x))))
	if r == engine.inq_pos and engine.grandissimo:
		lines.append("Qui ci sono i 2 Caballeros neri dell'Inquisitore (non contano).")
	if engine.colonie:
		lines.append_array(_colonie_info(r))
	for s in engine.n:
		var q: int = counts[r][s]
		if q > 0:
			lines.append("  %s: %s" % [engine.pname(s), "?" if r == CAS and not can_see_castillo(s) else str(q)])
	if mapr:
		var pts := engine.region_points(r)
		if not pts.is_empty():
			var pp := []
			for s in pts:
				pp.append("%s %d" % [engine.pname(s), pts[s]])
			lines.append("Se valutata ora: " + ", ".join(pp))
	board.tooltip_text = "\n".join(lines)


## Righe del suggerimento per le regioni delle Colonie.
func _colonie_info(r: int) -> Array:
	var out := []
	match r:
		11:
			out.append("Al massimo 3 Caballeros. Ambasciatore +2, Inviato +1.")
			var nm := ["Ambasciatore", "Inviato"]
			for i in 2:
				if engine.france_slots[i] >= 0:
					out.append("%s: %s" % [nm[i], engine.pname(engine.france_slots[i])])
			out.append("Ci si arriva quando il Re è in Aragona o Catalogna, o con la nave.")
		12:
			out.append("Prende punti solo il Capitano (+3)%s." % ((": " + engine.pname(engine.captain)) if engine.captain >= 0 else ""))
			out.append("Si sale dalla corte quando il Re è in una regione costiera.")
			out.append("A inizio turno si sbarca in America, Francia, Mediterraneo o sulla costa.")
		13:
			out.append("Il Viceré (+5) non conta per la maggioranza%s." % ((": " + engine.pname(engine.viceroy)) if engine.viceroy >= 0 else ""))
			out.append("Oro libero: %d (vale 6 punti portato in Spagna)." % engine.discs[13]["gold"])
		14:
			out.append("Merci libere: %d (valgono 4 punti portate in Spagna)." % engine.discs[14]["wares"])
	if int(engine.black.get(r, 0)) > 0:
		out.append("Caballeros neri dell'Inquisitore: %d%s." % [engine.black[r], (" (contano per %s)" % engine.pname(engine.inq_owner)) if engine.inq_owner >= 0 else " (giocatore invisibile)"])
	if r == engine.limit_r:
		var lc: Array = engine._limit_counts()
		var parts := []
		for s in engine.n:
			if lc[s] > 0:
				parts.append("%s %d" % [engine.pname(s), lc[s]])
		out.append("Tavola limite: contano al massimo %d Caballeros (%s)." % [engine.limit_n, ", ".join(parts) if not parts.is_empty() else "vuota"])
	for s in engine.n:
		if engine.carry[s].has(r):
			var c: Dictionary = engine.carry[s][r]
			out.append("%s porta %d oro e %d merci." % [engine.pname(s), c["gold"], c["wares"]])
	return out


func _on_region_click(r: int, button: int) -> void:
	if pending.is_empty():
		return
	var tp := str(pending["type"])
	if button == MOUSE_BUTTON_RIGHT:
		match tp:
			"place":
				if place_d.get(r, 0) > 0:
					place_d[r] -= 1
					if place_d[r] == 0:
						place_d.erase(r)
			"moves":
				_undo_move()
			"take":
				if take_d.get(r, 0) > 0:
					take_d[r] -= 1
					if take_d[r] == 0:
						take_d.erase(r)
		_update_controls()
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	match tp:
		"region":
			if r in pending["allowed"]:
				_provide(r)
		"place":
			if r in pending["targets"] and _placed() < int(pending["n"]) and place_d.get(r, 0) < engine.room(r):
				place_d[r] = place_d.get(r, 0) + 1
		"moves":
			if move_src < 0:
				var cols := _movable_colors(r)
				if cols.size() == 1:
					move_src = r
					move_col = cols[0]
				elif cols.size() > 1:
					_color_chooser(r, cols)
			else:
				if r == move_src:
					move_src = -1
					move_col = -1
				elif _move_ok(move_src, r, move_col):
					moves.append([move_src, r, move_col])
					var keep_src := move_src
					var keep_col := move_col
					move_src = -1
					move_col = -1
					# continua con lo stesso colore dalla stessa regione, se possibile
					if _move_ok_any(keep_src, keep_col):
						move_src = keep_src
						move_col = keep_col
		"take":
			if r in allowed_regions():
				take_d[r] = take_d.get(r, 0) + 1
	_update_controls()


func _move_ok_any(a: int, p: int) -> bool:
	for b in 17:
		if _move_ok(a, b, p):
			return true
	return false


func _undo_move() -> void:
	if move_src >= 0:
		move_src = -1
		move_col = -1
	elif not moves.is_empty():
		moves.pop_back()


func _color_chooser(r: int, cols: Array) -> void:
	_clear_modal()
	var vb := _open_modal("Di chi sposti un Caballero da %s?" % D.region_name(r), 560)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	for p in cols:
		var b := UI.button(engine.pname(p), 150, 56, 22)
		b.add_theme_color_override("font_color", UI.plight(engine.players[p]["color"]))
		b.pressed.connect(func():
			_clear_modal()
			move_src = r
			move_col = p
			_update_controls())
		hb.add_child(b)
	vb.add_child(hb)
	var cancel := UI.button("Annulla", 160, 48, 20)
	cancel.pressed.connect(func(): _clear_modal())
	vb.add_child(cancel)


# =================================================================== decisioni

func _who(s: int) -> String:
	return "%s, " % engine.pname(s) if humans.size() > 1 else ""


func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else t


func _on_decision(req: Dictionary) -> void:
	# scelte segrete con più persone allo stesso schermo: prima la tenda
	if req.get("secret", false) and humans.size() > 1 and online == null and not req.get("_shown", false):
		req["_shown"] = true
		_curtain(int(req["seat"]), func(): _on_decision(req))
		return
	pending = req
	place_d = {}
	moves = []
	move_src = -1
	move_col = -1
	take_d = {}
	var s: int = req["seat"]
	if viewer != s:
		viewer = s
	_clear_modal()
	refresh()
	match str(req["type"]):
		"power":
			_power_modal(req)
		"ik_power":
			_ik_power_modal(req)
		"deck":
			_deck_modal(req)
		"action":
			msg_lbl.text = _cap(_who(s) + "scegli una carta azione: clic su una delle carte in basso a destra (passaci sopra il mouse per leggerla).")
			_refresh_cards()
			_clear_buttons()
		"pick":
			_pick_modal(req)
		_:
			_update_controls()


func _clear_buttons() -> void:
	for c in btn_row.get_children():
		c.queue_free()


func _add_btn(text: String, cb: Callable, prim := false, enabled := true) -> Button:
	var b := UI.button(text, 0, 56, 22)
	b.custom_minimum_size.x = maxf(140, text.length() * 13 + 40)
	if prim:
		UI.primary(b)
	b.disabled = not enabled
	b.pressed.connect(cb)
	btn_row.add_child(b)
	return b


## Istruzioni e pulsanti per le scelte fatte sul tabellone.
func _update_controls() -> void:
	board.queue_redraw()
	_clear_buttons()
	if pending.is_empty():
		return
	_update_controls_inner()
	msg_lbl.text = _cap(msg_lbl.text)


func _update_controls_inner() -> void:
	var s: int = pending["seat"]
	var who := _who(s)
	match str(pending["type"]):
		"region":
			var extra := ""
			match str(pending["ctx"]):
				"one_each":
					extra = " (clic su una regione evidenziata)"
				_:
					extra = " — clic su una regione evidenziata." if str(pending["title"]).ends_with("?") else ": clic su una regione evidenziata."
			msg_lbl.text = who + str(pending["title"]) + extra
			if pending.get("skip", false):
				_add_btn("Non farlo", func(): _provide(-1))
		"place":
			var q: int = pending["n"]
			msg_lbl.text = "%s%s: clic sulle regioni evidenziate (confinanti col Re) o sul Castillo. Tasto destro per togliere. Piazzati %d di %d." % [who, pending["title"], _placed(), q]
			if pending["ctx"] == "court2":
				msg_lbl.text = "%sPiazza fino a %d Caballeros dalla corte in qualunque regione (non quella del Re) o nel Castillo. Piazzati %d." % [who, q, _placed()]
			_add_btn("Ricomincia", func():
				place_d = {}
				_update_controls(), false, _placed() > 0)
			_add_btn("Conferma", func(): _provide(place_d.duplicate()), true)
		"moves":
			var spec: Dictionary = pending["spec"]
			var oc := _move_counts()
			var t := "%s%s. " % [who, pending["title"]]
			if move_src < 0:
				t += "Clic sulla regione da cui togliere un Caballero."
			else:
				t += "Ora clic sulla regione di destinazione per il Caballero %s da %s (anche il Castillo)." % [engine.pname(move_col), D.region_name(move_src)]
			t += "  Mossi %d di %d" % [moves.size(), int(spec["max"])]
			if spec["own"] < spec["max"] and spec["foe"] > 0 and spec["own"] > 0:
				t += " (tuoi %d/%d, avversari %d/%d)" % [oc[0], spec["own"], oc[1], spec["foe"]]
			msg_lbl.text = t + "."
			_add_btn("Annulla ultimo", func():
				_undo_move()
				_update_controls(), false, moves.size() > 0 or move_src >= 0)
			_add_btn("Conferma", func(): _provide(moves.duplicate(true)), true)
		"take":
			var q: int = pending["n"]
			var exact: bool = pending.get("exact", false)
			msg_lbl.text = "%s%s. Clic sulle regioni (tasto destro per togliere). Scelti %d di %d." % [who, pending["title"], _taken(), q]
			if -1 in pending["sources"]:
				var avail: int = engine.court[s] - take_d.get(-1, 0)
				_add_btn("Dalla corte (%d)" % avail, func():
					if _taken() < q and engine.court[s] - take_d.get(-1, 0) > 0:
						take_d[-1] = take_d.get(-1, 0) + 1
					_update_controls(), false, avail > 0 and _taken() < q)
			_add_btn("Ricomincia", func():
				take_d = {}
				_update_controls(), false, _taken() > 0)
			_add_btn("Conferma", func(): _provide(take_d.duplicate()), true, not exact or _taken() == q)


func _provide(r) -> void:
	pending = {}
	place_d = {}
	moves = []
	move_src = -1
	move_col = -1
	take_d = {}
	_clear_modal()
	_clear_buttons()
	msg_lbl.text = ""
	refresh()
	engine.provide_decision(r)


func _idle_text() -> String:
	if engine.current >= 0 and not (engine.current in humans):
		return "%s sta pensando…" % engine.pname(engine.current)
	return ""


# ------------------------------------------------------------------ finestre

func _clear_modal() -> void:
	for c in modal.get_children():
		c.queue_free()
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _open_modal(title_text: String, w := 640.0, dim := true, pos := Vector2(-1, -1)) -> VBoxContainer:
	_clear_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP if dim else Control.MOUSE_FILTER_IGNORE
	if dim:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.55)
		shade.size = size
		modal.add_child(shade)
	var box := PanelContainer.new()
	var st := UI.panel_style(Color("#1e120af6"), UI.GOLD, 2, 10)
	st.set_content_margin_all(18)
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 14
	box.add_theme_stylebox_override("panel", st)
	box.custom_minimum_size = Vector2(w, 0)
	modal.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	box.add_child(vb)
	var tl := UI.heading(title_text, 26)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size.x = w - 40
	vb.add_child(tl)
	if pos.x >= 0:
		box.position = pos
	else:
		_center_box.call_deferred(box)
	return vb


func _center_box(box: Control) -> void:
	if not is_instance_valid(box):
		return
	box.reset_size()
	box.position = Vector2(BOARD_POS.x + BOARD_W / 2.0, 500) - box.size / 2.0


func _pick_modal(req: Dictionary) -> void:
	var s: int = req["seat"]
	var opts: Array = req["options"]
	var vb := _open_modal(_cap(_who(s) + str(req["title"])), 640 if not req.has("card") else 760)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	if req.has("card"):
		var cv := CardView.new()
		cv.setup(int(req["card"]), Vector2(250, 351), true)
		hb.add_child(cv)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(col)
	if req["ctx"] == "veto":
		col.add_child(UI.wrap(UI.label("Il veto annulla l'intera azione speciale (non il piazzamento dei Caballeros).", 20, UI.MUTED), 440))
	for i in opts.size():
		var b := UI.button(str(opts[i]["label"]), 440, 56, 22)
		if i == opts.size() - 1 and req["ctx"] in ["do", "veto"]:
			UI.primary(b)
		var ii := i
		b.pressed.connect(func(): _provide(ii))
		col.add_child(b)
	if req["ctx"] == "mobile":
		vb.get_parent().custom_minimum_size.x = 820


func _power_modal(req: Dictionary) -> void:
	var s: int = req["seat"]
	var p: Dictionary = engine.players[s]
	var used: Array = req["used"]
	var legal: Array = req["legal"]
	var vb := _open_modal(_cap(_who(s)) + ("G" if _who(s) == "" else "g") + "ioca una carta potere: più è alta, prima scegli la carta azione; i Caballeros raffigurati passano dalle province alla tua corte.", 1130, false, Vector2(BOARD_POS.x + 10, 450))
	var info := []
	for t in engine.n:
		if engine.played[t] > 0:
			info.append("%s %d" % [engine.pname(t), engine.played[t]])
	vb.add_child(UI.label(("Già giocate: " + ", ".join(info)) if not info.is_empty() else "Sei il primo a giocare.", 21, UI.MUTED))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)
	var hand: Array = req["hand"]
	for v in hand:
		var ok: bool = v in legal
		var b := TextureButton.new()
		b.texture_normal = UI.power_tex(p["color"], v)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(80, 120)
		b.disabled = not ok
		b.modulate = Color.WHITE if ok else Color(0.35, 0.35, 0.35)
		b.tooltip_text = "Carta %d: %d Caballeros alla corte%s" % [v, D.POWER_CAB[v], "" if ok else " (già giocata da un altro)"]
		var vv: int = v
		b.pressed.connect(func(): _provide(vv))
		b.mouse_entered.connect(func(): b.scale = Vector2(1.06, 1.06))
		b.mouse_exited.connect(func(): b.scale = Vector2.ONE)
		hb.add_child(b)
	msg_lbl.text = _cap(_who(s) + "scegli la carta potere.")


func _ckey(s: int) -> String:
	return D.COLORS[engine.players[s]["color"]]["key"]


## Intrigo & il Re: la carta del round (o la carta vera dopo il Jolly).
func _ik_power_modal(req: Dictionary) -> void:
	var s: int = req["seat"]
	var legal: Array = req["legal"]
	var joker: bool = req["ctx"] == "joker"
	var head := "Jolly: ora scegli la carta vera dalla tua mano." if joker else "gioca una carta azione: la più alta prende la carta del Re e più Caballeros, la più bassa l'Intrigo."
	var vb := _open_modal(_cap(_who(s) + head), 1130, false, Vector2(BOARD_POS.x + 10, 380))
	var info := []
	for t in engine.n:
		if engine.ik_played[t] >= 0:
			info.append("%s %s" % [engine.pname(t), "Jolly" if engine.played[t] == 0 else str(engine.played[t])])
	vb.add_child(UI.label(("Già giocate: " + ", ".join(info)) if not info.is_empty() else "Sei il primo a giocare.", 21, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for ci in req["hand"]:
		var ok: bool = ci in legal
		var cv := CardView.new()
		cv.color_key = _ckey(s)
		cv.setup(ci, Vector2(116, 188))
		cv.dim = not ok
		cv.glow = ok
		var cc: int = ci
		cv.gui_input.connect(func(ev):
			if ok and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_card_popup(-1, false)
				_provide(cc))
		cv.mouse_entered.connect(func(): _card_popup(cc, true, _ckey(s)))
		cv.mouse_exited.connect(func(): _card_popup(cc, false))
		grid.add_child(cv)
	msg_lbl.text = _cap(_who(s) + "scegli la carta (le carte scure hanno un valore già giocato da un altro).")


## Intrigo & il Re: si scelgono 13 carte delle 31.
func _deck_modal(req: Dictionary) -> void:
	var s: int = req["seat"]
	var need: int = req["n"]
	var sel := {}
	var vb := _open_modal(_cap(_who(s) + "scegli le %d carte con cui giocherai la partita (ne userai una per round)." % need), 1880, true, Vector2(20, 20))
	var count := UI.label("", 22, UI.GOLD, UI.font_sc_b)
	var grid := GridContainer.new()
	grid.columns = 16
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	vb.add_child(grid)
	var views := {}
	var ok := UI.primary(UI.button("Conferma", 220, 52, 22))
	var upd := func():
		count.text = "Scelte %d di %d" % [sel.size(), need]
		ok.disabled = sel.size() != need
		for c in views:
			views[c].dim = not sel.has(c)
			views[c].glow = sel.has(c)
			views[c].queue_redraw()
	for ci in req["cards"]:
		var cv := CardView.new()
		cv.color_key = _ckey(s)
		cv.setup(ci, Vector2(110, 178))
		views[ci] = cv
		var cc: int = ci
		cv.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if sel.has(cc):
					sel.erase(cc)
				elif sel.size() < need:
					sel[cc] = true
				upd.call())
		cv.mouse_entered.connect(func(): _card_popup(cc, true, _ckey(s), Vector2(1500, 560)))
		cv.mouse_exited.connect(func(): _card_popup(cc, false))
		grid.add_child(cv)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	hb.add_child(count)
	var sug := UI.button("Carte consigliate", 260, 52, 22)
	sug.tooltip_text = "Le 13 carte consigliate per la prima partita."
	sug.pressed.connect(func():
		sel.clear()
		for v in D.IK_SUGGESTED:
			sel[D.ik_by_val(v)] = true
		upd.call())
	hb.add_child(sug)
	var none := UI.button("Nessuna", 180, 52, 22)
	none.pressed.connect(func():
		sel.clear()
		upd.call())
	hb.add_child(none)
	ok.pressed.connect(func():
		_card_popup(-1, false)
		_provide(sel.keys()))
	hb.add_child(ok)
	upd.call()


## Tenda fra un giocatore e l'altro quando la scelta è segreta (hotseat).
func _curtain(s: int, then: Callable) -> void:
	_clear_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.01, 0.97)
	shade.size = size
	modal.add_child(shade)
	var vb := VBoxContainer.new()
	vb.position = Vector2(660, 380)
	vb.add_theme_constant_override("separation", 20)
	modal.add_child(vb)
	vb.add_child(UI.title("Tocca a %s" % engine.pname(s), 56))
	vb.add_child(UI.label("Scelta segreta col disco: gli altri non guardino lo schermo.", 24))
	var b := UI.primary(UI.button("SONO PRONTO", 280, 60, 26))
	b.pressed.connect(func():
		_clear_modal()
		then.call())
	vb.add_child(b)


# ------------------------------------------------------------------ pause ed effetti

func _on_pause(req: Dictionary) -> void:
	var kind: String = req.get("kind", "")
	var vb := _open_modal(str(req.get("title", "")), 760)
	match kind:
		"discs", "castillo":
			var picks: Dictionary = req.get("picks", {})
			if picks.is_empty():
				vb.add_child(UI.label("Nessuno aveva Caballeros nel Castillo.", 22))
			for s in picks:
				var row := UI.label("%s  →  %s" % [engine.pname(s), D.region_name(picks[s])], 24, UI.plight(engine.players[s]["color"]), UI.font_sc_b)
				vb.add_child(row)
		"general":
			var gains: Array = req.get("gains", [])
			var lst := range(engine.n)
			lst.sort_custom(func(a, b): return engine.score[a] > engine.score[b])
			for s in lst:
				var row := HBoxContainer.new()
				var nm := UI.label(engine.pname(s), 26, UI.plight(engine.players[s]["color"]), UI.font_sc_b)
				nm.custom_minimum_size.x = 300
				row.add_child(nm)
				var g := UI.label("+%d" % gains[s], 26, UI.GREEN, UI.font_sc_b)
				g.custom_minimum_size.x = 120
				row.add_child(g)
				row.add_child(UI.label("totale %d" % engine.score[s], 26, UI.GOLD, UI.font_sc_b))
				vb.add_child(row)
	var ok := UI.primary(UI.button("Avanti", 220, 56, 24))
	ok.pressed.connect(func():
		_clear_modal()
		engine.provide_decision(true))
	vb.add_child(ok)


func _on_fx(kind: String, data: Dictionary) -> void:
	match kind:
		"flow":
			_fly(int(data["seat"]), data["from"], data["to"], int(data["n"]))
		"score":
			var r: int = data["r"]
			board.flash[r] = board.t
			var pts: Dictionary = data["pts"]
			var i := 0
			var rr: Rect2 = D.REGIONS[r]["rect"] if r < 9 else Rect2(D.CASTILLO_POS - Vector2(60, 60), Vector2(120, 120))
			for s in pts:
				var l := UI.label("+%d" % pts[s], 34, UI.plight(engine.players[s]["color"]), UI.font_sc_b)
				l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
				l.add_theme_constant_override("outline_size", 8)
				var sc: float = board.sc
				l.position = BOARD_POS + (rr.position + Vector2(rr.size.x / 2.0 - 30 + (i - pts.size() / 2.0) * 44, 20)) * sc
				toast.add_child(l)
				var tw := l.create_tween()
				tw.tween_property(l, "position:y", l.position.y - 60, 1.6)
				tw.parallel().tween_property(l, "modulate:a", 0.0, 1.6).set_delay(0.6)
				tw.tween_callback(l.queue_free)
				i += 1
		"veto":
			_banner("VETO! di %s" % engine.pname(int(data["seat"])), UI.RED_L)
		"king":
			board.queue_redraw()


## Punto dello schermo di province, corte o di una regione del tabellone.
func _spot(s: int, where) -> Vector2:
	if where is String:
		return plance[s].prov_point() if where == "prov" else plance[s].court_point()
	var r := int(where)
	var c: Vector2 = D.CASTILLO_POS if r == CAS else D.REGIONS[r]["rect"].get_center()
	return board.global_position + c * board.sc


## Cubetti in volo da un posto all'altro.
func _fly(s: int, from, to, q: int) -> void:
	if engine.headless or (online != null and online.catchup):
		return
	var col := UI.pcol(engine.players[s]["color"])
	var a := _spot(s, from)
	var b := _spot(s, to)
	for i in mini(q, 7):
		var cube := Control.new()
		cube.size = Vector2(24, 24)
		cube.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cube.draw.connect(func(): UI.draw_cube(cube, Vector2(12, 12), 22, col, Color(1, 0.95, 0.8, 0.95)))
		cube.position = a - Vector2(12, 12) + Vector2(randf_range(-6, 6), randf_range(-6, 6))
		cube.modulate.a = 0.0
		toast.add_child(cube)
		var dest := b - Vector2(12, 12) + Vector2(randf_range(-10, 10), randf_range(-8, 8))
		var tw := cube.create_tween()
		tw.tween_interval(i * 0.09)
		tw.tween_property(cube, "modulate:a", 1.0, 0.08)
		tw.tween_property(cube, "position", dest, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(cube, "modulate:a", 0.0, 0.25)
		tw.tween_callback(cube.queue_free)


func _banner(text: String, col: Color) -> void:
	var l := UI.title(text, 72, col)
	l.position = Vector2(BOARD_POS.x + 300, 420)
	toast.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(1.2)
	tw.tween_callback(l.queue_free)


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		if log_panel.visible:
			_toggle_log()
		elif pending.get("type", "") == "moves" and move_src >= 0:
			_undo_move()
			_update_controls()


func _process(_d: float) -> void:
	if pending.is_empty() and msg_lbl != null:
		var t := _idle_text()
		if t != msg_lbl.text and not engine.game_over:
			msg_lbl.text = t


# ------------------------------------------------------------------ fine partita e menu

func _on_game_end(results: Array) -> void:
	if online != null:
		online.finish()
		online_status("")
	refresh()
	_clear_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.01, 0.0, 0.88)
	shade.size = size
	modal.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#1e120af8"), UI.GOLD, 2, 12))
	box.custom_minimum_size = Vector2(860, 0)
	modal.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	box.add_child(vb)
	var w: Dictionary = results[0]
	vb.add_child(UI.title("%s è El Grande!" % w["name"], 56))
	vb.add_child(UI.label("Dopo la terza valutazione generale, chi ha più influenza sulla Spagna conquista il titolo.", 22, UI.MUTED))
	var place := 0
	var last := -999
	for i in results.size():
		var e: Dictionary = results[i]
		if e["score"] != last:
			place = i + 1
			last = e["score"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.add_child(UI.title("%d°" % place, 40, Color.WHITE))
		var cube := Control.new()
		cube.custom_minimum_size = Vector2(56, 56)
		var col := UI.pcol(e["color"])
		cube.draw.connect(func(): UI.draw_cube(cube, Vector2(28, 30), 40, col, Color(1, 0.9, 0.7)))
		row.add_child(cube)
		var nm := UI.label(e["name"] + (" (IA)" if engine.players[e["seat"]]["ai"] else ""), 30, UI.plight(e["color"]), UI.font_sc_b)
		nm.custom_minimum_size = Vector2(360, 0)
		row.add_child(nm)
		row.add_child(UI.label("%d punti" % e["score"], 32, UI.GOLD, UI.font_sc_b))
		vb.add_child(row)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 16)
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	if online == null:
		var again := UI.primary(UI.button("Rigioca", 220, 60, 26))
		again.pressed.connect(func():
			var cfg := config.duplicate(true)
			cfg.erase("seed")
			main.start_game(cfg))
		br.add_child(again)
	var see := UI.button("Guarda il tabellone", 300, 60, 24)
	see.pressed.connect(func():
		_clear_modal()
		_clear_buttons()
		msg_lbl.text = "Partita finita."
		_add_btn("Risultati", func(): _on_game_end(results), true)
		_add_btn("Menu", func(): main.show_menu()))
	br.add_child(see)
	var menu := UI.button("Menu", 180, 60, 26)
	menu.pressed.connect(func(): main.show_menu())
	br.add_child(menu)
	vb.add_child(br)
	_center_full.call_deferred(box)


func _center_full(box: Control) -> void:
	if not is_instance_valid(box):
		return
	box.reset_size()
	box.position = Vector2(960, 540) - box.size / 2.0


func _ask_quit() -> void:
	var layer := Control.new()
	layer.size = size
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.size = layer.size
	layer.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#1e120af8"), UI.GOLD, 2, 10))
	box.position = Vector2(660, 400)
	layer.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Tornare al menu?", 40))
	vb.add_child(UI.label("La partita in corso andrà persa." if online == null else "Potrai rientrare nella stanza con lo stesso codice.", 22))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	var y := UI.primary(UI.button("Sì, al menu", 240, 56, 24))
	y.pressed.connect(func(): main.show_menu())
	var nb := UI.button("Continua a giocare", 300, 56, 24)
	nb.pressed.connect(func(): layer.queue_free())
	hb.add_child(y)
	hb.add_child(nb)
	vb.add_child(hb)


func _show_rules_popup() -> void:
	var layer := Control.new()
	layer.size = size
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.size = layer.size
	layer.add_child(shade)
	var rv := preload("res://scripts/ui/rules_view.gd").new()
	rv.embedded = true
	rv.on_close = func(): layer.queue_free()
	layer.add_child(rv)


# =================================================================== online

func _build_online_label() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel_style(Color("#000000cc"), UI.GOLD, 2, 8))
	p.position = Vector2(30, 900)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	online_lbl = UI.label("", 22, Color.WHITE)
	p.add_child(online_lbl)
	add_child(p)
	p.visible = false
	online_lbl.set_meta("box", p)


func online_status(t: String) -> void:
	if online_lbl == null:
		return
	online_lbl.text = t
	(online_lbl.get_meta("box") as Control).visible = t != ""


func online_waiting(seat: int, is_slow: bool) -> void:
	if seat < 0:
		online_status("")
		return
	var t := "Online · stanza %s · tocca a %s" % [online.code, engine.pname(seat)]
	if is_slow:
		t += " (sta pensando da più di un minuto)"
	online_status(t)


func online_caught_up() -> void:
	online_status("")
	refresh()


## L'IA ha già giocato al posto di questo giocatore: si chiude il dialogo aperto.
func online_cancel_decision(t: String) -> void:
	pending = {}
	_clear_modal()
	_clear_buttons()
	refresh()
	online_status(t)
