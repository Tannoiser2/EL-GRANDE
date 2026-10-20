class_name EGAI
extends RefCounted
## Giocatore artificiale di El Grande.
## Valuta la posizione come "punti che farei se tutto venisse valutato adesso", confrontati con
## quelli degli avversari, più il punteggio già fatto e i Caballeros a corte. Per ogni scelta simula
## le alternative sullo stato del motore (modificandolo e poi ripristinandolo: le decisioni dell'IA
## sono sincrone, quindi nessuno vede gli stati intermedi).

const D = preload("res://scripts/data/eg_data.gd")
const CAS := 9

var level := 1
var exp := ""                    # varianti sperimentali (solo per i test)
var rng := RandomNumberGenerator.new()
var me := 0
var eng: EGEngine


func _init(lvl := 1, seed_val := 0) -> void:
	level = lvl
	rng.seed = seed_val if seed_val != 0 else randi()


func decide(e: EGEngine, s: int, req: Dictionary):
	eng = e
	me = s
	_prepare()
	match req["type"]:
		"power":
			return _power(req)
		"action":
			return _action(req)
		"place":
			return _place(req["n"], req["targets"], -1, req.get("from_prov", false))
		"moves":
			return _moves(req["spec"])
		"take":
			return _take(req)
		"region":
			return _region(req)
		"pick":
			return _pick(req)
		"deck":
			return _deck(req)
		"ik_power":
			return _ik_power(req)
	return 0


# ================================================================ valutazione

func _noise() -> float:
	return [1.6, 0.5, 0.0][clampi(level, 0, 2)] * (rng.randf() - 0.5)


## Peso delle maggioranze sul tabellone rispetto ai punti già fatti: più è lontana la prossima
## valutazione generale, meno le posizioni attuali sono sicure.
var wb := 1.0
var regs: Array = []             # regioni della mappa che si valutano
var regs_cas: Array = []         # le stesse più il Castillo
## Valore di un Caballero a corte (cala verso la fine: a fine partita non serve più).
var wc := 0.32
var om := 0.55


func _prepare() -> void:
	regs = eng.map_regions()
	regs_cas = regs.duplicate()
	regs_cas.append(CAS)
	var rem := 0
	var k := 9
	for x in [3, 6, 9]:
		if eng.cur_round <= x:
			k = x
			break
	for r in eng.rounds:
		if r > eng.cur_round and r <= k:
			rem += 1
	wb = 1.0 / (1.0 + P("tw", 0.25) * rem)
	var left := 0
	for r in eng.rounds:
		if r > eng.cur_round:
			left += 1
	wc = P("cw", 0.32) * clampf(left / 2.0, 0.0, 1.0)
	om = P("om", 0.55)


func _oth(pts: Dictionary, p: int) -> float:
	var omax := 0.0
	var osum := 0.0
	for t in eng.n:
		if t == p:
			continue
		var v: float = pts.get(t, 0)
		omax = maxf(omax, v)
		osum += v
	return omax if eng.n == 2 else om * omax + (1.0 - om) * osum / float(eng.n - 1)


## Contributo di una regione per il giocatore p (punti miei meno quelli degli avversari).
func region_term(r: int, p: int) -> float:
	var pts := eng.region_points(r)
	var mine: float = pts.get(p, 0)
	var val := mine - _oth(pts, p)
	# solidità del vantaggio: un margine largo resiste agli intrighi
	var c: Array = eng.cab[r]
	var best_o := 0
	for t in eng.n:
		if t != p:
			best_o = maxi(best_o, c[t])
	var margin: int = c[p] - best_o
	if c[p] > 0:
		val += P("mg", 0.12) * clampf(margin, -3, 3) * float(eng.vals(r)[0]) / 5.0
	if eng.colonie and (r == eng.AME or r == eng.MED) and c[p] > 0:
		var free: int = c[p] - eng.carried(p, r)
		var dv: float = eng.discs[r]["gold"] * 6.0 + eng.discs[r]["wares"] * 4.0
		if free > 0 and dv > 0:
			val += 0.35 * minf(dv, free * 6.0)
	if r == CAS:
		val += P("cas", 0.2) * c[p]
		if c[p] > 0 and P("casr", 0.8) > 0.0:
			val += P("casr", 0.8) * _redeploy(p, c[p])
	return val * wb


## Quanto renderebbero i q Caballeros di p nel Castillo, spostati nella regione migliore.
func _redeploy(p: int, q: int) -> float:
	var best := 0.0
	for r in eng.disk_regions():
		var pts0 := eng.region_points(r)
		var b0: float = pts0.get(p, 0) - _oth(pts0, p)
		eng.cab[r][p] += q
		var pts1 := eng.region_points(r)
		var b1: float = pts1.get(p, 0) - _oth(pts1, p)
		eng.cab[r][p] -= q
		best = maxf(best, b1 - b0)
	return best


func global_term(p: int) -> float:
	var v: float = eng.score[p] + wc * eng.court[p] + 0.04 * eng.prov[p]
	if eng.colonie:
		v += 0.5 * _cargo(p)
	var omax := -999.0
	var osum := 0.0
	for t in eng.n:
		if t == p:
			continue
		var w: float = eng.score[t] + wc * 0.8 * eng.court[t]
		omax = maxf(omax, w)
		osum += w
	var oth := omax if eng.n == 2 else om * omax + (1.0 - om) * osum / float(eng.n - 1)
	return v - oth


## Valore dei dischi d'oro e di merci che p sta portando.
func _cargo(p: int) -> float:
	var t := 0.0
	for r in eng.carry[p]:
		t += eng.carry[p][r]["gold"] * 6.0 + eng.carry[p][r]["wares"] * 4.0
	return t


func evaluate(p: int) -> float:
	var t := global_term(p)
	for r in regs_cas:
		t += region_term(r, p)
	return t


func snap() -> Dictionary:
	return {"cab": eng.cab.duplicate(true), "court": eng.court.duplicate(), "prov": eng.prov.duplicate(),
		"score": eng.score.duplicate(), "grande": eng.grande.duplicate(), "king": eng.king,
		"mobile": eng.mobile.duplicate(), "hand": eng.hand.duplicate(true), "discard": eng.discard.duplicate(true),
		"inq_pos": eng.inq_pos, "revolution": eng.revolution, "inq_owner": eng.inq_owner, "black": eng.black.duplicate(),
		"limit_r": eng.limit_r, "lim_on": eng.lim_on.duplicate()}


func restore(sn: Dictionary) -> void:
	eng.cab = sn["cab"].duplicate(true)
	eng.court = sn["court"].duplicate()
	eng.prov = sn["prov"].duplicate()
	eng.score = sn["score"].duplicate()
	eng.grande = sn["grande"].duplicate()
	eng.king = sn["king"]
	eng.mobile = sn["mobile"].duplicate()
	eng.hand = sn["hand"].duplicate(true)
	eng.discard = sn["discard"].duplicate(true)
	eng.inq_pos = sn["inq_pos"]
	eng.revolution = sn["revolution"]
	eng.inq_owner = sn["inq_owner"]
	eng.black = sn["black"].duplicate()
	eng.limit_r = sn["limit_r"]
	eng.lim_on = sn["lim_on"].duplicate()


