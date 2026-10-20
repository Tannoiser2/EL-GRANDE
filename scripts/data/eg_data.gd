class_name EGData
extends RefCounted
## Dati fissi di El Grande (gioco base): regioni, confini, valori, carte potere e carte azione.
## Le coordinate sono in "unità tabellone" (immagine del tabellone ridotta a 1400 x 1025).

const BOARD_SIZE := Vector2(1400, 1025)
const CASTILLO := 9

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
]
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
]
const KING_CARD := 44


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
	var best := -1
	var bd := 140.0
	for r in ANCHORS.size():
		for a in ANCHORS[r]:
			var d := p.distance_to(a)
			if d < bd:
				bd = d
				best = r
	return best
