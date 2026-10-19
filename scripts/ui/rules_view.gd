extends Control
## Regole in breve e carte azione. Si apre dal menu o durante la partita.

const D = preload("res://scripts/data/eg_data.gd")

var main
var embedded := false
var on_close: Callable


func _ready() -> void:
	size = Vector2(1920, 1080)
	if not embedded:
		var bg := TextureRect.new()
		bg.texture = UI.tex("res://assets/board.jpg")
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.size = size
		bg.modulate = Color(0.22, 0.17, 0.13)
		add_child(bg)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#1e120af6"), UI.GOLD, 2, 10))
	box.position = Vector2(100, 30)
	box.custom_minimum_size = Vector2(1720, 1020)
	box.size = Vector2(1720, 1020)
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	box.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := UI.title("Le regole di El Grande", 46)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var close := UI.button("Chiudi" if embedded else "Indietro", 180, 52, 24)
	close.pressed.connect(func():
		if embedded:
			on_close.call()
		else:
			main.show_menu())
	hb.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	vb.add_child(cols)
	var left := RichTextLabel.new()
	left.bbcode_enabled = true
	left.custom_minimum_size = Vector2(830, 930)
	left.text = _rules_text()
	cols.add_child(left)
	var right := RichTextLabel.new()
	right.bbcode_enabled = true
	right.custom_minimum_size = Vector2(820, 930)
	right.text = _cards_text()
	cols.add_child(right)


func _h(t: String) -> String:
	return "[font_size=27][color=#d9b45a][b]%s[/b][/color][/font_size]\n" % t


func _rules_text() -> String:
	var s := ""
	s += _h("Scopo")
	s += "Spagna, XV secolo. Ognuno è il Grande di una regione e guida 30 Caballeros: vince chi, dopo la terza valutazione generale, ha più punti sulla scala del successo. I punti si fanno avendo la maggioranza dei Caballeros nelle regioni quando vengono valutate.\n\n"
	s += _h("Preparazione")
	s += "La prima carta regione indica dove sta il Re; poi ognuno pesca la regione di provenienza del suo Grande e vi mette 2 Caballeros. Ognuno ha 7 Caballeros a corte e 21 nelle province.\n\n"
	s += _h("Il round")
	s += "• Si scoprono 5 carte azione: una per ciascuna delle pile 1–4 più la carta del Re, sempre presente.\n"
	s += "• A turno (inizia chi ha giocato per ultimo nel round prima) ognuno gioca una carta potere, da 1 a 13, diversa da quelle già giocate. Le carte giocate non tornano in mano.\n"
	s += "• Si gioca dalla carta potere più alta alla più bassa. Nel proprio turno:\n"
	s += "   1. si portano dalle province alla corte tanti Caballeros quanti ne mostra la carta potere (se le province sono vuote si possono riprendere dal tabellone);\n"
	s += "   2. si sceglie una carta azione;\n"
	s += "   3. si piazzano dalla corte fino a tanti Caballeros quanti indica la carta azione (il numero della pila), nelle regioni confinanti con quella del Re e/o nel Castillo;\n"
	s += "   4. si esegue (o no) l'azione speciale. Piazzamento e azione si possono fare in qualunque ordine.\n\n"
	s += _h("Il Re")
	s += "Nella regione del Re non si può aggiungere né togliere niente: né Caballeros, né Grandi, né segna-punti mobili. Chi vi ha la maggioranza assoluta prende 2 punti in più quando la regione è valutata.\n\n"
	s += _h("Il Castillo")
	s += "Ci si possono mettere Caballeros ogni volta che se ne piazzano o se ne spostano, ovunque sia il Re. Nella valutazione generale si valuta (5/3/1), poi ognuno sceglie in segreto col disco la regione dove vanno tutti i suoi Caballeros del Castillo (non la regione del Re).\n\n"
	s += _h("Valutazione")
	s += "Dopo i round 3, 6 e 9 si valutano il Castillo e poi tutte le regioni, nell'ordine del tabellone. Il primo prende il valore più alto, il secondo il medio, il terzo il più basso. A parità i giocatori scalano di una posizione (prendono i punti della posizione successiva). In 3 giocatori contano solo i primi due valori, in 2 solo il primo.\n"
	s += "Bonus di 2 punti a chi ha la maggioranza assoluta nella regione del suo Grande, e 2 a chi l'ha nella regione del Re.\n\n"
	s += _h("Partita corta")
	s += "Si giocano 6 round (si saltano l'1, il 4 e il 7): le valutazioni restano dopo i round 3, 6 e 9.\n\n"
	s += _h("Comandi")
	s += "Clic sulle regioni evidenziate per scegliere o piazzare; tasto destro per togliere. Passa il mouse su una regione per vedere i Caballeros e i punti che darebbe ora. F11 schermo intero.\n"
	return s


func _cards_text() -> String:
	var s := _h("Le carte azione")
	var seen := {}
	for p in range(1, 6):
		var names := {1: "Pila 1 · intrighi (1 Caballero)", 2: "Pila 2 (2 Caballeros)", 3: "Pila 3 · valutazioni (3 Caballeros)", 4: "Pila 4 (4 Caballeros)", 5: "Pila 5 · la carta del Re (5 Caballeros)"}
		s += "[color=#e0a070][b]%s[/b][/color]\n" % names[p]
		for ci in D.pile_cards(p):
			var cd: Dictionary = D.CARDS[ci]
			var k: String = cd["key"] + cd["text"]
			if seen.has(k):
				seen[k] += 1
				continue
			seen[k] = 1
		for ci in D.pile_cards(p):
			var cd: Dictionary = D.CARDS[ci]
			var k: String = cd["key"] + cd["text"]
			if not seen.has(k):
				continue
			var q: int = seen[k]
			seen.erase(k)
			s += "• [b]%s[/b]%s: %s\n" % [cd["title"], " (×%d)" % q if q > 1 else "", cd["text"]]
		s += "\n"
	s += "[color=#b9a988][i]Gli intrighi muovono Caballeros già sul tabellone (mai dentro o fuori dalla regione del Re; dal Castillo non si esce fino alla valutazione generale). Il Veto! si tiene davanti a sé e annulla un'azione speciale altrui in questo round o nel successivo.[/i][/color]\n"
	return s