# ================================================================ piazzamento

## Piazzamento goloso, un Caballero alla volta: {regione: quanti}.
func _place(q: int, targets: Array, p := -1, from_prov := false) -> Dictionary:
	if p < 0:
		p = me
	var out := {}
	if from_prov:
		# si simula portando prima i Caballeros a corte
		var k := mini(q, eng.prov[p])
		eng.prov[p] -= k
		eng.court[p] += k
		var d := _place(k, targets, p)
		eng.prov[p] += k
		eng.court[p] -= k
		return d
	q = mini(q, eng.court[p])
	for i in q:
		var best := -1
		var bv := -INF
		for t in targets:
			var before := region_term(t, p)
			eng.cab[t][p] += 1
			var v := region_term(t, p) - before + _noise() * 0.5
			eng.cab[t][p] -= 1
			if v > bv:
				bv = v
				best = t
		if best < 0:
			break
		# un Caballero a corte vale qualcosa: si piazza solo se serve
		if bv < 0.15 and i > 0 and eng.court[p] - i > 3:
			break
		eng.cab[best][p] += 1
		eng.court[p] -= 1
		out[best] = out.get(best, 0) + 1
	for t in out:
		eng.cab[t][p] -= out[t]
		eng.court[p] += out[t]
	return out


func _apply_place(d: Dictionary, p: int) -> void:
	for t in d:
		eng.cab[t][p] += d[t]
		eng.court[p] -= d[t]


# ================================================================ spostamenti

## Spostamenti golosi: ogni passo è il miglior singolo spostamento (variazione locale delle due regioni).
func _moves(spec: Dictionary, p := -1, apply := false) -> Array:
	if p < 0:
		p = me
	var out := []
	var own := 0
	var foe := 0
	var src := -1
	var used := {}
	var cargo_moved := {}
	for step in int(spec["max"]):
		var best = null
		var bv := 0.05
		# le due regioni cambiano indipendentemente: si calcolano a parte il togliere e l'aggiungere
		var base := {}
		var srcs: Array = eng.move_sources(spec)
		var dests: Array = eng.move_dests(spec)
		for r in dests:
			base[r] = region_term(r, p)
		for r in srcs:
			if not base.has(r):
				base[r] = region_term(r, p)
		var add := {}
		for q in eng.n:
			if (q == p and own >= int(spec["own"])) or (q != p and foe >= int(spec["foe"])):
				continue
			var row := {}
			for b in dests:
				eng.cab[b][q] += 1
				row[b] = region_term(b, p) - base[b]
				eng.cab[b][q] -= 1
			add[q] = row
		for a in srcs:
			for q in eng.n:
				if eng.cab[a][q] <= 0 or not add.has(q):
					continue
				if not _src_ok(p, spec, a, q, own, foe, src):
					continue
				if spec.has("caps") and spec["caps"].has(a) and int(used.get(a, 0)) >= int(spec["caps"][a]):
					continue
				var cargo: bool = eng.colonie and q == p and eng.carried(p, a) - int(cargo_moved.get(a, 0)) > 0
				eng.cab[a][q] -= 1
				var da: float = region_term(a, p) - base[a]
				eng.cab[a][q] += 1
				var row: Dictionary = add[q]
				for b in dests:
					if b == a:
						continue
					if spec.has("to") and b != int(spec["to"]):
						continue
					if eng.room(b) <= 0:
						continue
					var v: float = da + row[b] + _noise() * 0.3
					if cargo:
						if b < 9 and not eng.taboo(b):
							v += 5.0
						elif b == eng.SHIPC:
							v += 2.5
						elif b == CAS:
							v -= 5.0
					if v > bv:
						bv = v
						best = [a, b, q]
		if best == null:
			break
		eng.cab[best[0]][best[2]] -= 1
		eng.cab[best[1]][best[2]] += 1
		used[best[0]] = int(used.get(best[0], 0)) + 1
		if eng.colonie and best[2] == p and eng.carried(p, best[0]) - int(cargo_moved.get(best[0], 0)) > 0:
			cargo_moved[best[0]] = int(cargo_moved.get(best[0], 0)) + 1
		out.append(best)
		if best[2] == p:
			own += 1
		else:
			foe += 1
		src = best[0]
	if not apply:
		for i in range(out.size() - 1, -1, -1):
			var m: Array = out[i]
			eng.cab[m[1]][m[2]] -= 1
			eng.cab[m[0]][m[2]] += 1
	return out


func _src_ok(p: int, spec: Dictionary, a: int, q: int, own: int, foe: int, src: int) -> bool:
	var fr := int(spec.get("from", -1))
	if fr >= 0 and a != fr:
		return false
	if spec.get("single", false) and src >= 0 and a != src:
		return false
	if q == p and own >= int(spec["own"]):
		return false
	if q != p and foe >= int(spec["foe"]):
		return false
	return true


# ================================================================ togliere Caballeros

## Sceglie i Caballeros meno utili da togliere (corte = -1). exact: quanti esattamente.
func _take(req: Dictionary) -> Dictionary:
	var q: int = req["n"]
	var exact: bool = req.get("exact", false)
	var out := {}
	var srcs: Array = req["sources"]
	for i in q:
		var best := -99
		var bv := -INF
		for sidx in srcs:
			var src := int(sidx)
			var avail: int = eng.court[me] if src == -1 else eng.cab[src][me]
			if avail - out.get(src, 0) <= 0:
				continue
			var v := 0.0
			if src == -1:
				v = -0.32
			else:
				var before := region_term(src, me)
				eng.cab[src][me] -= 1 + out.get(src, 0)
				v = region_term(src, me) - before
				eng.cab[src][me] += 1 + out.get(src, 0)
				if req["ctx"] == "fill":
					v += 0.32
			if v > bv:
				bv = v
				best = src
		if best == -99:
			break
		if not exact and bv < -0.25:
			break
		out[best] = out.get(best, 0) + 1
	return out


# ================================================================ scelte su regioni

func _region(req: Dictionary) -> int:
	var allowed: Array = req["allowed"]
	var ctx: String = req["ctx"]
	var best: int = allowed[0]
	var bv := -INF
	var sn := snap()
	if req.get("skip", false):
		best = -1
		bv = evaluate(me)
	for r in allowed:
		var v := _region_value(ctx, r, req) + _noise()
		restore(sn)
		if v > bv:
			bv = v
			best = r
	restore(sn)
	return best


