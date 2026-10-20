class_name EGEngine
extends Node
## Motore delle regole di El Grande, senza dipendenze dalla UI. Gioco base ed espansioni.
## Ogni scelta passa da `decide()`: l'IA risponde subito; per i giocatori umani viene emesso
## `decision_requested` e si attende `provide_decision()`. Online le scelte viaggiano nel registro di
## mosse (OnlineSession): con lo stesso seme ogni dispositivo ottiene la stessa partita.
##
## Regioni: 0..8 come sul tabellone, 9 = Castillo, 10 = Portogallo, 11..14 colonie, 15 = nave di
## Grandissimo, 16 = prigione (vedi EGData). Le righe di `cab` esistono sempre; le espansioni attivano
## le regioni che servono.
##
## Varianti (config["variant"]): "base", "grandissimo".

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(results: Array)
signal fx(kind: String, data: Dictionary)
signal pause_requested(req: Dictionary)

const D = preload("res://scripts/data/eg_data.gd")
const CAS := 9
const POR := 10
const SHIP := 15
const JAIL := 16

var rng := RandomNumberGenerator.new()
var ai_delay := 0.0
var headless := false
var ais := {}
var online = null
var abort := false
var pause_enabled := false

var variant := "base"
var grandissimo := false

var players: Array = []          # {color, ai, name, level}
var n := 0
var cab: Array = []              # cab[regione][posto]
var court: Array = []
var prov: Array = []
var score: Array = []
var grande: Array = []           # regione del Grande (9 = nel Castillo, dopo la Cospirazione)
var king := 0
var mobile := [-1, -1]           # regione dei segna-punti mobili 8/4/0 e 4/0/0 (-1 fuori)
var hand: Array = []             # carte potere in mano
var discard: Array = []          # carte potere giocate (l'ultima è in cima)
var played: Array = []           # carta potere di questo round (0 = nessuna)
var order: Array = []            # ordine di turno del round
var start_seat := 0
var piles: Array = [[], [], [], [], [], []]   # pile 1..4 e 6 (indice 4 = pila 6)
var showing: Array = []          # carte azione scoperte nel round
var taken := {}                  # carta -> posto che l'ha presa
var veto := {}                   # posto -> ultimo round in cui il veto vale
var rounds: Array = []
var cur_round := 0
var round_i := 0
var phase := ""                  # setup, power, turn, scoring, over
var current := -1                # chi sta decidendo
var acting := -1                 # chi sta giocando il turno
var castillo_hidden := false
var game_over := false
var results: Array = []
var log_lines: Array = []
var last_scores: Array = []      # ultime valutazioni [regione, {posto: punti}] per la UI

# ---- Grandissimo
var ships := [-1, -1]            # proprietario dei due gettoni nave (-1 = a lato del tabellone)
var queen := -1
var jester := -1
var inq_owner := -1              # chi ha il Grande Inquisitore
var inq_pos := -1                # regione dei 2 Caballeros neri
var revolution := -1             # posto il cui Grande fa da Re (-1 = nessuna rivoluzione)
var stop_after := -1             # numero di turno dopo il quale le azioni speciali sono bloccate
var turn_no := 0
var boycott := {}                # posto -> regione boicottata (segreta)
var alliance := {}               # posto -> [r1, r2]
var incognito := {}              # posto -> regione (segreta)
var espionage := {}              # posto -> true
var free_choice := {}            # posto -> true
var saved := {}                  # posto -> [carte del Doppio turno da usare]
var gifts := {}                  # posto che riceve -> [posti che regalano] (Giullare)
var deferred: Array = []         # turni rimandati con L'ultima parola: [posto, carta]
var from_prov := false           # carta Province: si piazza dalle province


# ================================================================ preparazione

func setup(config: Dictionary) -> void:
	players = []
	for s in config["seats"]:
		players.append({"color": int(s["color"]), "ai": bool(s["ai"]), "name": str(s["name"]), "level": int(s.get("level", 1))})
	n = players.size()
	if config.has("seed"):
		rng.seed = int(config["seed"])
	else:
		rng.randomize()
	ai_delay = float(config.get("ai_delay", 0.0))
	castillo_hidden = bool(config.get("castillo_hidden", false))
	variant = str(config.get("variant", "base"))
	grandissimo = variant == "grandissimo"
	var short := bool(config.get("short", false))
	rounds = [2, 3, 5, 6, 8, 9] if short else [1, 2, 3, 4, 5, 6, 7, 8, 9]
	cab = []
	for r in D.NREG:
		var row := []
		row.resize(n)
		row.fill(0)
		cab.append(row)
	court = []
	prov = []
	score = []
	grande = []
	hand = []
	discard = []
	played = []
	for s in n:
		court.append(7)
		prov.append(21)
		score.append(0)
		grande.append(-1)
		var h := []
		for v in range(1, 14):
			h.append(v)
		hand.append(h)
		discard.append([])
		played.append(0)
	for p in 4:
		piles[p] = D.pile_cards(p + 1)
		_shuffle(piles[p])
	if grandissimo:
		piles[4] = D.pile_cards(6)
		_shuffle(piles[4])
	# carte regione: la prima va al Re, poi una a testa per la regione di provenienza
	var regs := range(9)
	_shuffle(regs)
	king = regs[0]
	for s in n:
		grande[s] = regs[s + 1]
		cab[grande[s]][s] = 2
	if grandissimo:
		# i 2 Caballeros neri dell'Inquisitore in una regione pescata a caso
		inq_pos = regs[n + 1] if n + 1 < 9 else regs[8]
	start_seat = rng.randi() % n
	phase = "setup"


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func pname(s: int) -> String:
	return players[s]["name"] if s >= 0 and s < n else "?"


## Caballeros che passano da un posto all'altro (per le animazioni): "prov", "court" o una regione.
func flow(s: int, from, to, q: int) -> void:
	if q > 0 and not headless:
		fx.emit("flow", {"seat": s, "from": from, "to": to, "n": q})


func log_msg(t: String) -> void:
	log_lines.append(t)
	if log_lines.size() > 400:
		log_lines.pop_front()
	log_added.emit(t)


func rname(r: int) -> String:
	return D.region_name(r)


func any_local_human() -> bool:
	if online != null:
		return true
	for p in players:
		if not p["ai"]:
			return true
	return false


# ================================================================ decisioni

func decide(seat: int, req: Dictionary):
	req["seat"] = seat
	current = seat
	changed.emit()
	if abort:
		return ais[seat].decide(self, seat, req)
	if online != null:
		var r0 = await online.decide(self, seat, req)
		return r0
	if players[seat]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay).timeout
		return ais[seat].decide(self, seat, req)
	decision_requested.emit(req)
	var r = await decision_provided
	return r


func provide_decision(r) -> void:
	decision_provided.emit(r)


## Scelta fra opzioni: restituisce l'indice.
func pick(seat: int, ctx: String, title: String, options: Array, extra := {}) -> int:
	var req := {"type": "pick", "ctx": ctx, "title": title, "options": options}
	for k in extra:
		req[k] = extra[k]
	var c = await decide(seat, req)
	return clampi(int(c) if (c is int or c is float) else 0, 0, options.size() - 1)


