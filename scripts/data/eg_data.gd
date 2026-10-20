class_name EGData
extends RefCounted
## Dati fissi di El Grande: regioni, confini, valori, carte potere e carte azione (gioco base ed espansioni).
## Le coordinate sono in "unità tabellone" (immagine del tabellone ridotta a 1400 x 1025).

const BOARD_SIZE := Vector2(1400, 1025)
const CASTILLO := 9
## Regioni aggiunte dalle espansioni (indici fissi, le righe di cab esistono sempre).
const PORTUGAL := 10
const FRANCE := 11
const SHIP_C := 12          # nave delle Colonie (si valuta)
const AMERICA := 13
const MEDIT := 14
const SHIP_G := 15          # nave di Grandissimo (solo transito, non si valuta)
const JAIL := 16
const NREG := 17
## Regioni costiere (Grandissimo / Colonie).
const COASTAL := [0, 1, 3, 6, 7, 8, 10, 11]
const INLAND := [2, 4, 5]

## Regioni nell'ordine del tabellone (è anche l'ordine della valutazione generale).
## rect: zona dove si dispongono i Caballeros; box: casella del segna-punti stampato.
const REGIONS := [
	{"id": 0, "name": "Galizia", "vals": [4, 2, 0], "rect": Rect2(364, 123, 159, 141), "box": Vector2(300, 200), "label": Vector2(305, 243)},
	{"id": 1, "name": "Paesi Baschi", "vals": [5, 3, 1], "rect": Rect2(666, 89, 159, 140), "box": Vector2(600, 170), "label": Vector2(632, 212)},
	{"id": 2, "name": "Aragona", "vals": [5, 4, 1], "rect": Rect2(791, 267, 160, 139), "box": Vector2(967, 187), "label": Vector2(960, 227)},
	{"id": 3, "name": "Catalogna", "vals": [4, 2, 1], "rect": Rect2(1103, 280, 161, 141), "box": Vector2(1217, 210), "label": Vector2(1215, 250)},
	{"id": 4, "name": "Vecchia Castiglia", "vals": [6, 4, 2], "rect": Rect2(467, 372, 159, 138), "box": Vector2(577, 303), "label": Vector2(582, 350)},
	{"id": 5, "name": "Nuova Castiglia", "vals": [7, 4, 2], "rect": Rect2(596, 545, 160, 139), "box": Vector2(797, 487), "label": Vector2(796, 528)},
	{"id": 6, "name": "Siviglia", "vals": [4, 3, 1], "rect": Rect2(371, 766, 162, 137), "box": Vector2(513, 700), "label": Vector2(506, 741)},
	{"id": 7, "name": "Granada", "vals": [6, 3, 1], "rect": Rect2(696, 777, 160, 138), "box": Vector2(777, 707), "label": Vector2(776, 754)},
	{"id": 8, "name": "Valencia", "vals": [5, 3, 1], "rect": Rect2(948, 554, 162, 139), "box": Vector2(990, 447), "label": Vector2(980, 489)},
	{"id": 9, "name": "Castillo", "vals": [5, 3, 1], "rect": Rect2(1118, 640, 124, 128), "box": Vector2(1220, 590), "label": Vector2(1180, 790)},
	{"id": 10, "name": "Portogallo", "vals": [5, 0, 0], "rect": Rect2(246, 698, 124, 100), "box": Vector2(318, 720), "label": Vector2(330, 765)},
	{"id": 11, "name": "Francia", "vals": [3, 0, 0], "rect": Rect2(0, 0, 10, 10), "box": Vector2.ZERO, "label": Vector2.ZERO},
	{"id": 12, "name": "Nave", "vals": [3, 0, 0], "rect": Rect2(0, 0, 10, 10), "box": Vector2.ZERO, "label": Vector2.ZERO},
	{"id": 13, "name": "America", "vals": [4, 2, 0], "rect": Rect2(0, 0, 10, 10), "box": Vector2.ZERO, "label": Vector2.ZERO},
	{"id": 14, "name": "Mediterraneo", "vals": [4, 2, 1], "rect": Rect2(0, 0, 10, 10), "box": Vector2.ZERO, "label": Vector2.ZERO},
	{"id": 15, "name": "Nave", "vals": [0, 0, 0], "rect": Rect2(78, 92, 130, 80), "box": Vector2.ZERO, "label": Vector2(140, 180)},
	{"id": 16, "name": "Prigione", "vals": [0, 0, 0], "rect": Rect2(130, 730, 92, 92), "box": Vector2.ZERO, "label": Vector2(176, 836)},
]

