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
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	vb.add_child(cols)
	var left := RichTextLabel.new()
	left.bbcode_enabled = true
	left.custom_minimum_size = Vector2(830, 880)
	cols.add_child(left)
	var right := RichTextLabel.new()
	right.bbcode_enabled = true
	right.custom_minimum_size = Vector2(820, 880)
	cols.add_child(right)
	var pages := [["Gioco base", _rules_text(), _cards_text()], ["Grandissimo", _grandissimo_text(), _grandissimo_cards()], ["Intrigo & il Re", _intrigo_text(), _intrigo_cards()], ["Le Colonie", _colonie_text(), _colonie_cards()]]
	var btns := []
	for i in pages.size():
		var b := UI.button(pages[i][0], 220, 44, 21)
		tabs.add_child(b)
		btns.append(b)
	var show := func(k: int):
		left.text = pages[k][1]
		right.text = pages[k][2]
		left.scroll_to_line(0)
		right.scroll_to_line(0)
		for i in btns.size():
			btns[i].add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if i == k else Color("#24170d"), UI.GOLD if i == k else Color("#4a3a2a"), 2, 4))
			btns[i].add_theme_color_override("font_color", UI.DARK if i == k else Color("#e8dcc0"))
	for i in btns.size():
		btns[i].pressed.connect(func(): show.call(i))
	show.call(0)


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


func _grandissimo_text() -> String:
	var s := _h("Grandissimo")
	s += "Si gioca come El Grande con queste aggiunte.\n\n"
	s += _h("Due pile in più")
	s += "Ogni round si scoprono 7 carte azione: le solite cinque, la prima della 6ª pila (19 carte nuove) e la carta della 7ª pila (la Regina o il Giullare), che come la carta del Re torna ogni round. Il numero di Caballeros da piazzare è quello disegnato sulla carta.\n\n"
	s += _h("Portogallo")
	s += "Una regione in più, confinante con Galizia, Vecchia e Nuova Castiglia e Siviglia. Si valuta 5 punti solo per il primo (un segnapunti mobile può coprirlo). Il Re e i Grandi possono andarci; non si sceglie col disco segreto.\n\n"
	s += _h("Simbolo nave")
	s += "Chi prende una carta col simbolo della nave può prendere un gettone nave (uno solo a testa; se sono finiti, lo prende a un altro giocatore). Con il gettone può piazzare i Caballeros della corte sulla nave, ovunque sia il Re; all'inizio del suo turno li sbarca in una regione costiera (anche il Portogallo, non quella del Re). Sulla nave non si fanno punti.\n\n"
	s += _h("Simbolo prigione")
	s += "Chi prende una carta col simbolo della prigione può mandare in prigione un Caballero qualsiasi da una regione (non quella del Re). Chi prende la carta del Re può liberare tutti i prigionieri in una sola regione, oppure lasciarli dentro.\n\n"
	s += _h("Regina e Giullare")
	s += "La carta della 7ª pila dà la Regina o il Giullare (se ne è rimasto uno solo a lato si prende quello; se li hanno altri due giocatori, si sceglie a chi toglierlo). Si usano a ogni proprio turno, anche quello in cui si prendono:\n"
	s += "• [b]Regina[/b]: un Caballero in più dalla corte a una regione vicina al Re, oppure dalle province alla corte.\n"
	s += "• [b]Giullare[/b]: regali a un altro giocatore un tuo Caballero delle province; lui lo mette dove vuole sulla mappa all'inizio del suo turno.\n\n"
	s += _h("Grande Inquisitore")
	s += "All'inizio due Caballeros neri vanno in una regione a caso: non sono di nessuno e non contano mai nelle valutazioni. Chi prende la carta Grande Inquisitore lo tiene fino alla prossima valutazione generale e, a ogni suo turno, può spingere i Caballeros neri in una regione confinante e rimandare alle province un Caballero avversario che si trova lì.\n\n"
	s += _h("Interpretazioni")
	s += "[color=#b9a988][i]Le note di Grandissimo lasciano alcuni punti aperti: qui il Giullare regala un Caballero proprio, la nave sbarca tutti i Caballeros nella stessa regione, la Regina, il Giullare e l'Inquisitore si usano alla fine del proprio turno, le carte tenute col Doppio turno si possono usare a fine turno nei round successivi.[/i][/color]\n"
	return s