func yesno(seat: int, ctx: String, title: String, extra := {}, no_label := "No", yes_label := "Sì") -> bool:
	return await pick(seat, ctx, title, [{"label": no_label}, {"label": yes_label}], extra) == 1


## Scelta di una regione fra quelle permesse (allow_skip: -1 = rinuncia).
func pick_region(seat: int, ctx: String, title: String, allowed: Array, allow_skip := false, extra := {}) -> int:
	if allowed.is_empty():
		return -1
	var req := {"type": "region", "ctx": ctx, "title": title, "allowed": allowed, "skip": allow_skip}
	for k in extra:
		req[k] = extra[k]
	var c = await decide(seat, req)
	var r := int(c) if (c is int or c is float) else -1
	if r in allowed:
		return r
	if allow_skip:
		return -1
	return allowed[0]


## Scelta di un giocatore (o nessuno con allow_skip): restituisce il posto o -1.
func pick_player(seat: int, ctx: String, title: String, allowed: Array, allow_skip := false, extra := {}) -> int:
	if allowed.is_empty():
		return -1
	var opts := []
	for t in allowed:
		opts.append({"label": pname(t), "p": t})
	if allow_skip:
		opts.append({"label": "Nessuno", "p": -1})
	var i := await pick(seat, ctx, title, opts, extra)
	return int(opts[i]["p"])


func pause_point(req: Dictionary) -> void:
	if headless or abort or not pause_enabled or not any_local_human():
		return
	if online != null and online.catchup:
		return
	pause_requested.emit(req)
	await decision_provided


# ================================================================ regioni

## Regioni della mappa che si valutano (senza Castillo), nell'ordine della valutazione generale.
func map_regions() -> Array:
	var out := range(9)
	if grandissimo:
		out.append(POR)
	return out


## Regioni dove può stare il Re.
func king_regions() -> Array:
	return map_regions()


## Regioni protette (niente entra, niente esce).
func taboo(r: int) -> bool:
	return r == king


func adj(r: int) -> Array:
	var out := []
	if r < D.ADJ.size():
		for a in D.ADJ[r]:
			if a in map_regions():
				out.append(a)
	for a in map_regions():
		if a < D.ADJ.size() and r in D.ADJ[a] and not (a in out):
			out.append(a)
	return out


func total_in(r: int) -> int:
	var t := 0
	for s in n:
		t += cab[r][s]
	return t


## Regioni dove si possono togliere o aggiungere Caballeros (non quella del Re).
func free_regions() -> Array:
	var out := []
	for r in map_regions():
		if not taboo(r):
			out.append(r)
	return out


func ship_holder(s: int) -> bool:
	return s in ships


func place_targets(s := -1) -> Array:
	var out := []
	for a in adj(king):
		if not taboo(a):
			out.append(a)
	out.append(CAS)
	if grandissimo and s >= 0 and ship_holder(s):
		out.append(SHIP)
	return out


func any_targets() -> Array:
	var out := free_regions()
	out.append(CAS)
	return out


## Regioni scelte dal disco segreto (solo le 9 regioni spagnole, non quella del Re).
func disk_regions() -> Array:
	var out := []
	for r in 9:
		if not taboo(r):
			out.append(r)
	return out


func on_board(s: int) -> int:
	var t := 0
	for r in D.NREG:
		t += cab[r][s]
	return t


func vals(r: int) -> Array:
	for m in 2:
		if mobile[m] == r:
			return D.MOBILE[m]
	return D.REGIONS[r]["vals"]


func npos() -> int:
	return 1 if n == 2 else (2 if n == 3 else 3)


func card(c: int) -> Dictionary:
	return D.CARDS[c]


func veto_active(s: int) -> bool:
	return veto.has(s) and veto[s] >= cur_round


## Carte regione disponibili (non tenute da Boicottaggio, Alleanza o Re in incognito).
func region_cards_free() -> Array:
	var out := range(9)
	for s in boycott:
		out.erase(boycott[s])
	for s in incognito:
		out.erase(incognito[s])
	for s in alliance:
		for r in alliance[s]:
			out.erase(r)
	return out


# ================================================================ partita

func run() -> void:
	log_msg("Il Re si trova in %s." % rname(king))
	for s in n:
		log_msg("%s: il Grande parte da %s." % [pname(s), rname(grande[s])])
	if grandissimo:
		log_msg("I Caballeros neri del Grande Inquisitore sono in %s." % rname(inq_pos))
	changed.emit()
	for i in rounds.size():
		if game_over:
			return
		round_i = i
		cur_round = rounds[i]
		await _play_round()
		if cur_round in [3, 6, 9]:
			await general_scoring()
	_end_game()


func _play_round() -> void:
	log_msg("— Round %d —" % cur_round)
	taken = {}
	showing = []
	for p in 4:
		if piles[p].is_empty():
			piles[p] = D.pile_cards(p + 1)
			_shuffle(piles[p])
		showing.append(piles[p].pop_back())
	showing.append(D.KING_CARD)
	if grandissimo:
		if piles[4].is_empty():
			piles[4] = D.pile_cards(6)
			_shuffle(piles[4])
		showing.append(piles[4].pop_back())
		showing.append(D.QUEEN_CARD)
	for s in n:
		played[s] = 0
	stop_after = -1
	turn_no = 0
	deferred = []
	phase = "power"
	changed.emit()
	# carte potere, a partire da start_seat in senso orario
	var seq := []
	for k in n:
		var s := (start_seat + k) % n
		var used := []
		for t in seq:
			used.append(played[t])
		var legal := []
		for v in hand[s]:
			if not (v in used):
				legal.append(v)
		if legal.is_empty():
			legal = hand[s].duplicate()
		legal.sort()
		var v: int = await _ask_power(s, legal, used)
		played[s] = v
		hand[s].erase(v)
		discard[s].append(v)
		seq.append(s)
		log_msg("%s gioca la carta potere %d (%d Caballeros)." % [pname(s), v, D.POWER_CAB[v]])
		changed.emit()
	# ordine: dal valore più alto; a parità va dopo chi l'ha giocata dopo
	order = seq.duplicate()
	order.sort_custom(func(a, b):
		if played[a] != played[b]:
			return played[a] > played[b]
		return seq.find(a) < seq.find(b))
	phase = "turn"
	for s in order:
		if game_over:
			return
		await _turn(s)
	# L'ultima parola: chi ha rimandato finisce il turno adesso
	for dfr in deferred:
		await _finish_turn(int(dfr[0]), int(dfr[1]))
	start_seat = order.back()
	acting = -1
	# i veto non usati scadono alla fine del round successivo a quello in cui sono stati presi
	for s in veto.keys():
		if veto[s] <= cur_round:
			veto.erase(s)
			log_msg("Il veto di %s non è stato usato ed è scartato." % pname(s))
	changed.emit()