const ADJ := [
	[1, 4],
	[0, 4, 2],
	[1, 4, 5, 3, 8],
	[2, 8],
	[0, 1, 2, 5],
	[4, 2, 8, 7, 6],
	[5, 7],
	[6, 5, 8],
	[3, 2, 5, 7],
	[],
	[0, 4, 5, 6],
	[2, 3],
]

## Punti per il clic sulla mappa: vince la regione del punto più vicino.
const ANCHORS := [
	[Vector2(300, 250), Vector2(400, 200), Vector2(330, 180), Vector2(420, 270), Vector2(460, 230), Vector2(270, 300)],
	[Vector2(560, 200), Vector2(650, 170), Vector2(750, 190), Vector2(820, 150), Vector2(700, 240), Vector2(620, 240), Vector2(790, 240)],
	[Vector2(870, 200), Vector2(950, 250), Vector2(870, 330), Vector2(930, 330), Vector2(830, 280), Vector2(1000, 210), Vector2(880, 400), Vector2(960, 380)],
	[Vector2(1050, 250), Vector2(1150, 250), Vector2(1200, 300), Vector2(1080, 330), Vector2(1250, 240), Vector2(1010, 330), Vector2(1150, 330)],
	[Vector2(520, 350), Vector2(600, 360), Vector2(560, 440), Vector2(650, 420), Vector2(720, 380), Vector2(500, 450), Vector2(690, 320)],
	[Vector2(560, 560), Vector2(650, 570), Vector2(760, 560), Vector2(820, 520), Vector2(720, 620), Vector2(600, 620), Vector2(500, 520), Vector2(830, 600)],
	[Vector2(450, 700), Vector2(520, 720), Vector2(560, 800), Vector2(480, 760), Vector2(600, 700), Vector2(420, 660), Vector2(520, 880)],
	[Vector2(700, 700), Vector2(780, 760), Vector2(850, 800), Vector2(700, 820), Vector2(650, 780), Vector2(900, 840), Vector2(760, 880)],
	[Vector2(900, 500), Vector2(960, 500), Vector2(1000, 560), Vector2(900, 620), Vector2(970, 650), Vector2(1040, 450), Vector2(960, 720)],
	[],
	[Vector2(300, 760), Vector2(360, 775), Vector2(330, 720), Vector2(280, 735), Vector2(390, 740)],
]
const SHIP_G_POS := Vector2(143, 132)
const JAIL_POS := Vector2(176, 776)
const CASTILLO_POS := Vector2(1180, 705)

## Scala del successo: [punteggio, x, y] lungo il bordo (si interpola fra i punti).
const TRACK := [[0, 47, 815], [18, 47, 59], [19, 88, 47], [50, 1334, 47], [51, 1352, 104], [70, 1352, 885], [72, 1350, 965], [73, 1307, 967], [95, 410, 967], [99, 247, 967]]
## Righe dei round sul tabellone (cubo nero segna-turno).
const ROUND_Y := [0, 258, 293, 330, 405, 442, 478, 550, 590, 625]
const ROUND_X := 125.0
const EVAL_ROWS := [365, 515, 660]

