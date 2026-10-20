extends Control
## Menu principale: il tabellone sullo sfondo, il titolo gotico, i cinque colori (Umano / IA / Assente) e le opzioni.

const MODES := ["Umano", "IA", "Assente"]
const D = preload("res://scripts/data/eg_data.gd")

var main
var seat_mode := [0, 1, 1, 1, 2]      # 0 umano, 1 IA, 2 assente
var tiles := {}
var level := 1
var speed := 1
var short := false
var cas_hidden := false
var variant := "base"
const VARIANTS := [
	["base", "Gioco base", "Le regole della scatola di El Grande."],
	["grandissimo", "Grandissimo", "Portogallo, nave, prigione, Regina e Giullare, Grande Inquisitore e 19 nuove carte azione."],
	["intrigo", "Intrigo & il Re", "Ognuno sceglie 13 delle sue 31 carte azione: la più alta prende la carta del Re, la più bassa l'Intrigo."],
	["colonie", "Inquisitore e Colonie", "Francia, nave, America e Mediterraneo con oro e merci, tavola limite, Grande Inquisitore e 7ª pila."],
	["re_colonie", "Il Re e le Colonie", "Le carte di Intrigo & il Re insieme alle Colonie, al Grande Inquisitore e alla 7ª pila."],
]
var msg: Label


func _ready() -> void:
	size = Vector2(1920, 1080)
	if main.menu_state.has("seat_mode"):
		seat_mode = main.menu_state["seat_mode"].duplicate()
		level = main.menu_state["level"]
		speed = main.menu_state["speed"]
		short = main.menu_state.get("short", false)
		cas_hidden = main.menu_state.get("cas_hidden", false)
		variant = main.menu_state.get("variant", "base")
	var bg := TextureRect.new()
	bg.texture = UI.tex("res://assets/board.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.size = Vector2(1920, 1080)
	bg.modulate = Color(0.55, 0.45, 0.36)
	add_child(bg)
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.08, 0.04, 0.02, 0.35))
	g.set_color(1, Color(0.06, 0.03, 0.01, 0.94))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 0.75)
	shade.texture = grad
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.size = Vector2(1920, 1080)
	add_child(shade)

	var logo := UI.title("El Grande", 150, UI.GOLD)
	logo.add_theme_constant_override("outline_size", 14)
	logo.add_theme_color_override("font_outline_color", Color(0.12, 0.03, 0.0, 0.95))
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	logo.add_theme_constant_override("shadow_offset_x", 5)
	logo.add_theme_constant_override("shadow_offset_y", 6)
	logo.position = Vector2(0, 10)
	logo.size = Vector2(1920, 180)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(logo)
	var tag := UI.label("Spagna, XV secolo · un sottile gioco di potere per 2–5 Grandi", 28, Color("#f1dcaa"), UI.font_italic)
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tag.add_theme_constant_override("outline_size", 6)
	tag.position = Vector2(0, 186)
	tag.size = Vector2(1920, 40)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tag)

	var head := UI.heading("Nuova partita", 36)
	head.position = Vector2(62, 262)
	add_child(head)
	var sub := UI.label("Scegli chi guida ogni colore (da 2 a 5 Grandi). Regione di partenza e posizione del Re sono sorteggiate.", 24, Color("#e2d3b2"))
	sub.position = Vector2(64, 310)
	add_child(sub)

	for c in D.COLORS:
		var i: int = c["id"]
		_make_tile(c, Vector2(62 + i * 364, 356))

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#140b06dd"), UI.GOLD_D, 1, 8))
	box.position = Vector2(62, 650)
	box.custom_minimum_size = Vector2(1180, 0)
	add_child(box)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 10)
	box.add_child(ov)
	ov.add_child(_segmented("Livello IA", ["Facile", "Normale", "Difficile"], level, func(k): level = k))
	ov.add_child(_segmented("Velocità IA", ["Lenta", "Normale", "Veloce", "Istantanea"], speed, func(k): speed = k))
	ov.add_child(_segmented("Durata", ["9 round (2 ore)", "6 round (1 ora)"], 1 if short else 0, func(k): short = k == 1))
	ov.add_child(_segmented("Castillo", ["Scoperto", "Coperto (si ricorda)"], 1 if cas_hidden else 0, func(k): cas_hidden = k == 1))

	_variant_box()

	msg = UI.label("", 26, UI.RED_L, UI.font_sc_b)
	msg.position = Vector2(62, 1000)
	add_child(msg)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 18)
	btns.position = Vector2(62, 912)
	add_child(btns)
	var b_start := _big_button("Inizia partita", 420, true)
	b_start.pressed.connect(_on_start)
	btns.add_child(b_start)
	var b_rules := _big_button("Regole", 240)
	b_rules.pressed.connect(func():
		_store()
		main.show_rules())
	btns.add_child(b_rules)
	if not OS.has_feature("web"):
		var b_quit := _big_button("Esci", 200)
		b_quit.pressed.connect(func(): get_tree().quit())
		btns.add_child(b_quit)

	var b_online := _big_button("Gioca online", 420)
	b_online.position = Vector2(1438, 912)
	b_online.pressed.connect(_online_panel)
	add_child(b_online)

	if not main.lobby.is_empty():
		_online_panel.call_deferred()

	var credits := UI.label("Adattamento digitale non ufficiale per uso personale · El Grande di Wolfgang Kramer e Richard Ulrich · © Hans im Glück / Rio Grande Games · F11 schermo intero", 18, Color("#9a8a6a"))
	credits.position = Vector2(62, 1044)
	add_child(credits)
	_refresh_tiles()