## Valore della posizione dopo aver scelto la regione r nel contesto ctx (lo stato viene ripristinato fuori).
func _region_value(ctx: String, r: int, req: Dictionary) -> float:
	match ctx:
		"score_any", "secret_score":
			var pts := eng.region_points(r)
			var v := _gain_value(pts, me)
			if ctx == "secret_score":
				# gli altri sceglieranno probabilmente la regione migliore per loro: meglio evitarla
				for t in eng.n:
					if t != me and _best_score_region(t) == r:
						v -= 2.0
			return v
		"advisor", "king":
			eng.king = r
			if eng.revolution >= 0:
				eng.grande[eng.revolution] = r
			return evaluate(me) + 0.15 * _adj_potential(r)
		"grande":
			eng.grande[me] = r
			return evaluate(me)
		"mobile_dest":
			eng.mobile[int(req["m"])] = r
			return evaluate(me)
		"castillo_dest", "evict_dest":
			var q: int = eng.cab[CAS][me] if ctx == "castillo_dest" else eng.cab[int(req.get("from", 0))][me]
			if ctx == "evict_dest":
				eng.cab[int(req["from"])][me] = 0
			else:
				eng.cab[CAS][me] = 0
			if ctx == "castillo_dest" and eng.grande[me] == CAS:
				eng.grande[me] = r
			if eng.taboo(r) or (ctx == "evict_dest" and r == int(req["from"])):
				eng.court[me] += q
			else:
				eng.cab[r][me] += q
			return evaluate(me)
		"storm":
			var victim := int(req["victim"])
			eng.cab[r][victim] -= 1
			eng.cab[CAS][victim] += 1
			return evaluate(me)
		"incognito":
			return _region_value("king", r, req) - 0.3
		"boycott":
			# si toglie la regione dove gli avversari guadagnerebbero di più
			return -_gain_value(eng.region_points(r), me)
		"alliance":
			var best := -INF
			for b in eng.region_cards_free():
				if b != r:
					best = maxf(best, _alliance_gain(r, b))
			return best
		"alliance2":
			return _alliance_gain(int(req["first"]), r)
		"disembark":
			var q: int = eng.cab[eng.SHIP][me]
			eng.cab[eng.SHIP][me] = 0
			eng.cab[r][me] += q
			return evaluate(me)
		"jester_place":
			eng.cab[r][int(req["giver"])] += 1
			return evaluate(me)
		"jail", "inquisitor":
			var best := -INF
			for t in eng.n:
				if t == me or eng.cab[r][t] <= 0:
					continue
				eng.cab[r][t] -= 1
				best = maxf(best, evaluate(me))
				eng.cab[r][t] += 1
			return best if best > -INF else evaluate(me) - 1.0
		"pardon":
			for t in eng.n:
				eng.cab[r][t] += eng.cab[eng.JAIL][t]
				eng.cab[eng.JAIL][t] = 0
			return evaluate(me)
		"col_start":
			if eng.taboo(r):
				return evaluate(me) - 2.0
			eng.cab[r][me] += 2
			eng.court[me] -= 2
			return evaluate(me)
		"black_src":
			return _black_value(r)
		"black_dst":
			var a0 := int(req.get("from", -1))
			if a0 >= 0:
				eng.black[a0] = int(eng.black.get(a0, 0)) - 1
			eng.black[r] = int(eng.black.get(r, 0)) + 1
			return evaluate(me)
		"col_limit":
			eng.limit_r = r
			for t in eng.n:
				eng.lim_on[t] = 0
			eng.lim_on = eng._limit_counts(me)
			return evaluate(me)
		"col_later":
			return evaluate(me) + 0.7 * _gain_value(eng.region_points(r), me)
		"ik_start", "reserve_deploy":
			if eng.room(r) <= 0:
				return -INF
			eng.cab[r][me] += 1
			if ctx == "ik_start":
				eng.court[me] -= 1
			var v := evaluate(me)
			return v if ctx == "ik_start" or v > evaluate(me) else v
		"grande_move":
			if eng.grande[me] >= 0 and eng.grande[me] != CAS and not eng.taboo(eng.grande[me]):
				eng.grande[me] = r
			_moves({"max": 3, "own": 3, "foe": 0, "to": r}, me, true)
			return evaluate(me)
		"take6":
			# conviene dove sono in testa (blocca gli altri)
			var c: Array = eng.cab[r]
			var best_o := 0
			for t in eng.n:
				if t != me:
					best_o = maxi(best_o, c[t])
			return float(c[me] - best_o) * float(eng.vals(r)[0]) / 5.0
		"quarantine", "protection":
			# si protegge una regione dove si è in vantaggio
			return _gain_value(eng.region_points(r), me)
		"double_region":
			return _gain_value(eng.region_points(r), me)
		"score_purge", "score_three_pick":
			return _gain_value(eng.region_points(r), me)
		"score_three":
			# le regioni meno buone per l'avversario che deciderà: si scelgono quelle buone per me
			return _gain_value(eng.region_points(r), me) - (5.0 if r in req.get("chosen", []) else 0.0)
		"bridge_a", "bridge_b":
			var t := 0.0
			for b in eng.adj(r):
				t = maxf(t, float(eng.cab[r][me] + eng.cab[b][me]))
			return t + (0.0 if ctx == "bridge_a" else float(eng.cab[r][me]))
		"intrigue_src":
			var best := -INF
			var sn := snap()
			if eng.cab[r][me] > 0:
				_moves({"max": eng.cab[r][me], "own": eng.cab[r][me], "foe": 0, "from": r}, me, true)
				best = evaluate(me)
				restore(sn)
			if eng.total_in(r) - eng.cab[r][me] > 0:
				_moves({"max": 1, "own": 0, "foe": 1, "from": r}, me, true)
				best = maxf(best, evaluate(me))
				restore(sn)
			return best
		"exile":
			var two: bool = req.get("two", false)
			var q: int = mini(2, eng.cab[r][me]) if two else eng.cab[r][me]
			eng.cab[r][me] -= q
			eng.prov[me] += q
			return evaluate(me)
		"one_each":
			var victim := int(req["victim"])
			eng.cab[r][victim] -= 1
			eng.prov[victim] += 1
			return evaluate(me)
		"allown":
			var q: int = eng.cab[r][me]
			var spec := {"max": q, "own": q, "foe": 0, "from": r}
			_moves(spec, me, true)
			return evaluate(me)
		"evict":
			_sim_evict(r)
			return evaluate(me)
	return evaluate(me)


## Quanto guadagno (rispetto agli altri) se a e b si valutano insieme invece che separate.
func _alliance_gain(a: int, b: int) -> float:
	var cnt := []
	for t in eng.n:
		cnt.append(eng.cab[a][t] + eng.cab[b][t])
	var va := eng.vals(a)
	var vb := eng.vals(b)
	var comb := eng.points_for(cnt, [va[0] + vb[0], va[1] + vb[1], va[2] + vb[2]], false, [a, b])
	var sep := eng.region_points(a)
	var pb := eng.region_points(b)
	for t in pb:
		sep[t] = sep.get(t, 0) + pb[t]
	return _gain_value(comb, me) - _gain_value(sep, me)