func _ask_power(s: int, legal: Array, used: Array) -> int:
	var req := {"type": "power", "ctx": "power", "title": "Gioca una carta potere", "legal": legal, "used": used, "hand": hand[s].duplicate()}
	var c = await decide(s, req)
	var v := int(c) if (c is int or c is float) else -1
	if v in legal:
		return v
	return legal[0]


func _turn(s: int) -> void:
	acting = s
	var v: int = played[s]
	var nc: int = D.POWER_CAB[v]
	log_msg("Turno di %s." % pname(s))
	if grandissimo:
		await _turn_start_grandissimo(s)
	# 1. dalle province alla corte
	var take: int = mini(nc, prov[s])
	prov[s] -= take
	court[s] += take
	flow(s, "prov", "court", take)
	if take > 0:
		log_msg("%s porta %d Caballeros dalle province alla corte." % [pname(s), take])
	var short: int = nc - take
	if short > 0 and _own_movable(s) > 0:
		var r = await decide(s, {"type": "take", "ctx": "fill", "title": "Le province sono vuote: puoi riportare a corte fino a %d Caballeros dal tabellone" % short,
			"n": short, "exact": false, "sources": _own_sources(s, false)})
		var got := _apply_take(s, r, short, false, "court")
		if got > 0:
			log_msg("%s riporta %d Caballeros dal tabellone alla corte." % [pname(s), got])
	changed.emit()
	# 2. scelta della carta azione
	var avail := _available_cards()
	var c = await decide(s, {"type": "action", "ctx": "action", "title": "Scegli una carta azione", "cards": avail})
	var ci := int(c) if (c is int or c is float) else -1
	if not (ci in avail):
		ci = avail[0]
	taken[ci] = s
	var cd := card(ci)
	log_msg("%s sceglie «%s» (pila %d)." % [pname(s), cd["title"], cd["pile"]])
	changed.emit()
	if cd["key"] == "last_word" and order.find(s) < order.size() - 1:
		if await yesno(s, "last_word", "L'ultima parola: finisci il turno dopo tutti gli altri?", {"card": ci}, "No, gioco adesso", "Sì, gioco per ultimo"):
			log_msg("%s finirà il turno per ultimo." % pname(s))
			deferred.append([s, ci])
			return
	await _finish_turn(s, ci)


func _available_cards() -> Array:
	var out := []
	for c in showing:
		if not taken.has(c):
			out.append(c)
	return out


## Piazzamento e azione speciale della carta scelta, poi le azioni extra di Grandissimo.
func _finish_turn(s: int, ci: int) -> void:
	acting = s
	turn_no += 1
	var cd := card(ci)
	var k := D.card_n(ci)
	from_prov = cd["key"] == "province"
	var src_n: int = prov[s] if from_prov else court[s]
	var special_first := false
	if src_n > 0 and cd["key"] != "veto":
		var o := await pick(s, "order", "Cosa fai prima?", [{"label": "Piazzo prima i Caballeros"}, {"label": "Prima l'azione speciale"}], {"card": ci})
		special_first = o == 1
	if special_first:
		await _special(s, ci)
		await _place(s, k)
	else:
		await _place(s, k)
		await _special(s, ci)
	from_prov = false
	if grandissimo:
		await _symbols(s, ci)
		await _turn_end_grandissimo(s)
	changed.emit()


func _own_sources(s: int, with_court: bool) -> Array:
	var out := []
	for r in map_regions():
		if not taboo(r) and cab[r][s] > 0:
			out.append(r)
	if with_court and court[s] > 0:
		out.append(-1)
	return out


func _own_movable(s: int) -> int:
	var t := 0
	for r in map_regions():
		if not taboo(r):
			t += cab[r][s]
	return t


## Toglie Caballeros propri: r = {sorgente: quanti} (sorgente -1 = corte). dest "court", "prov" o "cas".
func _apply_take(s: int, r, nmax: int, exact: bool, dest: String) -> int:
	var got := 0
	var d: Dictionary = r if r is Dictionary else {}
	var ok_src := _own_sources(s, dest != "court")
	for k in d:
		var src := int(k)
		var q := int(d[k])
		if q <= 0 or not (src in ok_src):
			continue
		var avail: int = court[s] if src == -1 else cab[src][s]
		q = mini(q, mini(avail, nmax - got))
		if q <= 0:
			continue
		_move_out(s, src, dest, q)
		got += q
	if exact and got < nmax:
		# completa automaticamente (scelta non valida o incompleta)
		for src in _own_sources(s, dest != "court"):
			while got < nmax:
				if (src == -1 and court[s] > 0) or (src >= 0 and cab[src][s] > 0):
					_move_out(s, src, dest, 1)
					got += 1
				else:
					break
	return got


func _move_out(s: int, src: int, dest: String, q: int) -> void:
	if src == -1:
		court[s] -= q
	else:
		cab[src][s] -= q
	match dest:
		"court":
			court[s] += q
		"prov":
			prov[s] += q
		"cas":
			cab[CAS][s] += q
	flow(s, "court" if src == -1 else src, CAS if dest == "cas" else dest, q)


## Piazzamento dalla corte (o dalle province con la carta Province): fino a k Caballeros nelle
## regioni confinanti col Re e/o nel Castillo.
func _place(s: int, k: int, targets: Array = [], ctx := "place") -> void:
	var avail: int = prov[s] if from_prov else court[s]
	var q: int = mini(k, avail)
	if q <= 0:
		return
	if targets.is_empty():
		targets = place_targets(s)
	var title := "Piazza fino a %d Caballeros %s" % [q, "dalle province" if from_prov else "dalla corte"]
	var r = await decide(s, {"type": "place", "ctx": ctx, "title": title, "n": q, "targets": targets, "from_prov": from_prov})
	var d: Dictionary = r if r is Dictionary else {}
	var put := 0
	var parts := []
	for key in d:
		var t := int(key)
		var m := int(d[key])
		if not (t in targets) or m <= 0:
			continue
		m = mini(m, q - put)
		if m <= 0:
			continue
		cab[t][s] += m
		if from_prov:
			prov[s] -= m
		else:
			court[s] -= m
		flow(s, "prov" if from_prov else "court", t, m)
		put += m
		parts.append("%d in %s" % [m, rname(t)] if t != CAS or not castillo_hidden else "%d nel Castillo" % m)
	if put > 0:
		log_msg("%s piazza %s." % [pname(s), ", ".join(parts)])
		fx.emit("place", {"seat": s, "d": d})
	changed.emit()


# ================================================================ azioni speciali