func _grandissimo_cards() -> String:
	var s := _h("Le carte della 6ª e 7ª pila")
	for ci in D.pile_cards(6) + D.pile_cards(7):
		var cd: Dictionary = D.CARDS[ci]
		var sym: String = {"ship": " · nave", "jail": " · prigione"}.get(cd.get("sym", ""), "")
		s += "• [b]%s[/b] [color=#b9a988](%d Caballeros%s)[/color]: %s\n" % [cd["title"], D.card_n(ci), sym, cd["text"]]
	return s


func _intrigo_text() -> String:
	var s := _h("Intrigo & il Re")
	s += "Le carte potere e le carte azione del gioco base sono sostituite da 31 carte per giocatore, uguali per tutti. Prima della partita ognuno sceglie le 13 con cui giocherà (le altre restano fuori). Poi, col disco segreto, ognuno mette un Caballero della corte in una regione (se sceglie quella del Re resta a corte).\n\n"
	s += _h("Il round")
	s += "• A turno, a partire da chi ha giocato la carta più bassa nel round prima, ognuno gioca scoperta una carta: non si può giocare un valore già giocato.\n"
	s += "• Il [b]Jolly[/b] si gioca come una carta qualsiasi; quando tutti hanno giocato, chi l'ha usato sceglie la carta vera dalla mano.\n"
	s += "• La carta più alta prende la [b]carta del Re[/b] e la carta Caballero più alta, la seconda la successiva e così via; la più bassa prende anche la [b]carta dell'Intrigo[/b].\n"
	s += "• Si gioca dalla carta più alta. Nel proprio turno si portano a corte i Caballeros delle province disegnati sulla carta giocata; poi, nell'ordine che si vuole, si piazzano tanti Caballeros quanti ne indica la carta Caballero e si esegue l'azione speciale.\n\n"
	s += _h("Azioni speciali")
	s += "Chi ha la carta del Re esegue l'azione del Re (può mettere il Re in qualunque regione) al posto della propria; chi ha l'Intrigo esegue l'Intrigo: da una regione sposta 1 Caballero di un avversario, oppure fino a tutti i propri. In 2 o 3 giocatori possono scegliere invece l'azione della propria carta.\n"
	s += "Le altre azioni sono obbligatorie, tranne quelle che dicono «puoi».\n\n"
	s += _h("Carte Caballero")
	s += "2 giocatori: 4 e 2 · 3 giocatori: 5, 3, 1 · 4 giocatori: 5, 4, 2, 1 · 5 giocatori: 5, 4, 3, 2, 1.\n\n"
	s += _h("Interpretazioni")
	s += "[color=#b9a988][i]Il ponte unisce due regioni confinanti; c'è un solo ponte in gioco e il Caballero di guardia torna a corte quando viene tolto. Il Caballero della Riserva e le carte «Prendi 6!» si tolgono con la carta 125. La Protezione reale dura fino alla fine del round.[/i][/color]\n"
	return s