func _gain_value(pts: Dictionary, p: int) -> float:
	var mine: float = pts.get(p, 0)
	var omax := 0.0
	var osum := 0.0
	for t in eng.n:
		if t != p:
			omax = maxf(omax, pts.get(t, 0))
			osum += pts.get(t, 0)
	if eng.n == 2:
		return mine - omax
	return mine - (0.55 * omax + 0.45 * osum / float(eng.n - 1))


func _best_score_region(p: int) -> int:
	var best := 0
	var bv := -INF
	for r in regs:
		var v := _gain_value(eng.region_points(r), p)
		if v > bv:
			bv = v
			best = r
	return best


## Quanto è utile, per il piazzamento futuro, che il Re stia in r (regioni confinanti dove conviene entrare).
func _adj_potential(r: int) -> float:
	var t := 0.0
	for a in eng.adj(r):
		var before := region_term(a, me)
		eng.cab[a][me] += 1
		t = maxf(t, region_term(a, me) - before)
		eng.cab[a][me] -= 1
	return t


## Simula lo sgombero di r: ogni avversario sposta i suoi Caballeros dove conviene a lui.
func _sim_evict(r: int) -> void:
	for t in eng.n:
		if t == me or eng.cab[r][t] <= 0:
			continue
		var q: int = eng.cab[r][t]
		eng.cab[r][t] = 0
		var best := -1
		var bv := -INF
		for d in regs:
			if d == r or eng.taboo(d):
				continue
			eng.cab[d][t] += q
			var v := region_term(d, t)
			eng.cab[d][t] -= q
			if v > bv:
				bv = v
				best = d
		if best >= 0:
			eng.cab[best][t] += q
		else:
			eng.court[t] += q


# ================================================================ scelte fra opzioni

## Valore di togliere un Caballero nero da a (dove andrà lo decide _region con black_dst).
func _black_value(a: int) -> float:
	var best := -INF
	for b in eng.free_regions():
		if b == a or b == eng.FRA:
			continue
		eng.black[a] = int(eng.black.get(a, 0)) - 1
		eng.black[b] = int(eng.black.get(b, 0)) + 1
		best = maxf(best, evaluate(me))
		eng.black[b] -= 1
		eng.black[a] += 1
	return best


func _pick(req: Dictionary) -> int:
	var ctx: String = req["ctx"]
	var opts: Array = req["options"]
	match ctx:
		"col_choice":
			var best := 0
			var bv := -INF
			for i in opts.size():
				var sn := snap()
				var c: int = opts[i]["c"]
				var k: int = D.card_n(c) if i > 0 else int(eng.cab_card[me])
				_apply_place(_place(k, eng.place_targets(me)), me)
				var v := maxf(evaluate(me), _special_value(c)) + _noise()
				restore(sn)
				if v > bv:
					bv = v
					best = i
			return best
		"use_doppel":
			var sn := snap()
			var base := evaluate(me)
			var v := _special_value(int(req["card"]))
			restore(sn)
			return 1 if v > base + 1.5 else 0
		"use_remove":
			# toglie la carta che più servirebbe a chi sta per scegliere
			var actor := int(req["actor"])
			var saved_me := me
			me = actor
			var base := evaluate(actor)
			var vals := []
			for i in opts.size():
				if i == 0:
					vals.append(0.0)
					continue
				vals.append(_plan(int(opts[i]["c"]))["value"] - base)
			me = saved_me
			var best := 0
			var bv := 3.0
			var sorted := vals.duplicate()
			sorted.sort()
			for i in range(1, opts.size()):
				var second: float = sorted[sorted.size() - 2] if vals[i] == sorted.back() else sorted.back()
				var d: float = vals[i] - second
				if d > bv:
					bv = d
					best = i
			return best
		"order":
			return 1 if _plan(int(req["card"]))["special_first"] else 0
		"do":
			var sn := snap()
			var base := evaluate(me)
			var v := _special_value(int(req["card"]))
			restore(sn)
			return 1 if v > base + 0.05 else 0
		"veto":
			# veto se l'azione dell'avversario mi costa parecchio
			var actor := int(req["actor"])
			var sn := snap()
			var base := evaluate(me)
			var saved_me := me
			me = actor
			_special_value(int(req["card"]))
			me = saved_me
			var after := evaluate(me)
			restore(sn)
			var loss := base - after
			return 1 if loss > (2.5 if level >= 1 else 4.0) else 0
		"c2oa":
			var sn := snap()
			_apply_place(_place(2, eng.any_targets()), me)
			var a := evaluate(me)
			restore(sn)
			var b := -INF
			var srcs := []
			for r in regs:
				if not eng.taboo(r) and eng.cab[r][me] > 0:
					srcs.append(r)
			for r in srcs:
				b = maxf(b, _region_value("allown", r, {}))
				restore(sn)
			return 0 if a >= b else 1
		"mobile":
			var sn := snap()
			var best := 0
			var bv := -INF
			for i in opts.size():
				var m := int(opts[i]["m"])
				for r in eng._mobile_targets(m):
					eng.mobile[m] = r
					var v := evaluate(me) + _noise()
					restore(sn)
					if v > bv:
						bv = v
						best = i
			return best
		"powerback":
			var best := 0
			for i in opts.size():
				if int(opts[i]["v"]) > int(opts[best]["v"]):
					best = i
			return best
		"last_word", "ship_take":
			return 1
		"double_now", "use_saved":
			var sn := snap()
			var base := evaluate(me)
			var v := _special_value(int(req["card"]))
			restore(sn)
			var last: bool = eng.round_i >= eng.rounds.size() - 1
			return 1 if (v > base + 0.6 or last) else 0
		"incognito_reveal":
			var sn := snap()
			var base := evaluate(me)
			var v := _region_value("king", int(req["region"]), req)
			restore(sn)
			return 1 if v > base + 0.6 else 0
		"revolution", "jail_victim", "inq_victim":
			var sn := snap()
			var best := 0
			var bv := -INF
			for i in opts.size():
				var t := int(opts[i]["p"])
				var v := evaluate(me) - 0.01
				if t >= 0:
					if ctx == "revolution":
						eng.king = eng.grande[t]
						eng.revolution = t
					elif ctx == "jail_victim" or ctx == "inq_victim":
						var r := int(req["region"])
						eng.cab[r][t] -= 1
					v = evaluate(me) + (-3.0 if t == me else 0.0)
				restore(sn)
				if v > bv:
					bv = v
					best = i
			return best
		"character":
			for i in opts.size():
				if opts[i]["c"] == "q":
					return i
			return 0
		"queen":
			for i in opts.size():
				if str(opts[i].get("k", "")) == "place":
					return i
			return opts.size() - 1
		"jester":
			# lo regala a chi ha meno punti (lo piazzerà dove mi danneggia di meno)
			var best := opts.size() - 1
			var low := 999
			for i in opts.size():
				var t := int(opts[i]["p"])
				if t >= 0 and eng.score[t] < low:
					low = eng.score[t]
					best = i
			return best
		"ship_steal":
			return 0
		"ik_which":
			var sn := snap()
			var a := _special_value(int(req["card"]))
			restore(sn)
			var b := _special_value(int(req["card2"]))
			restore(sn)
			return 0 if a >= b else 1
		"intrigue_mode":
			var r := int(req["region"])
			var sn := snap()
			_moves({"max": eng.cab[r][me], "own": eng.cab[r][me], "foe": 0, "from": r}, me, true)
			var a := evaluate(me)
			restore(sn)
			_moves({"max": 1, "own": 0, "foe": 1, "from": r}, me, true)
			var b := evaluate(me)
			restore(sn)
			return 0 if a >= b else 1
		"remove_faceup":
			# toglie una carta avversaria
			for i in opts.size():
				var o: Dictionary = opts[i]
				if int(o["r"]) >= 0 and eng.limit6[int(o["r"])] != me:
					return i
				if int(o["s"]) >= 0 and int(o["s"]) != me:
					return i
			return 0
		"score_three_who":
			# chi deve scegliere: quello con meno punti (sceglierà la regione migliore per sé)
			var best := 0
			var low := 99999
			for i in opts.size():
				var t := int(opts[i]["p"])
				if eng.score[t] < low:
					low = eng.score[t]
					best = i
			return best
	return 0