func _special(s: int, ci: int) -> void:
	var cd := card(ci)
	var key: String = cd["key"]
	if key == "veto":
		veto[s] = cur_round + 1
		log_msg("%s tiene il Veto (vale fino alla fine del round %d)." % [pname(s), cur_round + 1])
		return
	if key in ["extra6", "province", "last_word"]:
		return
	if stop_after >= 0 and turn_no > stop_after:
		log_msg("Azione interrotta: %s non può eseguire l'azione speciale." % pname(s))
		return
	if not _special_possible(s, key):
		return
	if not await yesno(s, "do", "Eseguire l'azione «%s»?" % cd["title"], {"card": ci}, "Non eseguire", "Esegui"):
		log_msg("%s non esegue l'azione speciale." % pname(s))
		return
	# veto degli altri giocatori, in senso orario
	for k in range(1, n):
		var o := (s + k) % n
		if veto_active(o):
			var vv := await pick(o, "veto", "%s sta per eseguire «%s». Usi il tuo Veto?" % [pname(s), cd["title"]], [{"label": "Lascia fare"}, {"label": "VETO!"}], {"card": ci, "actor": s})
			if vv == 1:
				veto.erase(o)
				log_msg("%s pone il VETO: l'azione di %s è annullata!" % [pname(o), pname(s)])
				fx.emit("veto", {"seat": o})
				return
	await _do_special(s, ci, key)
	changed.emit()


func _do_special(s: int, ci: int, key: String) -> void:
	match key:
		"own4":
			await _moves(s, {"max": 4, "own": 4, "foe": 0})
		"any3":
			await _moves(s, {"max": 3, "own": 3, "foe": 3})
		"any4":
			await _moves(s, {"max": 4, "own": 4, "foe": 4})
		"foe3":
			await _moves(s, {"max": 3, "own": 0, "foe": 3})
		"own2foe2":
			await _moves(s, {"max": 4, "own": 2, "foe": 2})
		"five1":
			await _moves(s, {"max": 5, "own": 5, "foe": 5, "single": true})
		"allown":
			await _all_own(s)
		"court2":
			await _place(s, 2, any_targets(), "court2")
		"court2_or_all":
			var ch := await pick(s, "c2oa", "Quale intrigo?", [{"label": "2 Caballeros dalla corte in qualunque regione"}, {"label": "Tutti i tuoi Caballeros da una regione"}])
			if ch == 0:
				await _place(s, 2, any_targets(), "court2")
			else:
				await _all_own(s)
		"exile_all":
			await _exile(s, false)
		"remove2":
			await _exile(s, true)
		"one_each":
			await _one_each(s)
		"decay3", "decay_all":
			for k in range(1, n):
				var o := (s + k) % n
				var q: int = court[o] if key == "decay_all" else mini(3, court[o])
				court[o] -= q
				prov[o] += q
				flow(o, "court", "prov", q)
				if q > 0:
					log_msg("%s rimanda %d Caballeros dalla corte alle province." % [pname(o), q])
		"king_returns":
			for k in range(1, n):
				var o := (s + k) % n
				var avail: int = _own_movable(o) + court[o]
				var q := mini(3, avail)
				if q <= 0:
					continue
				var r = await decide(o, {"type": "take", "ctx": "king_returns", "title": "Il ritorno del Re: rimanda %d Caballeros alle province (dalle regioni o dalla corte)" % q,
					"n": q, "exact": true, "sources": _own_sources(o, true)})
				_apply_take(o, r, q, true, "prov")
				log_msg("%s rimanda %d Caballeros alle province." % [pname(o), q])
		"score_any":
			var allowed := map_regions()
			allowed.append(CAS)
			var r := await pick_region(s, "score_any", "Scegli la regione da valutare", allowed)
			score_region(r)
		"score4", "score5", "score67":
			var want: Array = {"score4": [4], "score5": [5], "score67": [6, 7]}[key]
			var any := false
			for r in map_regions():
				if int(vals(r)[0]) in want:
					score_region(r)
					any = true
			if not any:
				log_msg("Nessuna regione da valutare.")
		"score_most", "score_least":
			var best := []
			var bv := -1 if key == "score_most" else 999
			for r in map_regions():
				var t := total_in(r)
				if key == "score_least" and t == 0:
					continue
				if (key == "score_most" and t > bv) or (key == "score_least" and t < bv):
					bv = t
					best = [r]
				elif t == bv:
					best.append(r)
			for r in best:
				score_region(r)
		"score_first":
			for r in map_regions():
				score_region(r, true)
		"score_castillo":
			score_region(CAS)
		"score_secret":
			var picks := {}
			for k in n:
				var o := (s + k) % n
				picks[o] = await pick_region(o, "secret_score", "Valutazione segreta: scegli la regione da valutare", range(9), false, {"secret": true})
			var cnt := {}
			for o in picks:
				cnt[picks[o]] = cnt.get(picks[o], 0) + 1
			var txt := []
			for o in picks:
				txt.append("%s → %s" % [pname(o), rname(picks[o])])
			log_msg("Dischi rivelati: " + ", ".join(txt))
			fx.emit("discs", {"picks": picks})
			await pause_point({"kind": "discs", "picks": picks, "title": "Valutazione segreta"})
			for r in 9:
				if cnt.get(r, 0) == 1:
					score_region(r)
		"mobile":
			var boards := []
			for m in 2:
				if not _mobile_targets(m).is_empty():
					boards.append(m)
			if boards.is_empty():
				return
			var m: int = boards[0]
			if boards.size() > 1:
				var labels := []
				for b in boards:
					labels.append({"label": "Segna-punti %s%s" % [D.MOBILE_NAME[b], "" if mobile[b] < 0 else " (ora in %s)" % rname(mobile[b])], "m": b})
				m = boards[await pick(s, "mobile", "Quale segna-punti mobile usi?", labels, {"card": ci})]
			await _place_mobile(s, m)
		"court_plus2":
			var q := mini(2, prov[s])
			prov[s] -= q
			court[s] += q
			flow(s, "prov", "court", q)
			log_msg("%s porta %d Caballeros dalle province alla corte." % [pname(s), q])
		"advisor":
			var allowed := []
			for a in adj(king):
				allowed.append(a)
			var r := await pick_region(s, "advisor", "Editto reale: muovi il Re in una regione confinante", allowed)
			_move_king(r)
		"king":
			var r := await pick_region(s, "king", "Metti il Re in una regione qualunque", king_regions())
			_move_king(r)
		"powerback":
			if discard[s].is_empty():
				return
			var opts := []
			for v in discard[s]:
				opts.append({"label": "Carta %d" % v, "v": v})
			var i := await pick(s, "powerback", "Riprendi in mano una carta potere", opts)
			var v: int = opts[i]["v"]
			discard[s].erase(v)
			hand[s].append(v)
			hand[s].sort()
			log_msg("%s riprende in mano una carta potere." % pname(s))
		"evict":
			var allowed := []
			for r in free_regions():
				for k in range(1, n):
					if cab[r][(s + k) % n] > 0:
						allowed.append(r)
						break
			var r := await pick_region(s, "evict", "Espulsione: scegli la regione da sgomberare", allowed)
			if r < 0:
				return
			log_msg("%s sceglie %s: gli avversari devono andarsene." % [pname(s), rname(r)])
			var dest := {}
			for k in range(1, n):
				var o := (s + k) % n
				if cab[r][o] > 0:
					dest[o] = await pick_region(o, "evict_dest", "Espulsione: dove sposti i tuoi %d Caballeros da %s?" % [cab[r][o], rname(r)], map_regions(), false, {"secret": true, "from": r})
			for o in dest:
				var q: int = cab[r][o]
				cab[r][o] = 0
				var t: int = dest[o]
				flow(o, r, "court" if (taboo(t) or t == r) else t, q)
				if taboo(t) or t == r:
					court[o] += q
					log_msg("%s riporta %d Caballeros a corte." % [pname(o), q])
				else:
					cab[t][o] += q
					log_msg("%s sposta %d Caballeros in %s." % [pname(o), q, rname(t)])
		"grande":
			if taboo(grande[s]) or grande[s] == CAS:
				log_msg("Il Grande di %s non può muoversi." % pname(s))
				return
			var allowed := []
			for r in free_regions():
				if r != grande[s]:
					allowed.append(r)
			var r := await pick_region(s, "grande", "Sposta il tuo Grande", allowed, true)
			if r >= 0:
				grande[s] = r
				log_msg("%s sposta il Grande in %s." % [pname(s), rname(r)])
		# ---------------- Grandissimo
		"gi_take":
			if inq_owner >= 0 and inq_owner != s:
				log_msg("%s prende il Grande Inquisitore a %s." % [pname(s), pname(inq_owner)])
			else:
				log_msg("%s prende il Grande Inquisitore." % pname(s))
			inq_owner = s
		"revolution":
			var cands := []
			for t in n:
				if grande[t] >= 0 and grande[t] != CAS:
					cands.append(t)
			var g := await pick_player(s, "revolution", "Rivoluzione: quale Grande diventa il nuovo Re?", cands)
			if g < 0:
				return
			revolution = g
			king = grande[g]
			log_msg("Rivoluzione! Il Re va nel Castillo; il Grande di %s è il nuovo Re in %s." % [pname(g), rname(king)])
			fx.emit("king", {"r": king})
		"stop":
			stop_after = turn_no
			log_msg("Azione interrotta: chi gioca dopo %s in questo round non avrà l'azione speciale." % pname(s))
		"score_inland":
			for r in D.INLAND:
				score_region(r)
		"score_coastal":
			for r in D.COASTAL:
				if r in map_regions():
					score_region(r)
		"score_courts":
			_score_courts()
		"conspiracy":
			var moved := []
			for t in n:
				if t != s and grande[t] >= 0 and grande[t] != CAS and not taboo(grande[t]):
					grande[t] = CAS
					moved.append(pname(t))
			log_msg("Cospirazione: nel Castillo i Grandi di %s." % (", ".join(moved) if not moved.is_empty() else "nessuno"))
		"storm":
			for k in range(1, n):
				var o := (s + k) % n
				for j in 2:
					var srcs := _own_sources(o, false)
					if srcs.is_empty():
						break
					var r := await pick_region(s, "storm", "Assalto al Castillo: da quale regione prendi un Caballero di %s?" % pname(o), srcs, false, {"victim": o})
					cab[r][o] -= 1
					cab[CAS][o] += 1
					flow(o, r, CAS, 1)
			var q := mini(2, court[s])
			court[s] -= q
			cab[CAS][s] += q
			flow(s, "court", CAS, q)
			log_msg("Assalto al Castillo: 2 Caballeros di ogni giocatore entrano nel Castillo.")
		"alliance":
			var a := await pick_region(s, "alliance", "Alleanza: scegli la prima regione", region_cards_free())
			var free := region_cards_free()
			free.erase(a)
			var b := await pick_region(s, "alliance2", "Alleanza: scegli la seconda regione (unita a %s)" % rname(a), free, false, {"first": a})
			if a >= 0 and b >= 0:
				alliance[s] = [a, b]
				log_msg("%s allea %s e %s per la prossima valutazione generale." % [pname(s), rname(a), rname(b)])
		"double_swap":
			for m in 2:
				if not _mobile_targets(m).is_empty():
					await _place_mobile(s, m)
		"incognito":
			var r := await pick_region(s, "incognito", "Re in incognito: scegli in segreto una regione", region_cards_free(), false, {"secret": true})
			if r >= 0:
				incognito[s] = r
				log_msg("%s tiene coperta una carta regione (Re in incognito)." % pname(s))
		"espionage":
			espionage[s] = true
			log_msg("%s userà lo Spionaggio alla prossima valutazione generale." % pname(s))
		"free_choice":
			free_choice[s] = true
			log_msg("%s tiene la Scelta libera per la prossima valutazione generale." % pname(s))
		"double_turn":
			var avail := _available_cards()
			if avail.is_empty():
				return
			var c = await decide(s, {"type": "action", "ctx": "double_turn", "title": "Doppio turno: prendi un'altra carta azione", "cards": avail})
			var c2 := int(c) if (c is int or c is float) else -1
			if not (c2 in avail):
				c2 = avail[0]
			taken[c2] = s
			log_msg("%s prende anche «%s» col Doppio turno." % [pname(s), card(c2)["title"]])
			if await yesno(s, "double_now", "Usi adesso l'azione di «%s»?" % card(c2)["title"], {"card": c2}, "La tengo per un altro turno", "La uso adesso"):
				await _special(s, c2)
				await _symbols(s, c2)
			else:
				if not saved.has(s):
					saved[s] = []
				saved[s].append(c2)
		"boycott":
			var r := await pick_region(s, "boycott", "Boicottaggio: scegli in segreto la regione che non riceverà punti", region_cards_free(), false, {"secret": true})
			if r >= 0:
				boycott[s] = r
				log_msg("%s tiene coperta una carta regione (Boicottaggio)." % pname(s))
		"evict_castillo":
			for k in range(1, n):
				var o := (s + k) % n
				var q: int = cab[CAS][o]
				if q > 0:
					cab[CAS][o] = 0
					court[o] += q
					flow(o, CAS, "court", q)
			log_msg("Ordine di sgombero: gli avversari riportano a corte i loro Caballeros del Castillo.")
		"queen_jester":
			await _take_character(s)


