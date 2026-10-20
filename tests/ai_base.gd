class_name EGAIBase
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
	match req["type"]:
		"power":
			return _power(req)
		"action":
			return _action(req)
		"place":
			return _place(req["n"], req["targets"])
		"moves":
			return _moves(req["spec"])
		"take":
			return _take(req)
		"region":
			return _region(req)
		"pick":
			return _pick(req)
	return 0


# ================================================================ valutazione

func _noise() -> float:
	return [1.6, 0.5, 0.0][clampi(level, 0, 2)] * (rng.randf() - 0.5)


## Contributo di una regione per il giocatore p (punti miei meno quelli degli avversari).
func region_term(r: int, p: int) -> float:
	var pts := eng.region_points(r)
	var mine: float = pts.get(p, 0)
	var omax := 0.0
	var osum := 0.0
	for t in eng.n:
		if t == p:
			continue
		var v: float = pts.get(t, 0)
		omax = maxf(omax, v)
		osum += v
	var oth := omax if eng.n == 2 else 0.55 * omax + 0.45 * osum / float(eng.n - 1)
	var val := mine - oth
	# solidità del vantaggio: un margine largo resiste agli intrighi
	var c: Array = eng.cab[r]
	var best_o := 0
	for t in eng.n:
		if t != p:
			best_o = maxi(best_o, c[t])
	var margin: int = c[p] - best_o
	if c[p] > 0:
		val += 0.12 * clampf(margin, -3, 3) * float(eng.vals(r)[0]) / 5.0
	if r == CAS:
		val += 0.35 * c[p]
	return val


func global_term(p: int) -> float:
	var v: float = eng.score[p] + 0.32 * eng.court[p] + 0.04 * eng.prov[p]
	var omax := -999.0
	var osum := 0.0
	for t in eng.n:
		if t == p:
			continue
		var w: float = eng.score[t] + 0.25 * eng.court[t]
		omax = maxf(omax, w)
		osum += w
	var oth := omax if eng.n == 2 else 0.55 * omax + 0.45 * osum / float(eng.n - 1)
	return v - oth


func evaluate(p: int) -> float:
	var t := global_term(p)
	for r in 10:
		t += region_term(r, p)
	return t


func snap() -> Dictionary:
	return {"cab": eng.cab.duplicate(true), "court": eng.court.duplicate(), "prov": eng.prov.duplicate(),
		"score": eng.score.duplicate(), "grande": eng.grande.duplicate(), "king": eng.king,
		"mobile": eng.mobile.duplicate(), "hand": eng.hand.duplicate(true), "discard": eng.discard.duplicate(true)}


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


# ================================================================ piazzamento

## Piazzamento goloso, un Caballero alla volta: {regione: quanti}.
func _place(q: int, targets: Array, p := -1) -> Dictionary:
	if p < 0:
		p = me
	var out := {}
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
	for step in int(spec["max"]):
		var best = null
		var bv := 0.05
		for a in 9:
			if a == eng.king:
				continue
			for q in eng.n:
				if eng.cab[a][q] <= 0:
					continue
				if not _src_ok(p, spec, a, q, own, foe, src):
					continue
				var base := region_term(a, p)
				for b in 10:
					if b == a or b == eng.king:
						continue
					var b0 := region_term(b, p)
					eng.cab[a][q] -= 1
					eng.cab[b][q] += 1
					var v := region_term(a, p) + region_term(b, p) - base - b0 + _noise() * 0.3
					eng.cab[a][q] += 1
					eng.cab[b][q] -= 1
					if v > bv:
						bv = v
						best = [a, b, q]
		if best == null:
			break
		eng.cab[best[0]][best[2]] -= 1
		eng.cab[best[1]][best[2]] += 1
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
			if r == eng.king or (ctx == "evict_dest" and r == int(req["from"])):
				eng.court[me] += q
			else:
				eng.cab[r][me] += q
			return evaluate(me)
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
	for r in 9:
		var v := _gain_value(eng.region_points(r), p)
		if v > bv:
			bv = v
			best = r
	return best