# ================================================================ carte azione

## Valore dell'azione speciale per `me`, applicata allo stato (che resta modificato).
func _special_value(ci: int) -> float:
	var key: String = D.CARDS[ci]["key"]
	if eng.colonie and not (key in ["col_remove", "col_doppel"]):
		var g: int = mini(int(D.CARDS[ci].get("gold", 0)), eng.supply["gold"])
		var w: int = mini(int(D.CARDS[ci].get("wares", 0)), eng.supply["wares"])
		var fa: int = eng.cab[eng.AME][me] - eng.carried(me, eng.AME) - (1 if eng.viceroy == me else 0)
		var fm: int = eng.cab[eng.MED][me] - eng.carried(me, eng.MED)
		eng.score[me] += 0.5 * (mini(g, maxi(fa, 0)) * 6.0 + mini(w, maxi(fm, 0)) * 4.0)
	match key:
		"own4":
			_moves({"max": 4, "own": 4, "foe": 0}, me, true)
		"any3":
			_moves({"max": 3, "own": 3, "foe": 3}, me, true)
		"any4":
			_moves({"max": 4, "own": 4, "foe": 4}, me, true)
		"foe3":
			_moves({"max": 3, "own": 0, "foe": 3}, me, true)
		"own2foe2":
			_moves({"max": 4, "own": 2, "foe": 2}, me, true)
		"five1":
			_moves({"max": 5, "own": 5, "foe": 5, "single": true}, me, true)
		"court2":
			_apply_place(_place(2, eng.any_targets()), me)
		"allown", "court2_or_all":
			var sn := snap()
			var best := -INF
			var best_sn := sn
			if key == "court2_or_all":
				_apply_place(_place(2, eng.any_targets()), me)
				best = evaluate(me)
				best_sn = snap()
				restore(sn)
			for r in regs:
				if eng.taboo(r) or eng.cab[r][me] <= 0:
					continue
				var v := _region_value("allown", r, {})
				if v > best:
					best = v
					best_sn = snap()
				restore(sn)
			restore(best_sn)
		"exile_all", "remove2":
			for t in eng.n:
				if t == me:
					continue
				# l'avversario sacrifica la regione che gli costa meno
				var best := -1
				var bv := -INF
				for r in regs:
					if eng.taboo(r) or eng.cab[r][t] < (2 if key == "remove2" else 1):
						continue
					var q: int = mini(2, eng.cab[r][t]) if key == "remove2" else eng.cab[r][t]
					var before := region_term(r, t)
					eng.cab[r][t] -= q
					var v := region_term(r, t) - before
					eng.cab[r][t] += q
					if v > bv:
						bv = v
						best = r
				if best >= 0:
					var q2: int = mini(2, eng.cab[best][t]) if key == "remove2" else eng.cab[best][t]
					eng.cab[best][t] -= q2
					eng.prov[t] += q2
		"one_each":
			for t in eng.n:
				var best := -1
				var bv := -INF
				for r in regs:
					if eng.taboo(r) or eng.cab[r][t] <= 0:
						continue
					eng.cab[r][t] -= 1
					var v := evaluate(me)
					eng.cab[r][t] += 1
					if v > bv:
						bv = v
						best = r
				if best >= 0:
					eng.cab[best][t] -= 1
					eng.prov[t] += 1
		"decay3", "decay_all":
			for t in eng.n:
				if t != me:
					var q: int = eng.court[t] if key == "decay_all" else mini(3, eng.court[t])
					eng.court[t] -= q
					eng.prov[t] += q
		"king_returns":
			for t in eng.n:
				if t == me:
					continue
				var q := 3
				var c := mini(q, eng.court[t])
				eng.court[t] -= c
				eng.prov[t] += c
				q -= c
				while q > 0:
					var best := -1
					var bv := -INF
					for r in regs:
						if eng.taboo(r) or eng.cab[r][t] <= 0:
							continue
						var before := region_term(r, t)
						eng.cab[r][t] -= 1
						var v := region_term(r, t) - before
						eng.cab[r][t] += 1
						if v > bv:
							bv = v
							best = r
					if best < 0:
						break
					eng.cab[best][t] -= 1
					eng.prov[t] += 1
					q -= 1
		"score_any":
			var best := 0
			var bv := -INF
			for r in regs_cas:
				var v := _gain_value(eng.region_points(r), me)
				if v > bv:
					bv = v
					best = r
			_sim_score(best)
		"score4", "score5", "score67":
			var want: Array = {"score4": [4], "score5": [5], "score67": [6, 7]}[key]
			for r in regs:
				if int(eng.vals(r)[0]) in want:
					_sim_score(r)
		"score_most", "score_least":
			var best := []
			var bv := -1 if key == "score_most" else 999
			for r in regs:
				var t := eng.total_in(r)
				if key == "score_least" and t == 0:
					continue
				if (key == "score_most" and t > bv) or (key == "score_least" and t < bv):
					bv = t
					best = [r]
				elif t == bv:
					best.append(r)
			for r in best:
				_sim_score(r)
		"score_first":
			for r in regs:
				_sim_score(r, true)
		"score_castillo":
			_sim_score(CAS)
		"score_secret":
			var r := _best_score_region(me)
			var pts := eng.region_points(r)
			for t in pts:
				eng.score[t] += pts[t] * 0.5
		"mobile":
			var best := []
			var bv := -INF
			var sn := snap()
			for m in 2:
				for r in eng._mobile_targets(m):
					eng.mobile[m] = r
					var v := evaluate(me)
					restore(sn)
					if v > bv:
						bv = v
						best = [m, r]
			if not best.is_empty():
				eng.mobile[best[0]] = best[1]
		"court_plus2":
			var q := mini(2, eng.prov[me])
			eng.prov[me] -= q
			eng.court[me] += q
		"advisor", "king":
			var allowed: Array = eng.adj(eng.king) if key == "advisor" else eng.king_regions()
			var sn := snap()
			var best: int = eng.king
			var bv := -INF
			for r in allowed:
				var v := _region_value("king", r, {})
				restore(sn)
				if v > bv:
					bv = v
					best = r
			eng.king = best
			if eng.revolution >= 0:
				eng.grande[eng.revolution] = best
		"powerback":
			if not eng.discard[me].is_empty():
				eng.score[me] += 1.2
		"evict":
			var sn := snap()
			var best := -1
			var bv := -INF
			for r in regs:
				if eng.taboo(r):
					continue
				var has := false
				for t in eng.n:
					if t != me and eng.cab[r][t] > 0:
						has = true
				if not has:
					continue
				_sim_evict(r)
				var v := evaluate(me)
				restore(sn)
				if v > bv:
					bv = v
					best = r
			if best >= 0:
				_sim_evict(best)
		"grande":
			if eng.grande[me] != eng.king:
				var sn := snap()
				var best: int = eng.grande[me]
				var bv := evaluate(me)
				for r in regs:
					if eng.taboo(r):
						continue
					eng.grande[me] = r
					var v := evaluate(me)
					restore(sn)
					if v > bv:
						bv = v
						best = r
				eng.grande[me] = best
		"veto":
			eng.score[me] += 1.0
		"score_inland":
			for r in D.INLAND:
				_sim_score(r)
		"score_coastal":
			for r in D.COASTAL:
				if r in regs:
					_sim_score(r)
		"score_courts":
			var pts := eng.points_for(eng.court, D.COURTS_VALS)
			for t in pts:
				eng.score[t] += pts[t]
		"evict_castillo":
			for t in eng.n:
				if t != me:
					eng.court[t] += eng.cab[CAS][t]
					eng.cab[CAS][t] = 0
		"conspiracy":
			for t in eng.n:
				if t != me and eng.grande[t] >= 0 and eng.grande[t] != CAS and not eng.taboo(eng.grande[t]):
					eng.grande[t] = CAS
		"col_gi":
			eng.inq_owner = me
			for j in 2:
				var best_a := -1
				var bv := evaluate(me) + 0.1
				for r in eng.black.keys():
					if eng.black[r] > 0 and not eng.taboo(r):
						var v := _black_value(r)
						if v > bv:
							bv = v
							best_a = r
				if best_a < 0:
					break
				var best_b := -1
				var bb := -INF
				for b in eng.free_regions():
					if b == best_a or b == eng.FRA:
						continue
					eng.black[best_a] -= 1
					eng.black[b] = int(eng.black.get(b, 0)) + 1
					var v2 := evaluate(me)
					eng.black[b] -= 1
					eng.black[best_a] += 1
					if v2 > bb:
						bb = v2
						best_b = b
				eng.black[best_a] -= 1
				eng.black[best_b] = int(eng.black.get(best_b, 0)) + 1
			eng.score[me] += 1.0
		"col_limit":
			var sn := snap()
			var best := eng.limit_r
			var bv := evaluate(me)
			for r in eng.free_regions():
				if r == eng.FRA or r == eng.limit_r:
					continue
				var v := _region_value("col_limit", r, {})
				restore(sn)
				if v > bv:
					bv = v
					best = r
			eng.limit_r = best
			eng.lim_on = eng._limit_counts(me)
		"col_remove":
			eng.score[me] += 1.0
		"col_doppel":
			eng.score[me] += 1.3
		"col_transport":
			_moves({"max": 3, "own": 3, "foe": 0}, me, true)
		"col_score_new":
			for r in [eng.FRA, eng.SHIPC, eng.AME, eng.MED]:
				_sim_score(r)
		"col_score_gi":
			eng.inq_owner = me
			for r in eng.black.keys():
				if eng.black[r] > 0:
					_sim_score(r)
		"col_score_later":
			var bv := 0.0
			for r in eng.map_regions():
				bv = maxf(bv, _gain_value(eng.region_points(r), me))
			eng.score[me] += 0.7 * bv
		"storm":
			for t in eng.n:
				if t == me:
					continue
				for j in 2:
					var best := -1
					var bv := -INF
					for r in regs:
						if eng.taboo(r) or eng.cab[r][t] <= 0:
							continue
						eng.cab[r][t] -= 1
						var v := evaluate(me)
						eng.cab[r][t] += 1
						if v > bv:
							bv = v
							best = r
					if best >= 0:
						eng.cab[best][t] -= 1
						eng.cab[CAS][t] += 1
			var q := mini(2, eng.court[me])
			eng.court[me] -= q
			eng.cab[CAS][me] += q
		"double_swap":
			for m in 2:
				var sn := snap()
				var best: int = eng.mobile[m]
				var bv := evaluate(me)
				for r in eng._mobile_targets(m):
					eng.mobile[m] = r
					var v := evaluate(me)
					restore(sn)
					if v > bv:
						bv = v
						best = r
				eng.mobile[m] = best
		"revolution":
			var sn := snap()
			var best := -1
			var bv := evaluate(me)
			for t in eng.n:
				if eng.grande[t] < 0 or eng.grande[t] == CAS:
					continue
				eng.king = eng.grande[t]
				var v := evaluate(me)
				restore(sn)
				if v > bv:
					bv = v
					best = t
			if best >= 0:
				eng.king = eng.grande[best]
				eng.revolution = best
		"alliance":
			var best := 0.0
			var fr := eng.region_cards_free()
			for i in fr.size():
				for j in range(i + 1, fr.size()):
					best = maxf(best, _alliance_gain(fr[i], fr[j]))
			eng.score[me] += best * 0.7
		"boycott":
			var best := 0.0
			for r in eng.region_cards_free():
				best = maxf(best, -_gain_value(eng.region_points(r), me))
			eng.score[me] += best * 0.6
		"gi_take":
			eng.score[me] += 1.6
		"incognito":
			eng.score[me] += 1.0
		"espionage":
			eng.score[me] += 0.4 + 0.3 * eng.cab[CAS][me]
		"free_choice":
			eng.score[me] += 1.2
		"stop":
			var pos := eng.order.find(me)
			eng.score[me] += 0.8 * maxi(0, eng.order.size() - 1 - pos)
		"double_turn":
			var base := evaluate(me)
			var best := 0.0
			for c in eng._available_cards():
				if D.CARDS[c]["key"] == "double_turn":
					continue
				var sn := snap()
				best = maxf(best, _special_value(c) - base)
				restore(sn)
			eng.score[me] += best
		"queen_jester":
			eng.score[me] += 1.4
		"ik_intrigue", "ik_intrigue_card":
			var sn := snap()
			var best := evaluate(me)
			var best_sn := sn
			for r in regs:
				if eng.taboo(r) or eng.total_in(r) == 0:
					continue
				var v := _region_value("intrigue_src", r, {})
				restore(sn)
				if v > best:
					best = v
					var mine: int = eng.cab[r][me]
					var sn2 := snap()
					if mine > 0:
						_moves({"max": mine, "own": mine, "foe": 0, "from": r}, me, true)
					var va := evaluate(me)
					var sa := snap()
					restore(sn2)
					_moves({"max": 1, "own": 0, "foe": 1, "from": r}, me, true)
					if va >= evaluate(me):
						best_sn = sa
					else:
						best_sn = snap()
					restore(sn)
			restore(best_sn)
		"ik_king", "ik_king_card":
			var sn := snap()
			var best: int = eng.king
			var bv := evaluate(me)
			for r in eng.king_regions():
				var v := _region_value("king", r, {})
				restore(sn)
				if v > bv:
					bv = v
					best = r
			eng.king = best
		"bridge":
			eng.score[me] += 1.6
		"take6":
			eng.score[me] += 0.4
		"one_each_other":
			for t in eng.n:
				if t == me:
					continue
				var best := -1
				var bv := -INF
				for r in regs:
					if eng.taboo(r) or eng.cab[r][t] <= 0:
						continue
					eng.cab[r][t] -= 1
					var v := evaluate(me)
					eng.cab[r][t] += 1
					if v > bv:
						bv = v
						best = r
				if best >= 0:
					eng.cab[best][t] -= 1
					eng.prov[t] += 1
		"reserve":
			eng.score[me] += 1.0
		"grande_move":
			var sn := snap()
			var best_sn := sn
			var bv := evaluate(me)
			for r in regs:
				if eng.taboo(r):
					continue
				var v := _region_value("grande_move", r, {})
				if v > bv:
					bv = v
					best_sn = snap()
				restore(sn)
			restore(best_sn)
		"quarantine", "protection":
			eng.score[me] += 0.8
		"remove_faceup":
			eng.score[me] += 0.3
		"double_region":
			var best := 0.0
			for r in eng.region_cards_free():
				best = maxf(best, _gain_value(eng.region_points(r), me))
			eng.score[me] += best * 0.6
		"score_two":
			var best := -INF
			var br := -1
			for r in regs:
				if eng.cab[r][me] != 2:
					continue
				var v := _gain_value(eng.region_points(r), me)
				if v > best:
					best = v
					br = r
			if br >= 0:
				_sim_score(br)
		"score_purge":
			var best := -INF
			var br := -1
			for r in regs:
				if eng.taboo(r):
					continue
				var v := _gain_value(eng.region_points(r), me)
				if v > best:
					best = v
					br = r
			if br >= 0:
				_sim_score(br)
				for t in eng.n:
					eng.prov[t] += eng.cab[br][t]
					eng.cab[br][t] = 0
		"score_three":
			eng.score[me] += 1.0
		"score_secret2":
			eng.score[me] += 0.5
	return evaluate(me)