func _special_possible(s: int, key: String) -> bool:
	match key:
		"powerback":
			return not discard[s].is_empty()
		"grande":
			return not taboo(grande[s]) and grande[s] != CAS
		"mobile":
			return not _mobile_options().is_empty()
		"allown":
			return _own_movable(s) > 0
		"court2":
			return court[s] > 0
		"court_plus2":
			return prov[s] > 0
		"alliance":
			return region_cards_free().size() >= 2
		"incognito", "boycott":
			return not region_cards_free().is_empty() and not (key == "incognito" and incognito.has(s)) and not (key == "boycott" and boycott.has(s))
		"double_turn":
			return not _available_cards().is_empty()
		"espionage":
			return not espionage.has(s)
		"free_choice":
			return not free_choice.has(s)
	return true


func _mobile_options() -> Array:
	var out := []
	for m in 2:
		for r in _mobile_targets(m):
			out.append([m, r])
	return out


func _mobile_targets(m: int) -> Array:
	var out := []
	if mobile[m] >= 0 and taboo(mobile[m]):
		return out
	var regs := map_regions()
	regs.append(CAS)
	for r in regs:
		if taboo(r) or r == mobile[0] or r == mobile[1]:
			continue
		out.append(r)
	return out


func _place_mobile(s: int, m: int) -> void:
	var r := await pick_region(s, "mobile_dest", "Dove metti il segna-punti %s?" % D.MOBILE_NAME[m], _mobile_targets(m), false, {"m": m})
	if r < 0:
		return
	mobile[m] = r
	log_msg("%s mette il segna-punti %s in %s." % [pname(s), D.MOBILE_NAME[m], rname(r)])
	changed.emit()