## Colori dei giocatori.
const COLORS := [
	{"id": 0, "key": "red", "name": "Rosso", "col": Color("#c8321e"), "light": Color("#ff6a4d")},
	{"id": 1, "key": "green", "name": "Verde", "col": Color("#2f8a32"), "light": Color("#72d36a")},
	{"id": 2, "key": "brown", "name": "Marrone", "col": Color("#5a3a22"), "light": Color("#c08b5c")},
	{"id": 3, "key": "yellow", "name": "Giallo", "col": Color("#e2b51e"), "light": Color("#ffe066")},
	{"id": 4, "key": "blue", "name": "Blu", "col": Color("#2a55b8"), "light": Color("#7aa2ff")},
]

## Caballeros raffigurati sulle carte potere (valore 1..13).
const POWER_CAB := [0, 6, 5, 5, 4, 4, 3, 3, 2, 2, 1, 1, 0, 0]

## Segna-punti mobili.
const MOBILE := [[8, 4, 0], [4, 0, 0]]
const MOBILE_NAME := ["8 / 4 / 0", "4 / 0 / 0"]

## Carte azione. pile = numero di Caballeros che si possono piazzare dalla corte.
const CARDS := [
	# ---- pila 1: intrighi
	{"pile": 1, "key": "own4", "art": "p1_0", "title": "Intrigo", "text": "Muovi fino a 4 tuoi Caballeros sul tabellone."},
	{"pile": 1, "key": "court2_or_all", "art": "p1_1", "title": "Intrigo", "text": "Muovi 2 Caballeros dalla tua corte in qualunque regione, oppure muovi tutti i tuoi Caballeros da una regione."},
	{"pile": 1, "key": "any3", "art": "p1_2", "title": "Intrigo", "text": "Muovi fino a 3 Caballeros qualsiasi (tuoi o avversari) sul tabellone."},
	{"pile": 1, "key": "five1", "art": "p1_3", "title": "Intrigo", "text": "Muovi fino a 5 Caballeros qualsiasi da una sola regione."},
	{"pile": 1, "key": "own2foe2", "art": "p1_4", "title": "Intrigo", "text": "Muovi fino a 2 tuoi Caballeros e fino a 2 avversari sul tabellone."},
	{"pile": 1, "key": "any4", "art": "p1_5", "title": "Intrigo", "text": "Muovi fino a 4 Caballeros qualsiasi (tuoi o avversari) sul tabellone."},
	{"pile": 1, "key": "allown", "art": "p1_6", "title": "Intrigo", "text": "Muovi tutti i tuoi Caballeros da una regione e ridistribuiscili dove vuoi."},
	{"pile": 1, "key": "five1", "art": "p1_7", "title": "Intrigo", "text": "Muovi fino a 5 Caballeros qualsiasi da una sola regione."},
	{"pile": 1, "key": "court2", "art": "p1_8", "title": "Intrigo", "text": "Muovi 2 Caballeros in più dalla tua corte in qualunque regione."},
	{"pile": 1, "key": "foe3", "art": "p1_9", "title": "Intrigo", "text": "Muovi fino a 3 Caballeros avversari sul tabellone."},
	{"pile": 1, "key": "own2foe2", "art": "p1_10", "title": "Intrigo", "text": "Muovi fino a 2 tuoi Caballeros e fino a 2 avversari sul tabellone."},
	# ---- pila 2
	{"pile": 2, "key": "exile_all", "art": "p2_0", "title": "Esilio", "text": "Gli avversari rimandano alle province tutti i loro Caballeros di una regione. Ognuno sceglie in segreto quale."},
	{"pile": 2, "key": "one_each", "art": "p2_1", "title": "Epurazione", "text": "Rimanda alle province 1 Caballero di ogni giocatore (anche tuo), dalla regione che scegli tu."},
	{"pile": 2, "key": "decay3", "art": "p2_2", "title": "Perdita di autorità", "text": "Gli avversari rimandano 3 Caballeros dalla loro corte alle province."},
	{"pile": 2, "key": "remove2", "art": "p2_3", "title": "Ritirata", "text": "Gli avversari rimandano alle province 2 loro Caballeros da una regione. Ognuno sceglie in segreto quale."},
	{"pile": 2, "key": "score_any", "art": "p2_4", "title": "Assegnazione di punti", "text": "Scegli una regione da valutare (anche la regione del Re o il Castillo)."},
	{"pile": 2, "key": "score_any", "art": "p2_5", "title": "Assegnazione di punti", "text": "Scegli una regione da valutare (anche la regione del Re o il Castillo)."},
	{"pile": 2, "key": "score_any", "art": "p2_6", "title": "Assegnazione di punti", "text": "Scegli una regione da valutare (anche la regione del Re o il Castillo)."},
	{"pile": 2, "key": "king_returns", "art": "p2_7", "title": "Il ritorno del Re", "text": "Ogni avversario rimanda alle province 3 Caballeros, presi dalle regioni e/o dalla sua corte."},
	{"pile": 2, "key": "veto", "art": "p2_8", "title": "Veto!", "text": "Puoi impedire un'azione speciale in questo round o nel prossimo."},
	{"pile": 2, "key": "veto", "art": "p2_9", "title": "Veto!", "text": "Puoi impedire un'azione speciale in questo round o nel prossimo."},
	{"pile": 2, "key": "decay_all", "art": "p2_10", "title": "Perdita di autorità", "text": "Gli avversari rimandano tutti i Caballeros della loro corte alle province."},
	# ---- pila 3: valutazioni
	{"pile": 3, "key": "score5", "art": "p3_0", "title": "Assegnazione di punti", "text": "Si valutano tutte le regioni da 5."},
	{"pile": 3, "key": "score67", "art": "p3_1", "title": "Assegnazione di punti", "text": "Si valutano tutte le regioni da 6 e da 7."},
	{"pile": 3, "key": "score_most", "art": "p3_2", "title": "Assegnazione di punti", "text": "Si valuta la regione con più Caballeros."},
	{"pile": 3, "key": "score_first", "art": "p3_3", "title": "Assegnazione di punti", "text": "In tutte le regioni conta soltanto il primo posto."},
	{"pile": 3, "key": "score4", "art": "p3_4", "title": "Assegnazione di punti", "text": "Si valutano tutte le regioni da 4."},
	{"pile": 3, "key": "score4", "art": "p3_5", "title": "Assegnazione di punti", "text": "Si valutano tutte le regioni da 4."},
	{"pile": 3, "key": "score_any", "art": "p3_6", "title": "Assegnazione di punti", "text": "Scegli una regione da valutare (anche la regione del Re o il Castillo)."},
	{"pile": 3, "key": "score_least", "art": "p3_7", "title": "Assegnazione di punti", "text": "Si valuta la regione con meno Caballeros (le regioni vuote non contano)."},
	{"pile": 3, "key": "score_castillo", "art": "p3_8", "title": "Assegnazione di punti", "text": "Si valuta il Castillo. I Caballeros restano dentro."},
	{"pile": 3, "key": "score_castillo", "art": "p3_9", "title": "Assegnazione di punti", "text": "Si valuta il Castillo. I Caballeros restano dentro."},
	{"pile": 3, "key": "score5", "art": "p3_10", "title": "Assegnazione di punti", "text": "Si valutano tutte le regioni da 5."},
	# ---- pila 4
	{"pile": 4, "key": "mobile", "art": "p4_0", "title": "Segnapunti mobile", "text": "Piazza un segna-punti mobile in una regione, o sposta uno già in gioco."},
	{"pile": 4, "key": "mobile", "art": "p4_1", "title": "Segnapunti mobile", "text": "Piazza un segna-punti mobile in una regione, o sposta uno già in gioco."},
	{"pile": 4, "key": "court_plus2", "art": "p4_2", "title": "La corte", "text": "Muovi 2 tuoi Caballeros dalle province alla tua corte."},
	{"pile": 4, "key": "advisor", "art": "p4_3", "title": "Editto reale", "text": "Muovi il Re in una regione confinante."},
	{"pile": 4, "key": "mobile", "art": "p4_4", "title": "Segnapunti mobile", "text": "Piazza un segna-punti mobile in una regione, o sposta uno già in gioco."},
	{"pile": 4, "key": "powerback", "art": "p4_5", "title": "Carte potere", "text": "Riprendi in mano una delle tue carte potere già giocate."},
	{"pile": 4, "key": "powerback", "art": "p4_6", "title": "Carte potere", "text": "Riprendi in mano una delle tue carte potere già giocate."},
	{"pile": 4, "key": "evict", "art": "p4_7", "title": "Espulsione", "text": "Scegli una regione: gli avversari spostano tutti i loro Caballeros da lì a un'altra regione, scelta in segreto."},
	{"pile": 4, "key": "grande", "art": "p4_8", "title": "Il Grande", "text": "Puoi spostare il tuo Grande in un'altra regione."},
	{"pile": 4, "key": "grande", "art": "p4_9", "title": "Il Grande", "text": "Puoi spostare il tuo Grande in un'altra regione."},
	{"pile": 4, "key": "score_secret", "art": "p4_10", "title": "Assegnazione di punti", "text": "Ognuno sceglie in segreto una regione: si valutano quelle scelte da un solo giocatore."},
	# ---- pila 5
	{"pile": 5, "key": "king", "art": "p5_0", "title": "Il Re", "text": "Metti il Re in una regione qualunque."},
	# ---- Grandissimo: pila 6 (19 carte) e pila 7 (Regina / Giullare)
	{"pile": 6, "n": 3, "sym": "jail", "key": "gi_take", "title": "Grande Inquisitore", "text": "Prendi il Grande Inquisitore nella tua corte fino alla prossima valutazione generale: a ogni tuo turno puoi spostare i suoi 2 Caballeros neri in una regione confinante e rimandare alle province un Caballero avversario che si trova lì."},
	{"pile": 6, "n": 3, "sym": "ship", "key": "revolution", "title": "Rivoluzione", "text": "Il Re va nel Castillo. Scegli un Grande: diventa il nuovo Re e la sua regione è la regione del Re. Dopo la prossima valutazione generale il Re va in Portogallo."},
	{"pile": 6, "n": 3, "sym": "jail", "key": "stop", "title": "Azione interrotta", "text": "Tutti quelli che giocano dopo di te in questo round non possono eseguire l'azione speciale."},
	{"pile": 6, "n": 3, "sym": "jail", "key": "score_inland", "title": "Punteggio speciale", "text": "Si valutano tutte le regioni interne (Aragona, Vecchia e Nuova Castiglia)."},
	{"pile": 6, "n": 3, "sym": "", "key": "conspiracy", "title": "Cospirazione", "text": "Metti tutti i Grandi avversari nel Castillo. Chi ha il Grande nel Castillo e la maggioranza lì prende il bonus del Grande; alla valutazione generale il Grande segue i suoi Caballeros."},
	{"pile": 6, "n": 3, "sym": "ship", "key": "province", "title": "Province", "text": "Questo turno piazzi i Caballeros prendendoli direttamente dalle province invece che dalla corte."},
	{"pile": 6, "n": 4, "sym": "ship", "key": "storm", "title": "Assalto al Castillo", "text": "Manda nel Castillo 2 Caballeros di ogni giocatore: quelli degli avversari li prendi dalle regioni, i tuoi dalla corte."},
	{"pile": 6, "n": 4, "sym": "ship", "key": "last_word", "title": "L'ultima parola", "text": "In questo round puoi giocare il resto del turno per ultimo."},
	{"pile": 6, "n": 4, "sym": "jail", "key": "alliance", "title": "Alleanza", "text": "Scegli 2 regioni: alla prossima valutazione generale si valutano insieme, sommando Caballeros e punti. Valgono i bonus del Re e del Grande."},
	{"pile": 6, "n": 6, "sym": "jail", "key": "extra6", "title": "Rinforzi", "text": "Puoi piazzare fino a 6 Caballeros dalla corte."},
	{"pile": 6, "n": 1, "sym": "ship", "key": "double_swap", "title": "Doppio scambio", "text": "Sposta o piazza entrambi i segnapunti mobili."},
	{"pile": 6, "n": 2, "sym": "", "key": "incognito", "title": "Re in incognito", "text": "Scegli in segreto una regione. In qualunque tuo turno successivo puoi rivelarla e mettervi il Re."},
	{"pile": 6, "n": 2, "sym": "jail", "key": "espionage", "title": "Spionaggio", "text": "Alla prossima valutazione generale non usi il disco: sposti i tuoi Caballeros del Castillo dove vuoi dopo che gli altri hanno mosso i loro."},
	{"pile": 6, "n": 2, "sym": "jail", "key": "free_choice", "title": "Scelta libera", "text": "Alla prossima valutazione generale, svuotato il Castillo, puoi spostare 2 tuoi Caballeros in altre regioni."},
	{"pile": 6, "n": 3, "sym": "jail", "key": "double_turn", "title": "Doppio turno", "text": "Prendi un'altra carta azione scoperta: puoi usarne l'azione speciale subito o in un tuo turno successivo."},
	{"pile": 6, "n": 2, "sym": "ship", "key": "score_coastal", "title": "Punteggio speciale", "text": "Si valutano tutte le regioni costiere, Portogallo compreso."},
	{"pile": 6, "n": 2, "sym": "ship", "key": "boycott", "title": "Boicottaggio", "text": "Scegli in segreto una regione: non riceve punti alla prossima valutazione generale."},
	{"pile": 6, "n": 2, "sym": "ship", "key": "evict_castillo", "title": "Ordine di sgombero", "text": "Gli avversari riportano nella loro corte tutti i loro Caballeros del Castillo."},
	{"pile": 6, "n": 2, "sym": "ship", "key": "score_courts", "title": "Punteggio speciale", "text": "Le corti dei giocatori si valutano come una regione (6 / 5 / 1)."},
	{"pile": 7, "n": 3, "sym": "", "key": "queen_jester", "title": "7ª Pila", "text": "Prendi la Regina o il Giullare nella tua corte."},
]
const QUEEN_CARD := 64
const COURTS_VALS := [6, 5, 1]
const KING_CARD := 44