func _sim_score(r: int, first_only := false) -> void:
	var pts := eng.region_points(r, first_only)
	for t in pts:
		eng.score[t] += pts[t]


## Piano completo per una carta: valore, ordine (azione prima o dopo il piazzamento).
func _plan(ci: int) -> Dictionary:
	var pile: int = D.card_n(ci)
	if eng.intrigo:
		pile = 5 if D.CARDS[ci]["key"] == "fiesta" else eng.cab_card[me]
	var fp: bool = D.CARDS[ci]["key"] == "province"
	if fp:
		return {"value": _province_value(pile), "special_first": false}
	var sn := snap()
	# piazzamento poi azione
	_apply_place(_place(pile, eng.place_targets(me)), me)
	var base1 := evaluate(me)
	var a := maxf(base1, _special_value(ci))
	restore(sn)
	# azione poi piazzamento
	var b := -INF
	if eng.court[me] > 0:
		var base2 := evaluate(me)
		b = maxf(base2, _special_value(ci))
		_apply_place(_place(pile, eng.place_targets(me)), me)
		b = maxf(b, evaluate(me))
		restore(sn)
	return {"value": maxf(a, b), "special_first": b > a + 0.01}


func _province_value(k: int) -> float:
	var sn := snap()
	var q := mini(k, eng.prov[me])
	eng.prov[me] -= q
	eng.court[me] += q
	_apply_place(_place(q, eng.place_targets(me)), me)
	# quelli non piazzati tornano nelle province
	var back: int = mini(q, eng.court[me])
	eng.court[me] -= back
	eng.prov[me] += back
	var v := evaluate(me)
	restore(sn)
	return v