func _move_king(r: int) -> void:
	if not (r in king_regions()):
		return
	king = r
	if revolution >= 0:
		grande[revolution] = r
		log_msg("Il Grande-Re di %s si sposta in %s." % [pname(revolution), rname(r)])
	else:
		log_msg("Il Re si sposta in %s." % rname(r))
	fx.emit("king", {"r": r})


## Movimento di Caballeros sul tabellone. spec: max, own, foe, single.
## Risposta: [[da, a, posto], ...]
func _moves(s: int, spec: Dictionary) -> void:
	var req := {"type": "moves", "ctx": "moves", "title": _moves_title(spec), "spec": spec}
	var r = await decide(s, req)
	_apply_moves(s, r, spec)


func _moves_title(spec: Dictionary) -> String:
	if spec.get("from", -1) >= 0:
		return "Ridistribuisci i tuoi Caballeros da %s" % rname(spec["from"])
	if spec.get("single", false):
		return "Muovi fino a %d Caballeros da una sola regione" % spec["max"]
	if spec["foe"] == 0:
		return "Muovi fino a %d tuoi Caballeros" % spec["max"]
	if spec["own"] == 0:
		return "Muovi fino a %d Caballeros avversari" % spec["max"]
	if spec["own"] < spec["max"]:
		return "Muovi fino a %d tuoi e %d avversari" % [spec["own"], spec["foe"]]
	return "Muovi fino a %d Caballeros qualsiasi" % spec["max"]


## Controlla e applica una lista di spostamenti; restituisce quanti ne ha applicati.
func _apply_moves(s: int, r, spec: Dictionary) -> int:
	var lst: Array = r if r is Array else []
	var done := 0
	var own := 0
	var foe := 0
	var src := -1
	var parts := []
	for mv in lst:
		if not (mv is Array) or mv.size() < 3:
			continue
		var a := int(mv[0])
		var b := int(mv[1])
		var p := int(mv[2])
		if done >= int(spec["max"]):
			break
		if not move_ok(s, spec, a, b, p, own, foe, src):
			continue
		cab[a][p] -= 1
		cab[b][p] += 1
		flow(p, a, b, 1)
		done += 1
		if p == s:
			own += 1
		else:
			foe += 1
		src = a
		parts.append("%s %s→%s" % [players[p]["name"], rname(a), rname(b) if not (b == CAS and castillo_hidden) else "Castillo"])
	if done > 0:
		log_msg("%s muove: %s." % [pname(s), ", ".join(parts)])
	else:
		log_msg("%s non muove nessun Caballero." % pname(s))
	return done


## Regioni da cui si possono spostare Caballeros e dove si possono portare.
func move_sources() -> Array:
	return free_regions()


func move_dests() -> Array:
	var out := free_regions()
	out.append(CAS)
	return out


## Uno spostamento singolo è valido? (own/foe = già mossi, src = regione d'origine già usata)
func move_ok(s: int, spec: Dictionary, a: int, b: int, p: int, own: int, foe: int, src: int) -> bool:
	if a == b or not (a in move_sources()) or not (b in move_dests()):
		return false
	if p < 0 or p >= n or cab[a][p] <= 0:
		return false
	var fr := int(spec.get("from", -1))
	if fr >= 0 and a != fr:
		return false
	if spec.get("single", false) and src >= 0 and a != src:
		return false
	if p == s and own >= int(spec["own"]):
		return false
	if p != s and foe >= int(spec["foe"]):
		return false
	return true


func _all_own(s: int) -> void:
	var allowed := _own_sources(s, false)
	var r := await pick_region(s, "allown", "Da quale regione muovi tutti i tuoi Caballeros?", allowed)
	if r < 0:
		return
	var q: int = cab[r][s]
	await _moves(s, {"max": q, "own": q, "foe": 0, "from": r})


func _exile(s: int, two: bool) -> void:
	var picks := {}
	for k in range(1, n):
		var o := (s + k) % n
		var allowed := []
		for r in free_regions():
			if cab[r][o] >= (2 if two else 1):
				allowed.append(r)
		if two and allowed.is_empty():
			allowed = _own_sources(o, false)
		if allowed.is_empty():
			continue
		var title := "Scegli in segreto la regione da cui ritiri %s" % ("2 Caballeros" if two else "tutti i tuoi Caballeros")
		picks[o] = await pick_region(o, "exile", title, allowed, false, {"secret": true, "two": two})
	for o in picks:
		var r: int = picks[o]
		var q: int = mini(2, cab[r][o]) if two else cab[r][o]
		cab[r][o] -= q
		prov[o] += q
		flow(o, r, "prov", q)
		log_msg("%s rimanda %d Caballeros da %s alle province." % [pname(o), q, rname(r)])
	if not picks.is_empty():
		fx.emit("discs", {"picks": picks})


func _one_each(s: int) -> void:
	for k in n:
		var o := (s + k) % n
		var allowed := _own_sources(o, false)
		if allowed.is_empty():
			continue
		var r := await pick_region(s, "one_each", "Da quale regione togli 1 Caballero %s?" % ("tuo" if o == s else "di " + pname(o)), allowed, false, {"victim": o})
		if r < 0:
			continue
		cab[r][o] -= 1
		prov[o] += 1
		flow(o, r, "prov", 1)
		log_msg("%s rimanda 1 Caballero di %s da %s alle province." % [pname(s), pname(o), rname(r)])
		changed.emit()


# ================================================================ Grandissimo: azioni extra

## Inizio turno: Caballeros regalati dal Giullare, sbarco dalla nave, Re in incognito.
func _turn_start_grandissimo(s: int) -> void:
	while gifts.has(s) and not gifts[s].is_empty():
		var giver: int = gifts[s][0]
		var r := await pick_region(s, "jester_place", "Il Giullare: dove metti il Caballero di %s?" % pname(giver), free_regions(), false, {"giver": giver})
		gifts[s].pop_front()
		if r >= 0:
			cab[r][giver] += 1
			flow(giver, "prov", r, 1)
			log_msg("%s mette il Caballero regalato da %s in %s." % [pname(s), pname(giver), rname(r)])
		else:
			prov[giver] += 1
	gifts.erase(s)
	if cab[SHIP][s] > 0:
		var coast := []
		for r in D.COASTAL:
			if r in map_regions() and not taboo(r):
				coast.append(r)
		var r := await pick_region(s, "disembark", "Nave: i tuoi %d Caballeros sbarcano? Scegli una regione costiera" % cab[SHIP][s], coast, true)
		if r >= 0:
			var q: int = cab[SHIP][s]
			cab[SHIP][s] = 0
			cab[r][s] += q
			flow(s, SHIP, r, q)
			log_msg("%s sbarca %d Caballeros in %s." % [pname(s), q, rname(r)])
	if incognito.has(s):
		var r: int = incognito[s]
		if not taboo(r) and await yesno(s, "incognito_reveal", "Re in incognito: riveli %s e ci metti il Re?" % rname(r), {"region": r}, "Non ancora", "Sì, rivela"):
			incognito.erase(s)
			log_msg("%s rivela il Re in incognito." % pname(s))
			_move_king(r)
	changed.emit()


