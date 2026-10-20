class_name EGEngine
extends Node
## Motore delle regole di El Grande (gioco base), senza dipendenze dalla UI.
## Ogni scelta passa da `decide()`: l'IA risponde subito; per i giocatori umani viene emesso
## `decision_requested` e si attende `provide_decision()`. Online le scelte viaggiano nel registro di
## mosse (OnlineSession): con lo stesso seme ogni dispositivo ottiene la stessa partita.
##
## Regioni 0..8 come sul tabellone, 9 = Castillo.

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(results: Array)
signal fx(kind: String, data: Dictionary)
signal pause_requested(req: Dictionary)

const D = preload("res://scripts/data/eg_data.gd")
const CAS := 9

var rng := RandomNumberGenerator.new()
var ai_delay := 0.0
var headless := false
var ais := {}
var online = null
var abort := false
var pause_enabled := false

var players: Array = []          # {color, ai, name, level}
var n := 0
var cab: Array = []              # cab[regione][posto]
var court: Array = []
var prov: Array = []
var score: Array = []
var grande: Array = []
var king := 0
var mobile := [-1, -1]           # regione dei segna-punti mobili 8/4/0 e 4/0/0 (-1 fuori)
var hand: Array = []             # carte potere in mano
var discard: Array = []          # carte potere giocate (l'ultima è in cima)
var played: Array = []           # carta potere di questo round (0 = nessuna)
var order: Array = []            # ordine di turno del round
var start_seat := 0
var piles: Array = [[], [], [], []]
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
	var short := bool(config.get("short", false))
	rounds = [2, 3, 5, 6, 8, 9] if short else [1, 2, 3, 4, 5, 6, 7, 8, 9]
	cab = []
	for r in 10:
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
	# carte regione: la prima va al Re, poi una a testa per la regione di provenienza
	var regs := range(9)
	_shuffle(regs)
	king = regs[0]
	for s in n:
		grande[s] = regs[s + 1]
		cab[grande[s]][s] = 2
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


func pause_point(req: Dictionary) -> void:
	if headless or abort or not pause_enabled or not any_local_human():
		return
	if online != null and online.catchup:
		return
	pause_requested.emit(req)
	await decision_provided


# ================================================================ helper di stato

func total_in(r: int) -> int:
	var t := 0
	for s in n:
		t += cab[r][s]
	return t


## Regioni dove si possono togliere o aggiungere Caballeros (non quella del Re).
func free_regions() -> Array:
	var out := []
	for r in 9:
		if r != king:
			out.append(r)
	return out


func place_targets() -> Array:
	var out: Array = D.ADJ[king].duplicate()
	out.append(CAS)
	return out


func any_targets() -> Array:
	var out := free_regions()
	out.append(CAS)
	return out


func on_board(s: int) -> int:
	var t := 0
	for r in 10:
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


# ================================================================ partita

func run() -> void:
	log_msg("Il Re si trova in %s." % rname(king))
	for s in n:
		log_msg("%s: il Grande parte da %s." % [pname(s), rname(grande[s])])
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
	for s in n:
		played[s] = 0
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
	var avail := []
	for c in showing:
		if not taken.has(c):
			avail.append(c)
	var c = await decide(s, {"type": "action", "ctx": "action", "title": "Scegli una carta azione", "cards": avail})
	var ci := int(c) if (c is int or c is float) else -1
	if not (ci in avail):
		ci = avail[0]
	taken[ci] = s
	var cd := card(ci)
	log_msg("%s sceglie «%s» (pila %d)." % [pname(s), cd["title"], cd["pile"]])
	changed.emit()
	# 3/4. piazzamento e azione speciale, nell'ordine voluto
	var special_first := false
	if court[s] > 0 and cd["key"] != "veto":
		var o := await pick(s, "order", "Cosa fai prima?", [{"label": "Piazzo prima i Caballeros"}, {"label": "Prima l'azione speciale"}], {"card": ci})
		special_first = o == 1
	if special_first:
		await _special(s, ci)
		await _place(s, cd["pile"])
	else:
		await _place(s, cd["pile"])
		await _special(s, ci)
	changed.emit()


func _own_sources(s: int, with_court: bool) -> Array:
	var out := []
	for r in 9:
		if r != king and cab[r][s] > 0:
			out.append(r)
	if with_court and court[s] > 0:
		out.append(-1)
	return out


func _own_movable(s: int) -> int:
	var t := 0
	for r in 9:
		if r != king:
			t += cab[r][s]
	return t