func _colonie_text() -> String:
	var s := _h("Il Grande Inquisitore e le Colonie")
	s += "Ognuno ha 36 Caballeros: 2 nella regione del Grande, 9 a corte, il resto nelle province. Prima del primo round, col disco segreto, ognuno porta 2 Caballeros della corte in una regione (se sceglie quella del Re restano a corte). Due regioni pescate a caso ricevono 2 Caballeros neri ciascuna, una terza la tavola limite. In America c'è 1 disco d'oro, nel Mediterraneo 2 di merci.\n\n"
	s += _h("Le nuove regioni")
	s += "Si valutano dopo Valencia, in quest'ordine: [b]Francia[/b], [b]nave[/b], [b]America[/b], [b]Mediterraneo[/b]. Il disco segreto non le può scegliere; il Re può andare solo in Francia.\n"
	s += "• [b]Francia[/b] (3 / 1 / –): al massimo 3 Caballeros. Il primo arrivato è l'Ambasciatore (+2), il secondo l'Inviato (+1). Ci si piazza quando il Re è in Aragona o Catalogna.\n"
	s += "• [b]Nave[/b]: prende 3 punti solo il Capitano (il primo Caballero salito). Si sale dalla corte quando il Re è in una regione costiera (Francia, Catalogna, Valencia, Granada, Siviglia, Galizia, Paesi Baschi). All'inizio del proprio turno si sbarca in America, Francia, Mediterraneo o su una costa spagnola, e si possono imbarcare i Caballeros che erano già in America o nel Mediterraneo.\n"
	s += "• [b]America[/b] (4 / – / –): il Viceré (il primo arrivato) prende 5 punti ma non conta per la maggioranza.\n"
	s += "• [b]Mediterraneo[/b] (4 / 2 / 1).\n\n"
	s += _h("Oro e merci")
	s += "Le carte della 7ª pila mettono dischi d'oro in America e di merci nel Mediterraneo. Un Caballero libero che si trova lì prende un disco; quando arriva in Spagna il disco vale subito 6 punti (oro) o 4 (merci). Va perso se il Caballero torna a corte, nelle province o nel Castillo.\n\n"
	s += _h("Il Grande Inquisitore")
	s += "La sua carta (6ª pila) è sempre disponibile come quella del Re. Chi la prende tiene l'Inquisitore finché un altro non glielo toglie: i Caballeros neri contano come suoi e a ogni turno porta un Caballero in più dalle province alla corte o dalla corte vicino al Re. Se l'Inquisitore non è di nessuno, i Caballeros neri sono un giocatore invisibile.\n\n"
	s += _h("Tavola limite")
	s += "Nella regione con la tavola contano al massimo 6 Caballeros (con 2 o 3 giocatori) o 10 (con 4 o 5): chi c'è già resta sulla tavola, i posti liberi vanno a chi arriva.\n\n"
	s += _h("Il Re e le Colonie")
	s += "Con le carte di Intrigo & il Re: a ogni round sono disponibili la carta dell'Inquisitore e una della 7ª pila; al proprio turno si può prendere una delle due al posto della propria azione, e allora è quella carta a dire quanti Caballeros si piazzano. «Togli carta» vale come un veto.\n\n"
	s += _h("Interpretazioni")
	s += "[color=#b9a988][i]I posti di Ambasciatore, Capitano e Viceré si occupano da soli con il primo Caballero che arriva (mai con uno che porta un disco). Chi parte da una regione porta per primi i Caballeros con i dischi se va verso la Spagna o la nave, per ultimi se va a corte o nel Castillo. «Togli carta» si usa prima che un altro scelga la sua carta azione.[/i][/color]\n"
	return s


func _colonie_cards() -> String:
	var s := _h("Le carte delle Colonie")
	for ci in range(D.COL_GI, D.CARDS.size()):
		var cd: Dictionary = D.CARDS[ci]
		var disc := []
		if cd.get("gold", 0) > 0:
			disc.append("%d oro" % cd["gold"])
		if cd.get("wares", 0) > 0:
			disc.append("%d merci" % cd["wares"])
		s += "• [b]%s[/b] [color=#b9a988](%d Caballeros%s)[/color]: %s\n" % [cd["title"], cd["n"], (", " + " e ".join(disc)) if not disc.is_empty() else "", cd["text"]]
	return s


func _intrigo_cards() -> String:
	var s := _h("Le 31 carte")
	for ci in D.ik_cards():
		var cd: Dictionary = D.CARDS[ci]
		var v: String = "Jolly" if cd["val"] == 0 else str(cd["val"])
		s += "• [b]%s[/b] [color=#b9a988](%d dalle province)[/color] %s: %s\n" % [v, cd["pc"], cd["title"], cd["text"]]
	return s