## Simboli della carta: nave (prendi un gettone nave) e prigione (un Caballero in prigione).
func _symbols(s: int, ci: int) -> void:
	var sym: String = card(ci).get("sym", "")
	if sym == "ship" and not ship_holder(s):
		var free := ships.find(-1)
		if free >= 0:
			if await yesno(s, "ship_take", "Simbolo nave: prendi un gettone nave?", {"card": ci}, "No", "Prendi la nave"):
				ships[free] = s
				log_msg("%s prende un gettone nave." % pname(s))
		else:
			var owners := []
			for o in ships:
				if o != s and not (o in owners):
					owners.append(o)
			var o := await pick_player(s, "ship_steal", "Simbolo nave: a chi prendi il gettone nave?", owners, true)
			if o >= 0:
				ships[ships.find(o)] = s
				log_msg("%s prende il gettone nave a %s." % [pname(s), pname(o)])
	elif sym == "jail":
		var regs := []
		for r in free_regions():
			if total_in(r) > 0:
				regs.append(r)
		var r := await pick_region(s, "jail", "Simbolo prigione: da quale regione mandi un Caballero in prigione?", regs, true)
		if r >= 0:
			var cands := []
			for t in n:
				if cab[r][t] > 0:
					cands.append(t)
			var v := await pick_player(s, "jail_victim", "Di chi è il Caballero che va in prigione?", cands, false, {"region": r})
			if v >= 0:
				cab[r][v] -= 1
				cab[JAIL][v] += 1
				flow(v, r, JAIL, 1)
				log_msg("%s manda in prigione un Caballero di %s da %s." % [pname(s), pname(v), rname(r)])
	# la carta del Re libera i prigionieri
	if ci == D.KING_CARD and total_in(JAIL) > 0:
		var r := await pick_region(s, "pardon", "Grazia del Re: dove liberi tutti i prigionieri? (oppure restano in prigione)", free_regions(), true)
		if r >= 0:
			for t in n:
				var q: int = cab[JAIL][t]
				if q > 0:
					cab[JAIL][t] = 0
					cab[r][t] += q
					flow(t, JAIL, r, q)
			log_msg("%s concede la grazia: i prigionieri vanno in %s." % [pname(s), rname(r)])
	changed.emit()


## Fine turno: Regina, Giullare, Grande Inquisitore e carte tenute col Doppio turno.
func _turn_end_grandissimo(s: int) -> void:
	if queen == s:
		var opts := [{"label": "Niente"}]
		if court[s] > 0 and not place_targets().is_empty():
			opts.append({"label": "Un Caballero dalla corte a una regione vicina al Re", "k": "place"})
		if prov[s] > 0:
			opts.append({"label": "Un Caballero dalle province alla corte", "k": "court"})
		if opts.size() > 1:
			var i := await pick(s, "queen", "La Regina: cosa fai?", opts)
			match str(opts[i].get("k", "")):
				"place":
					await _place(s, 1, [], "queen")
				"court":
					prov[s] -= 1
					court[s] += 1
					flow(s, "prov", "court", 1)
					log_msg("La Regina porta un Caballero di %s a corte." % pname(s))
	if jester == s and prov[s] > 0:
		var others := []
		for t in n:
			if t != s:
				others.append(t)
		var t := await pick_player(s, "jester", "Il Giullare: a chi regali un tuo Caballero delle province? (lo metterà lui sulla mappa)", others, true)
		if t >= 0:
			prov[s] -= 1
			if not gifts.has(t):
				gifts[t] = []
			gifts[t].append(s)
			log_msg("Il Giullare: %s regala un Caballero a %s, che lo metterà sulla mappa." % [pname(s), pname(t)])
	if inq_owner == s and inq_pos >= 0:
		var dests := []
		for a in adj(inq_pos):
			if not taboo(a):
				dests.append(a)
		var r := await pick_region(s, "inquisitor", "Grande Inquisitore: dove spingi i Caballeros neri? (regione confinante)", dests, true)
		if r >= 0:
			inq_pos = r
			log_msg("I Caballeros neri dell'Inquisitore entrano in %s." % rname(r))
			var victims := []
			for t in n:
				if t != s and cab[r][t] > 0:
					victims.append(t)
			var v := await pick_player(s, "inq_victim", "Grande Inquisitore: di chi è il Caballero che rimandi alle province?", victims, true, {"region": r})
			if v >= 0:
				cab[r][v] -= 1
				prov[v] += 1
				flow(v, r, "prov", 1)
				log_msg("L'Inquisitore rimanda alle province un Caballero di %s da %s." % [pname(v), rname(r)])
	if saved.has(s) and not saved[s].is_empty():
		for c2 in saved[s].duplicate():
			if await yesno(s, "use_saved", "Doppio turno: usi adesso «%s»?" % card(c2)["title"], {"card": c2}, "Più avanti", "Usala adesso"):
				saved[s].erase(c2)
				await _special(s, c2)
				await _symbols(s, c2)
		if saved[s].is_empty():
			saved.erase(s)
	changed.emit()


## Carta della 7ª pila: la Regina o il Giullare.
func _take_character(s: int) -> void:
	var opts := []
	var free_q := queen < 0
	var free_j := jester < 0
	if free_q or free_j:
		if free_q:
			opts.append({"label": "La Regina", "c": "q"})
		if free_j:
			opts.append({"label": "Il Giullare", "c": "j"})
	else:
		if queen != s:
			opts.append({"label": "La Regina (da %s)" % pname(queen), "c": "q"})
		if jester != s:
			opts.append({"label": "Il Giullare (da %s)" % pname(jester), "c": "j"})
	if opts.is_empty():
		return
	var i := 0
	if opts.size() > 1:
		i = await pick(s, "character", "7ª pila: chi prendi nella tua corte?", opts)
	if opts[i]["c"] == "q":
		queen = s
		log_msg("%s prende la Regina." % pname(s))
	else:
		jester = s
		log_msg("%s prende il Giullare." % pname(s))


# ================================================================ valutazioni

## Punti di una regione se fosse valutata adesso: {posto: punti}.
func region_points(r: int, first_only := false, cb: Array = []) -> Dictionary:
	var counts: Array = cb[r] if not cb.is_empty() else cab[r]
	return points_for(counts, vals(r), first_only, [r])