## Toglie Caballeros propri: r = {sorgente: quanti} (sorgente -1 = corte). dest "court" o "prov".
func _apply_take(s: int, r, nmax: int, exact: bool, dest: String) -> int:
	var got := 0
	var d: Dictionary = r if r is Dictionary else {}
	for k in d:
		var src := int(k)
		var q := int(d[k])
		if q <= 0:
			continue
		var avail := 0
		if src == -1:
			avail = court[s]
		elif src >= 0 and src < 9 and src != king:
			avail = cab[src][s]
		q = mini(q, mini(avail, nmax - got))
		if q <= 0:
			continue
		if src == -1:
			court[s] -= q
		else:
			cab[src][s] -= q
		got += q
		if dest == "court":
			court[s] += q
		else:
			prov[s] += q
		flow(s, "court" if src == -1 else src, dest, q)
	if exact and got < nmax:
		# completa automaticamente (scelta non valida o incompleta)
		var srcs := _own_sources(s, dest == "prov")
		for src in srcs:
			while got < nmax:
				if src == -1 and court[s] > 0:
					court[s] -= 1
				elif src >= 0 and cab[src][s] > 0:
					cab[src][s] -= 1
				else:
					break
				got += 1
				if dest == "court":
					court[s] += 1
				else:
					prov[s] += 1
				flow(s, "court" if src == -1 else src, dest, 1)
	return got


## Piazzamento dalla corte: fino a k Caballeros nelle regioni confinanti col Re e/o nel Castillo.
func _place(s: int, k: int, targets: Array = [], ctx := "place") -> void:
	var q: int = mini(k, court[s])
	if q <= 0:
		return
	if targets.is_empty():
		targets = place_targets()
	var r = await decide(s, {"type": "place", "ctx": ctx, "title": "Piazza fino a %d Caballeros dalla corte" % q, "n": q, "targets": targets})
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
		court[s] -= m
		flow(s, "court", t, m)
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
	if not _special_possible(s, key):
		return
	var yes := await pick(s, "do", "Eseguire l'azione «%s»?" % cd["title"], [{"label": "Non eseguire"}, {"label": "Esegui"}], {"card": ci})
	if yes == 0:
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
			var allowed := range(10)
			var r := await pick_region(s, "score_any", "Scegli la regione da valutare", allowed)
			score_region(r)
		"score4", "score5", "score67":
			var want: Array = {"score4": [4], "score5": [5], "score67": [6, 7]}[key]
			var any := false
			for r in 9:
				if int(vals(r)[0]) in want:
					score_region(r)
					any = true
			if not any:
				log_msg("Nessuna regione da valutare.")
		"score_most", "score_least":
			var best := []
			var bv := -1 if key == "score_most" else 999
			for r in 9:
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
			for r in 9:
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
			var r := await pick_region(s, "mobile_dest", "Dove metti il segna-punti %s?" % D.MOBILE_NAME[m], _mobile_targets(m), false, {"m": m})
			if r < 0:
				return
			mobile[m] = r
			log_msg("%s mette il segna-punti %s in %s." % [pname(s), D.MOBILE_NAME[m], rname(r)])
		"court_plus2":
			var q := mini(2, prov[s])
			prov[s] -= q
			court[s] += q
			flow(s, "prov", "court", q)
			log_msg("%s porta %d Caballeros dalle province alla corte." % [pname(s), q])
		"advisor":
			var r := await pick_region(s, "advisor", "Editto reale: muovi il Re in una regione confinante", D.ADJ[king].duplicate())
			_move_king(r)
		"king":
			var allowed := range(9)
			var r := await pick_region(s, "king", "Metti il Re in una regione qualunque", allowed)
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
					dest[o] = await pick_region(o, "evict_dest", "Espulsione: dove sposti i tuoi %d Caballeros da %s?" % [cab[r][o], rname(r)], range(9), false, {"secret": true, "from": r})
			for o in dest:
				var q: int = cab[r][o]
				cab[r][o] = 0
				var t: int = dest[o]
				flow(o, r, "court" if (t == king or t == r) else t, q)
				if t == king or t == r:
					court[o] += q
					log_msg("%s riporta %d Caballeros a corte." % [pname(o), q])
				else:
					cab[t][o] += q
					log_msg("%s sposta %d Caballeros in %s." % [pname(o), q, rname(t)])
		"grande":
			if grande[s] == king:
				log_msg("Il Grande di %s è nella regione del Re e non può muoversi." % pname(s))
				return
			var allowed := []
			for r in free_regions():
				if r != grande[s]:
					allowed.append(r)
			var r := await pick_region(s, "grande", "Sposta il tuo Grande", allowed, true)
			if r >= 0:
				grande[s] = r
				log_msg("%s sposta il Grande in %s." % [pname(s), rname(r)])
	changed.emit()