## Caballeros che la carta permette di piazzare.
static func card_n(ci: int) -> int:
	return int(CARDS[ci].get("n", CARDS[ci]["pile"]))


static func card_tex_path(ci: int) -> String:
	if ci >= 45:
		return "res://assets/grandissimo/c%d.jpg" % ci
	return "res://assets/actions_it/c%d.jpg" % ci


static func pile_cards(p: int) -> Array:
	var out := []
	for i in CARDS.size():
		if CARDS[i]["pile"] == p:
			out.append(i)
	return out


static func region_name(r: int) -> String:
	return REGIONS[r]["name"] if r >= 0 and r < REGIONS.size() else "?"


static func track_pos(score: int) -> Vector2:
	var s := posmod(score, 100)
	if s > 99:
		s = 99
	for i in range(TRACK.size() - 1):
		var a: Array = TRACK[i]
		var b: Array = TRACK[i + 1]
		if s >= a[0] and s <= b[0]:
			var t := 0.0 if b[0] == a[0] else float(s - a[0]) / float(b[0] - a[0])
			return Vector2(a[1], a[2]).lerp(Vector2(b[1], b[2]), t)
	var l: Array = TRACK.back()
	return Vector2(l[1], l[2])


## Regione del tabellone sotto un punto (unità tabellone), -1 se nessuna.
static func region_at(p: Vector2) -> int:
	if p.distance_to(CASTILLO_POS) < 75:
		return CASTILLO
	if p.distance_to(SHIP_G_POS) < 70:
		return SHIP_G
	var best := -1
	var bd := 140.0
	for r in ANCHORS.size():
		for a in ANCHORS[r]:
			var d := p.distance_to(a)
			if d < bd:
				bd = d
				best = r
	return best