## Punti per un insieme di Caballeros (counts per posto) con i valori v. bonus_regs: regioni che
## danno il bonus del Re o del Grande a chi ha la maggioranza assoluta.
func points_for(counts: Array, v: Array, first_only := false, bonus_regs: Array = []) -> Dictionary:
	var np := 1 if first_only else npos()
	var lst := []
	for s in n:
		if counts[s] > 0:
			lst.append(s)
	lst.sort_custom(func(a, b): return counts[a] > counts[b])
	var out := {}
	var p := 0
	var i := 0
	while i < lst.size():
		var c: int = counts[lst[i]]
		var grp := [lst[i]]
		var j := i + 1
		while j < lst.size() and counts[lst[j]] == c:
			grp.append(lst[j])
			j += 1
		if p >= np:
			break
		var pts := 0
		if grp.size() == 1:
			pts = v[p]
			p += 1
		else:
			pts = v[p + 1] if p + 1 < np else 0
			p += 2
		for t in grp:
			if pts > 0:
				out[t] = pts
		i = j
	# bonus del Re e del Grande per chi ha la maggioranza assoluta
	if not bonus_regs.is_empty() and lst.size() > 0 and (lst.size() == 1 or counts[lst[0]] > counts[lst[1]]):
		var lead: int = lst[0]
		var bonus := 0
		if king in bonus_regs and king != CAS:
			bonus += 2
		if grande[lead] in bonus_regs:
			bonus += 2
		if bonus > 0:
			out[lead] = out.get(lead, 0) + bonus
	return out


func _add_points(pts: Dictionary, what: String, r := -1) -> void:
	var parts := []
	for s in pts:
		score[s] += pts[s]
		parts.append("%s +%d" % [pname(s), pts[s]])
	log_msg("Valutazione %s: %s." % [what, ", ".join(parts) if not parts.is_empty() else "nessun punto"])
	if r >= 0:
		last_scores.append([r, pts])
		if last_scores.size() > 30:
			last_scores.pop_front()
	fx.emit("score", {"r": r, "pts": pts})
	changed.emit()


func score_region(r: int, first_only := false) -> void:
	if r < 0:
		return
	_add_points(region_points(r, first_only), rname(r), r)


func _score_courts() -> void:
	_add_points(points_for(court, D.COURTS_VALS), "delle corti")


func general_scoring() -> void:
	phase = "scoring"
	log_msg("== Valutazione generale (dopo il round %d) ==" % cur_round)
	changed.emit()
	if grandissimo and inq_owner >= 0:
		log_msg("%s restituisce il Grande Inquisitore." % pname(inq_owner))
		inq_owner = -1
	# dischi segreti per chi ha Caballeros (o il Grande) nel Castillo; lo Spionaggio sceglie dopo
	var picks := {}
	var allowed := disk_regions()
	var spies := []
	for k in n:
		var s := (start_seat + k) % n
		if cab[CAS][s] > 0 or grande[s] == CAS:
			if espionage.has(s):
				spies.append(s)
				continue
			picks[s] = await pick_region(s, "castillo_dest", "Disco segreto: dove andranno i tuoi Caballeros del Castillo?", allowed, false, {"secret": true})
	score_region(CAS)
	var txt := _empty_castillo(picks)
	if not txt.is_empty():
		log_msg("Il Castillo si svuota — " + ", ".join(txt) + ".")
		fx.emit("discs", {"picks": picks})
	changed.emit()
	await pause_point({"kind": "castillo", "picks": picks, "title": "Il Castillo si svuota"})
	for s in spies:
		var r := await pick_region(s, "castillo_dest", "Spionaggio: dove porti i tuoi Caballeros del Castillo?", allowed, false, {"spy": true})
		var t2 := _empty_castillo({s: r})
		if not t2.is_empty():
			log_msg("Spionaggio — " + ", ".join(t2) + ".")
	espionage = {}
	# Scelta libera: 2 Caballeros propri prima della valutazione delle regioni
	for s in free_choice.keys():
		log_msg("%s usa la Scelta libera." % pname(s))
		await _moves(s, {"max": 2, "own": 2, "foe": 0})
	free_choice = {}
	var before := score.duplicate()
	var skip := {}
	for s in boycott:
		skip[boycott[s]] = true
		log_msg("Boicottaggio di %s: %s non riceve punti." % [pname(s), rname(boycott[s])])
	var done := {}
	for s in alliance:
		var pair: Array = alliance[s]
		var a: int = pair[0]
		var b: int = pair[1]
		done[a] = true
		done[b] = true
		if skip.has(a) or skip.has(b):
			continue
		var cnt := []
		for t in n:
			cnt.append(cab[a][t] + cab[b][t])
		var va := vals(a)
		var vb := vals(b)
		var vsum := [va[0] + vb[0], va[1] + vb[1], va[2] + vb[2]]
		_add_points(points_for(cnt, vsum, false, [a, b]), "dell'Alleanza %s + %s" % [rname(a), rname(b)], a)
	for r in map_regions():
		if skip.has(r) or done.has(r):
			continue
		score_region(r)
	boycott = {}
	alliance = {}
	if revolution >= 0:
		log_msg("Finita la rivoluzione: il Re torna in Portogallo.")
		revolution = -1
		king = POR
		fx.emit("king", {"r": king})
	var gains := []
	for s in n:
		gains.append(score[s] - before[s])
	await pause_point({"kind": "general", "gains": gains, "title": "Valutazione generale dopo il round %d" % cur_round})
	phase = "turn"
	changed.emit()


## Svuota il Castillo secondo i dischi: Caballeros (e Grande) nella regione scelta.
func _empty_castillo(picks: Dictionary) -> Array:
	var txt := []
	for s in picks:
		var t: int = picks[s]
		var q: int = cab[CAS][s]
		cab[CAS][s] = 0
		if grande[s] == CAS and t >= 0:
			grande[s] = t
		if q <= 0:
			continue
		flow(s, CAS, "court" if taboo(t) else t, q)
		if taboo(t) or t < 0:
			court[s] += q
		else:
			cab[t][s] += q
		txt.append("%s: %d in %s" % [pname(s), q, rname(t)])
	return txt


func _end_game() -> void:
	phase = "over"
	game_over = true
	var lst := range(n)
	lst.sort_custom(func(a, b): return score[a] > score[b])
	results = []
	for s in lst:
		results.append({"seat": s, "name": pname(s), "score": score[s], "color": players[s]["color"]})
	log_msg("Fine partita: vince %s con %d punti!" % [results[0]["name"], results[0]["score"]])
	changed.emit()
	game_ended.emit(results)


## Impronta dello stato (per verificare che due dispositivi online abbiano la stessa partita).
func fingerprint() -> String:
	return "%s|%s|%s|%s|%s|%d|%s|%s|%d|%d" % [str(score), str(cab), str(court), str(prov), str(grande), king, str(mobile), str(ships), queen, jester]