func _special_possible(s: int, key: String) -> bool:
	match key:
		"powerback":
			return not discard[s].is_empty()
		"grande":
			return grande[s] != king
		"mobile":
			return not _mobile_options().is_empty()
		"allown":
			return _own_movable(s) > 0
		"court2":
			return court[s] > 0
		"court_plus2":
			return prov[s] > 0
	return true


func _mobile_options() -> Array:
	var out := []
	for m in 2:
		for r in _mobile_targets(m):
			out.append([m, r])
	return out


func _mobile_targets(m: int) -> Array:
	var out := []
	if mobile[m] == king and mobile[m] >= 0:
		return out
	for r in range(10):
		if r == king or r == mobile[0] or r == mobile[1]:
			continue
		out.append(r)
	return out


func _move_king(r: int) -> void:
	if r < 0 or r > 8:
		return
	king = r
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


## Uno spostamento singolo è valido? (own/foe = già mossi, src = regione d'origine già usata)
func move_ok(s: int, spec: Dictionary, a: int, b: int, p: int, own: int, foe: int, src: int) -> bool:
	if a < 0 or a > 8 or b < 0 or b > 9 or a == b or a == king or b == king:
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


# ================================================================ valutazioni

## Punti di una regione se fosse valutata adesso: {posto: punti}.
func region_points(r: int, first_only := false, cb: Array = []) -> Dictionary:
	var counts: Array = cb[r] if not cb.is_empty() else cab[r]
	var v := vals(r)
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
	if r < 9 and lst.size() > 0 and (lst.size() == 1 or counts[lst[0]] > counts[lst[1]]):
		var lead: int = lst[0]
		var bonus := 0
		if r == king:
			bonus += 2
		if grande[lead] == r:
			bonus += 2
		if bonus > 0:
			out[lead] = out.get(lead, 0) + bonus
	return out


func score_region(r: int, first_only := false) -> void:
	if r < 0:
		return
	var pts := region_points(r, first_only)
	var parts := []
	for s in pts:
		score[s] += pts[s]
		parts.append("%s +%d" % [pname(s), pts[s]])
	last_scores.append([r, pts])
	if last_scores.size() > 30:
		last_scores.pop_front()
	log_msg("Valutazione %s: %s." % [rname(r), ", ".join(parts) if not parts.is_empty() else "nessun punto"])
	fx.emit("score", {"r": r, "pts": pts})
	changed.emit()


func general_scoring() -> void:
	phase = "scoring"
	log_msg("== Valutazione generale (dopo il round %d) ==" % cur_round)
	changed.emit()
	# dischi segreti per chi ha Caballeros nel Castillo
	var picks := {}
	var allowed := []
	for r in 9:
		if r != king:
			allowed.append(r)
	for k in n:
		var s := (start_seat + k) % n
		if cab[CAS][s] > 0:
			picks[s] = await pick_region(s, "castillo_dest", "Disco segreto: dove andranno i tuoi Caballeros del Castillo?", allowed, false, {"secret": true})
	score_region(CAS)
	var txt := []
	for s in picks:
		var q: int = cab[CAS][s]
		cab[CAS][s] = 0
		var t: int = picks[s]
		flow(s, CAS, "court" if t == king else t, q)
		if t == king:
			court[s] += q
		else:
			cab[t][s] += q
		txt.append("%s: %d in %s" % [pname(s), q, rname(t)])
	if not txt.is_empty():
		log_msg("Il Castillo si svuota — " + ", ".join(txt) + ".")
		fx.emit("discs", {"picks": picks})
	changed.emit()
	await pause_point({"kind": "castillo", "picks": picks, "title": "Il Castillo si svuota"})
	var before := score.duplicate()
	for r in 9:
		score_region(r)
	var gains := []
	for s in n:
		gains.append(score[s] - before[s])
	await pause_point({"kind": "general", "gains": gains, "title": "Valutazione generale dopo il round %d" % cur_round})
	phase = "turn"
	changed.emit()


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
	return "%s|%s|%s|%s|%s|%d|%s" % [str(score), str(cab), str(court), str(prov), str(grande), king, str(mobile)]