func _store() -> void:
	main.menu_state = {"seat_mode": seat_mode.duplicate(), "level": level, "speed": speed, "short": short, "cas_hidden": cas_hidden, "variant": variant}


## Riquadro delle espansioni (una sola alla volta).
func _variant_box() -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#140b06dd"), UI.GOLD_D, 1, 8))
	box.position = Vector2(1262, 632)
	box.custom_minimum_size = Vector2(596, 0)
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	box.add_child(vb)
	vb.add_child(UI.label("Espansione", 28, Color.WHITE, UI.font_sc_b))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	var btns := []
	for v in VARIANTS:
		var b := Button.new()
		b.text = v[1]
		b.custom_minimum_size = Vector2(282, 44)
		b.tooltip_text = v[2]
		b.add_theme_font_size_override("font_size", 20)
		grid.add_child(b)
		btns.append(b)
	var paint := func():
		for i in VARIANTS.size():
			var on: bool = VARIANTS[i][0] == variant
			btns[i].add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if on else Color("#24170d"), UI.GOLD if on else Color("#4a3a2a"), 2, 4))
			btns[i].add_theme_color_override("font_color", UI.DARK if on else Color("#e8dcc0"))
			btns[i].add_theme_color_override("font_hover_color", UI.DARK if on else UI.GOLD)
	for i in VARIANTS.size():
		var key: String = VARIANTS[i][0]
		btns[i].pressed.connect(func():
			variant = key
			_store()
			paint.call())
	paint.call()


func _make_tile(c: Dictionary, pos: Vector2) -> void:
	var i: int = c["id"]
	var root := Control.new()
	root.position = pos
	root.size = Vector2(340, 270)
	add_child(root)
	var frame := Panel.new()
	frame.size = root.size
	root.add_child(frame)
	var cube := Control.new()
	cube.position = Vector2(110, 10)
	cube.size = Vector2(120, 120)
	var col: Color = c["col"]
	cube.draw.connect(func():
		UI.draw_cube(cube, Vector2(60, 66), 78, col, Color(1, 0.9, 0.65, 0.95)))
	cube.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(cube)
	var nm := UI.title(c["name"], 44, c["light"])
	nm.position = Vector2(0, 132)
	nm.size = Vector2(340, 56)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(nm)
	var bar := HBoxContainer.new()
	bar.position = Vector2(8, 202)
	bar.size = Vector2(324, 56)
	bar.add_theme_constant_override("separation", 4)
	root.add_child(bar)
	var buttons := []
	for k in range(3):
		var b := Button.new()
		b.text = MODES[k]
		b.custom_minimum_size = Vector2(105, 56)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func():
			seat_mode[i] = k
			msg.text = ""
			_refresh_tiles())
		bar.add_child(b)
		buttons.append(b)
	tiles[i] = {"frame": frame, "cube": cube, "buttons": buttons, "color": c["light"]}
	cube.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			seat_mode[i] = (seat_mode[i] + 1) % 3
			_refresh_tiles())


func _refresh_tiles() -> void:
	for i in range(5):
		var t: Dictionary = tiles[i]
		var m: int = seat_mode[i]
		var active := m != 2
		t["cube"].modulate = Color.WHITE if active else Color(0.3, 0.3, 0.3)
		t["frame"].add_theme_stylebox_override("panel", UI.panel_style(Color("#140b06e6"), t["color"] if active else Color("#3a3028"), 3 if active else 1, 8))
		for k in range(3):
			var b: Button = t["buttons"][k]
			var sel := k == m
			b.add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if sel else Color("#24170d"), UI.GOLD if sel else Color("#4a3a2a"), 2, 4))
			b.add_theme_stylebox_override("hover", UI.panel_style(UI.GOLD if sel else Color("#3a2614"), UI.GOLD, 2, 4))
			b.add_theme_color_override("font_color", UI.DARK if sel else Color("#e8dcc0"))
			b.add_theme_color_override("font_hover_color", UI.DARK if sel else UI.GOLD)