## Esegue sullo stato il piano migliore per la carta ci (lo stato resta modificato).
func _apply_plan(ci: int) -> void:
	var pile: int = D.card_n(ci)
	var pl := _plan(ci)
	if pl["special_first"]:
		var b0 := evaluate(me)
		var sn := snap()
		var v := _special_value(ci)
		if v < b0:
			restore(sn)
		_apply_place(_place(pile, eng.place_targets(me)), me)
	else:
		_apply_place(_place(pile, eng.place_targets(me)), me)
		var b1 := evaluate(me)
		var sn2 := snap()
		var v2 := _special_value(ci)
		if v2 < b1:
			restore(sn2)


## Valore della carta ci tenendo conto delle risposte di chi gioca dopo di me in questo round:
## ognuno prende la carta rimasta migliore per sé e la gioca al meglio.
func _lookahead(ci: int, cards: Array) -> float:
	var sn := snap()
	var saved := me
	_apply_plan(ci)
	var avail := cards.duplicate()
	avail.erase(ci)
	var pos := eng.order.find(saved)
	if pos >= 0:
		for k in range(pos + 1, mini(eng.order.size(), pos + 1 + int(P("lah", 4)))):
			if avail.is_empty():
				break
			var t: int = eng.order[k]
			me = t
			var q: int = mini(D.POWER_CAB[eng.played[t]], eng.prov[t])
			eng.prov[t] -= q
			eng.court[t] += q
			var bc: int = avail[0]
			var bv := -INF
			for c in avail:
				var v: float = _plan(c)["value"]
				if v > bv:
					bv = v
					bc = c
			avail.erase(bc)
			_apply_plan(bc)
	me = saved
	var out := evaluate(me)
	restore(sn)
	return out


