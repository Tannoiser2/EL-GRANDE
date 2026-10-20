extends SceneTree
## Partite simulate fra IA, senza grafica: controlla che le regole reggano (Caballeros sempre 30
## per giocatore, nessuno nella regione del Re fuori posto) e misura i tempi.
## Uso: godot --headless --path . -s tests/sim.gd -- [partite] [giocatori] [livello]

var errors := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 5
	var np := int(args[1]) if args.size() > 1 else 4
	var lvl := int(args[2]) if args.size() > 2 else 1
	_run(games, np, lvl)


func _run(games: int, np: int, lvl: int) -> void:
	await process_frame
	var wins := {}
	var diff_sum := 0.0
	var test_wins := 0
	var tot := {}
	var t0 := Time.get_ticks_msec()
	for g in games:
		var eng := EGEngine.new()
		eng.headless = true
		root.add_child(eng)
		var seats := []
		var tseat := g % np
		for i in np:
			seats.append({"color": i, "ai": true, "name": "IA%d" % i, "level": lvl if i != tseat else (int(OS.get_environment("EG_LVL0")) if OS.get_environment("EG_LVL0") != "" else lvl)})
		eng.setup({"seats": seats, "seed": int(OS.get_environment("EG_SEED0") if OS.get_environment("EG_SEED0") != "" else "1000") + g, "short": OS.get_environment("EG_SHORT") == "1", "variant": OS.get_environment("EG_VARIANT") if OS.get_environment("EG_VARIANT") != "" else "base"})
		for i in np:
			if OS.get_environment("EG_BASE") == "1" and i != tseat:
				eng.ais[i] = EGAIBase.new(seats[i]["level"], 77 + g * 10 + i)
			else:
				eng.ais[i] = EGAI.new(seats[i]["level"], 77 + g * 10 + i)
			if i == tseat:
				eng.ais[i].exp = OS.get_environment("EG_EXP")
		eng.changed.connect(_check.bind(eng))
		var tg := Time.get_ticks_msec()
		await eng.run()
		if OS.get_environment("EG_LOG") == "1":
			for l in eng.log_lines:
				print("  ", l)
		var res := eng.results
		wins[res[0]["seat"]] = wins.get(res[0]["seat"], 0) + 1
		var line := []
		for r in res:
			line.append("%s %d" % [r["name"], r["score"]])
			tot[r["seat"]] = tot.get(r["seat"], 0) + r["score"]
		var others := 0.0
		for i in np:
			if i != tseat:
				others += eng.score[i]
		diff_sum += eng.score[tseat] - others / (np - 1)
		if res[0]["seat"] == tseat:
			test_wins += 1
		print("partita %d (%d ms): %s" % [g, Time.get_ticks_msec() - tg, ", ".join(line)])
		eng.queue_free()
	print("TEST: vittorie %d/%d, scarto medio %.2f" % [test_wins, games, diff_sum / games])
	print("vittorie: ", wins, "  punti totali: ", tot)
	print("tempo totale %d ms, errori %d" % [Time.get_ticks_msec() - t0, errors])
	quit(1 if errors > 0 else 0)


func _check(eng: EGEngine) -> void:
	for s in eng.n:
		var t: int = eng.court[s] + eng.prov[s]
		for r in eng.cab.size():
			if eng.cab[r][s] < 0:
				errors += 1
				push_error("negativo in %d per %d" % [r, s])
			t += eng.cab[r][s]
		t += eng.reserve.get(s, 0)
		if not eng.bridge.is_empty() and eng.bridge["owner"] == s and eng.bridge.get("guard", false):
			t += 1
		for rcv in eng.gifts:
			for g in eng.gifts[rcv]:
				if g == s:
					t += 1
		if t != eng.total_cab or eng.court[s] < 0 or eng.prov[s] < 0:
			errors += 1
			push_error("totale Caballeros %d per %d (corte %d, province %d)" % [t, s, eng.court[s], eng.prov[s]])