func _segmented(label_text: String, items: Array, cur: int, cb: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var l := UI.label(label_text, 28, Color.WHITE, UI.font_sc_b)
	l.custom_minimum_size = Vector2(200, 0)
	hb.add_child(l)
	var btns := []
	for k in range(items.size()):
		var b := Button.new()
		b.text = items[k]
		b.custom_minimum_size = Vector2(240 if items.size() <= 3 else 200, 48)
		b.add_theme_font_size_override("font_size", 22)
		hb.add_child(b)
		btns.append(b)
	var paint := func(sel: int):
		for k in range(btns.size()):
			var on: bool = k == sel
			btns[k].add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if on else Color("#24170d"), UI.GOLD if on else Color("#4a3a2a"), 2, 4))
			btns[k].add_theme_color_override("font_color", UI.DARK if on else Color("#e8dcc0"))
			btns[k].add_theme_color_override("font_hover_color", UI.DARK if on else UI.GOLD)
	for k in range(btns.size()):
		btns[k].pressed.connect(func():
			cb.call(k)
			paint.call(k))
	paint.call(cur)
	return hb


func _big_button(text: String, w: float, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 82)
	b.add_theme_font_override("font", UI.font_title)
	b.add_theme_font_size_override("font_size", 44)
	if primary:
		UI.primary(b)
	return b


## Configurazione scelta nel menu (anche quella che, online, viaggia agli altri).
func _config() -> Dictionary:
	var seats := []
	for c in D.COLORS:
		var m: int = seat_mode[c["id"]]
		if m == 2:
			continue
		seats.append({"color": c["id"], "ai": m == 1, "name": c["name"], "level": level})
	var speeds := [1.1, 0.6, 0.2, 0.0]
	return {"seats": seats, "ai_level": level, "ai_delay": speeds[speed], "short": short, "castillo_hidden": cas_hidden, "variant": variant}


func _on_start() -> void:
	var cfg := _config()
	if cfg["seats"].size() < 2:
		msg.text = "Servono almeno 2 Grandi in gioco."
		return
	_store()
	main.start_game(cfg)


# =================================================================== online

var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button


func _online_panel() -> void:
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.size = Vector2(1920, 1080)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.75)
	shade.size = on_panel.size
	on_panel.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#1e120af4"), UI.GOLD, 2, 8))
	box.position = Vector2(560, 130)
	box.custom_minimum_size = Vector2(800, 0)
	on_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Gioca online", 54))
	var info := UI.label("Chi crea la stanza sceglie prima nel menu i colori e le opzioni: i colori su UMANO diventano i posti per gli amici (il primo è il suo). Gli amici entrano con il codice. I posti rimasti liberi li gioca l'IA.", 22, Color("#cccccc"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(760, 0)
	vb.add_child(info)
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	var b_create := Button.new()
	b_create.text = "Crea una stanza"
	b_create.custom_minimum_size = Vector2(0, 60)
	b_create.add_theme_font_size_override("font_size", 28)
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := Button.new()
	b_join.text = "Entra"
	b_join.custom_minimum_size = Vector2(200, 60)
	b_join.add_theme_font_size_override("font_size", 28)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = UI.label("", 24, Color.WHITE)
	on_lbl.custom_minimum_size = Vector2(760, 120)
	on_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = _big_button("Inizia online", 420, true)
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := _big_button("Indietro", 300)
	b_close.pressed.connect(func():
		on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s…" % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 60)
	le.add_theme_font_size_override("font_size", 28)
	return le


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seat_list() -> Array:
	return _config()["seats"]


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var list := _seat_list()
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var who := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		var cname: String = list[int(idx)]["name"] if int(idx) < list.size() else "posto %d" % (int(idx) + 1)
		parts.append("%s: %s" % [cname, who])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var seats := []
	var list := _seat_list()
	for i in list.size():
		if not list[i]["ai"]:
			seats.append(i)
	if list.size() < 2 or seats.size() < 2:
		_say("Metti su Umano almeno due colori: il primo è il tuo, gli altri sono i posti per gli amici.")
		return
	_store()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": seats[0]}
	net.remember_room(code, seats[0])
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice ai tuoi amici.\nPosti: %s.\nQuando ci siete tutti premi Inizia online: i posti liberi li gioca l'IA." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] (posto %d).\nPosti: %s.\nAspetta che chi l'ha creata avvii la partita." % [code, int(main.lobby["seat"]) + 1, _seats_text(room)])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: colori, opzioni e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	var my_seat := int(main.lobby["seat"])
	if my_seat >= cfg["seats"].size() or not seats_db.has(str(my_seat)) or cfg["seats"][my_seat]["ai"]:
		_say("Hai cambiato i colori dopo aver creato la stanza: creane una nuova.")
		return
	for i in cfg["seats"].size():
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary and not cfg["seats"][i]["ai"]:
			cfg["seats"][i]["name"] = "%s" % str(seats_db[k].get("name", cfg["seats"][i]["name"]))
		else:
			cfg["seats"][i]["ai"] = true
	cfg["seed"] = 1 + randi() % 2000000000
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


## Avvio (o rientro) della partita online.
func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)