func _action(req: Dictionary) -> int:
	var cards: Array = req["cards"]
	var vals := {}
	for c in cards:
		vals[c] = _plan(c)["value"] + _noise()
	var la := P("la", 0.5) if level >= 2 else 0.0
	if la > 0.0 and cards.size() > 1 and eng.order.find(me) < eng.order.size() - 1:
		# solo le carte più promettenti, per non rallentare troppo
		var ranked := cards.duplicate()
		ranked.sort_custom(func(x, y): return vals[x] > vals[y])
		var top: Array = ranked.slice(0, int(P("lak", 3)))
		var la_vals := {}
		var la_max := -INF
		for c in top:
			la_vals[c] = _lookahead(c, cards)
			la_max = maxf(la_max, la_vals[c])
		for c in cards:
			if la_vals.has(c):
				vals[c] = (1.0 - la) * vals[c] + la * la_vals[c]
			else:
				vals[c] = -INF
	var best: int = cards[0]
	var bv := -INF
	for c in cards:
		if vals[c] > bv:
			bv = vals[c]
			best = c
	return best


# ================================================================ Intrigo & il Re

func _deck(req: Dictionary) -> Array:
	if OS.get_environment("EG_RANDDECK") == "1":
		# solo per i test: mazzo a caso, per provare tutte le carte
		var all := D.ik_cards()
		for i in range(all.size() - 1, 0, -1):
			var j := rng.randi() % (i + 1)
			var t = all[i]
			all[i] = all[j]
			all[j] = t
		return all.slice(0, 13)
	var vals: Array = D.IK_SUGGESTED.duplicate()
	if level == 0:
		# un po' di varietà
		var alt := [15, 25, 35, 40, 70, 80, 90, 110, 130, 145]
		for k in 3:
			vals[1 + rng.randi() % (vals.size() - 1)] = alt[rng.randi() % alt.size()]
	var out := []
	for v in vals:
		var ci := D.ik_by_val(v)
		if ci >= 0 and not (ci in out):
			out.append(ci)
	for ci in D.ik_cards():
		if out.size() >= 13:
			break
		if not (ci in out):
			out.append(ci)
	return out


## Valore di giocare la carta ci arrivando in posizione rank (0 = la più alta del round).
func _ik_value(ci: int, rank: int) -> float:
	var sn := snap()
	var cabs: Array = D.IK_CAB[clampi(eng.n, 2, 5)]
	var k: int = cabs[clampi(rank, 0, cabs.size() - 1)]
	var pc: int = mini(int(D.CARDS[ci].get("pc", 0)), eng.prov[me])
	eng.prov[me] -= pc
	eng.court[me] += pc
	var act := ci
	if rank == 0:
		act = D.IK_KING
	elif rank >= eng.n - 1:
		act = D.IK_INTRIGUE
	var key: String = D.CARDS[act]["key"]
	if key == "fiesta":
		k = 5
	var targets: Array = eng.any_targets() if key == "anywhere" else eng.place_targets(me)
	_apply_place(_place(k, targets), me)
	var base := evaluate(me)
	var v := maxf(base, _special_value(act)) if not D.CARDS[act].get("may", false) else maxf(base, _special_value(act))
	if not D.CARDS[act].get("may", true):
		v = _special_value(act)
	restore(sn)
	return v


func _ik_power(req: Dictionary) -> int:
	var legal: Array = req["legal"]
	var used: Array = req["used"]
	var waiting := []
	for t in eng.n:
		if t != me and eng.ik_played[t] < 0:
			waiting.append(t)
	var rounds_left: int = eng.rounds.size() - eng.round_i
	var avg := 0.0
	for c in eng.hand[me]:
		avg += eng.ik_val(c)
	avg /= maxf(1.0, eng.hand[me].size())
	var best: int = legal[0]
	var bv := -INF
	for ci in legal:
		var v := eng.ik_val(ci)
		var u := 0.0
		if v == 0:
			# il Jolly: sceglie dopo, quindi vale la carta migliore della mano, con un piccolo premio
			if req["ctx"] == "joker":
				continue
			u = 0.6 + (1.5 if eng.hand[me].size() > rounds_left else -3.0)
		else:
			var k := 0.0
			for w in used:
				if w > v:
					k += 1.0
			for t in waiting:
				var hi := 0
				var tot := 0
				for h in eng.hand[t]:
					if eng.ik_val(h) in used:
						continue
					tot += 1
					if eng.ik_val(h) > v:
						hi += 1
				k += float(hi) / maxf(1.0, tot)
			var rank := clampi(int(round(k)), 0, eng.n - 1)
			u = _ik_value(ci, rank) - evaluate(me)
			# le carte alte servono anche dopo
			var spare: int = eng.hand[me].size() - rounds_left
			u -= P("ikk", 0.012) * (float(v) - avg) * (1.0 if spare < 2 else 0.5)
		u += _noise() * 1.5
		if u > bv:
			bv = u
			best = ci
	return best


# ================================================================ carte potere

func P(k: String, d: float) -> float:
	var v := d
	for part in exp.split(","):
		if part.begins_with(k + "="):
			v = float(part.substr(k.length() + 1))
	return v


func _power(req: Dictionary) -> int:
	var legal: Array = req["legal"]
	if exp == "randpower":
		return legal[rng.randi() % legal.size()]
	var used: Array = req["used"]
	# valore delle carte azione scoperte per me, dalla migliore
	var base := evaluate(me)
	var cv := []
	var court0: int = eng.court[me]
	for c in eng.showing:
		cv.append(_plan(c)["value"] - base)
	cv.sort()
	cv.reverse()
	# chi deve ancora giocare
	var waiting := []
	for t in eng.n:
		if t != me and eng.played[t] == 0:
			waiting.append(t)
	var rounds_left: int = eng.rounds.size() - eng.round_i
	var best: int = legal[0]
	var bv := -INF
	for v in legal:
		var k := 0.0
		for u in used:
			if u >= v:
				k += 1.0
		for t in waiting:
			var hi := 0
			var tot := 0
			for h in eng.hand[t]:
				if h in used:
					continue
				tot += 1
				if h > v:
					hi += 1
			k += float(hi) / maxf(1.0, tot)
		var ki := clampi(int(round(k)), 0, cv.size() - 1)
		var pos_val: float = cv[ki]
		var cabs: int = mini(D.POWER_CAB[v], eng.prov[me])
		var nd := 0.75 if court0 < 4 else (0.45 if court0 < 8 else 0.2)
		var cab_val := cabs * nd
		var avg := 0.0
		for h in eng.hand[me]:
			avg += h
		avg /= maxf(1.0, eng.hand[me].size())
		var conserve := P("pk", 0.25) * (float(v) - avg)
		var u := P("pa", 1.0) * pos_val + P("pc", 1.0) * cab_val - conserve + _noise() * 2.0
		if u > bv:
			bv = u
			best = v
	return best