## Quanto è utile, per il piazzamento futuro, che il Re stia in r (regioni confinanti dove conviene entrare).
func _adj_potential(r: int) -> float:
	var t := 0.0
	for a in D.ADJ[r]:
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
		for d in 9:
			if d == r or d == eng.king:
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

func _pick(req: Dictionary) -> int:
	var ctx: String = req["ctx"]
	var opts: Array = req["options"]
	match ctx:
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
			for r in 9:
				if r != eng.king and eng.cab[r][me] > 0:
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
	return 0


# ================================================================ carte azione

## Valore dell'azione speciale per `me`, applicata allo stato (che resta modificato).
func _special_value(ci: int) -> float:
	var key: String = D.CARDS[ci]["key"]
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
			for r in 9:
				if r == eng.king or eng.cab[r][me] <= 0:
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
				for r in 9:
					if r == eng.king or eng.cab[r][t] < (2 if key == "remove2" else 1):
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
				for r in 9:
					if r == eng.king or eng.cab[r][t] <= 0:
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
					for r in 9:
						if r == eng.king or eng.cab[r][t] <= 0:
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
			for r in 10:
				var v := _gain_value(eng.region_points(r), me)
				if v > bv:
					bv = v
					best = r
			_sim_score(best)
		"score4", "score5", "score67":
			var want: Array = {"score4": [4], "score5": [5], "score67": [6, 7]}[key]
			for r in 9:
				if int(eng.vals(r)[0]) in want:
					_sim_score(r)
		"score_most", "score_least":
			var best := []
			var bv := -1 if key == "score_most" else 999
			for r in 9:
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
			for r in 9:
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
				if eng.mobile[m] == eng.king and eng.mobile[m] >= 0:
					continue
				for r in 10:
					if r == eng.king or r == eng.mobile[0] or r == eng.mobile[1]:
						continue
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
			var allowed: Array = D.ADJ[eng.king] if key == "advisor" else range(9)
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
		"powerback":
			if not eng.discard[me].is_empty():
				eng.score[me] += 1.2
		"evict":
			var sn := snap()
			var best := -1
			var bv := -INF
			for r in 9:
				if r == eng.king:
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
				for r in 9:
					if r == eng.king:
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
	return evaluate(me)


func _sim_score(r: int, first_only := false) -> void:
	var pts := eng.region_points(r, first_only)
	for t in pts:
		eng.score[t] += pts[t]


## Piano completo per una carta: valore, ordine (azione prima o dopo il piazzamento).
func _plan(ci: int) -> Dictionary:
	var pile: int = D.CARDS[ci]["pile"]
	var sn := snap()
	# piazzamento poi azione
	_apply_place(_place(pile, eng.place_targets()), me)
	var base1 := evaluate(me)
	var a := maxf(base1, _special_value(ci))
	restore(sn)
	# azione poi piazzamento
	var b := -INF
	if eng.court[me] > 0:
		var base2 := evaluate(me)
		b = maxf(base2, _special_value(ci))
		_apply_place(_place(pile, eng.place_targets()), me)
		b = maxf(b, evaluate(me))
		restore(sn)
	return {"value": maxf(a, b), "special_first": b > a + 0.01}


func _action(req: Dictionary) -> int:
	var cards: Array = req["cards"]
	var best: int = cards[0]
	var bv := -INF
	for c in cards:
		var v: float = _plan(c)["value"] + _noise()
		if v > bv:
			bv = v
			best = c
	return best


# ================================================================ carte potere

func P(k: String, d: float) -> float:
	for part in exp.split(","):
		if part.begins_with(k + "="):
			return float(part.substr(k.length() + 1))
	return d


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
		var need := 0.75 if court0 < 4 else (0.45 if court0 < 8 else 0.2)
		var cab_val := cabs * need
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
