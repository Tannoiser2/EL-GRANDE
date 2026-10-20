extends SceneTree
## Screenshot automatici dell'interfaccia (serve un display: xvfb-run).
## xvfb-run godot --path . -s res://tests/shot.gd -- <modo>

var main
var n := 0
var taken := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	n += 1
	img.save_png(OS.get_user_data_dir() + "/shots/%02d_%s.png" % [n, name])
	print("shot ", name)


func wait(f := 10) -> void:
	for i in range(f):
		await process_frame


func gv():
	return main.current


func auto_answer() -> void:
	var g = gv()
	var req: Dictionary = g.pending
	if req.is_empty():
		return
	var ai := EGAI.new(1, 5)
	var r = ai.decide(g.engine, int(req["seat"]), req)
	g._provide(r)


func _run() -> void:
	var mode: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "game"
	await wait(5)
	await shot("menu")
	if mode == "menu":
		quit()
		return
	if mode == "rules":
		main.show_rules()
		await wait(5)
		await shot("regole")
		quit()
		return
	main.start_game({"seats": [
		{"color": 0, "ai": false, "name": "Stefano", "level": 1},
		{"color": 1, "ai": true, "name": "Verde", "level": 1},
		{"color": 3, "ai": true, "name": "Giallo", "level": 1},
		{"color": 4, "ai": true, "name": "Blu", "level": 1}], "ai_delay": 0.0, "seed": 4242, "variant": OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "base"})
	await wait(10)
	var frames := 0
	while frames < 20000:
		frames += 1
		await process_frame
		var g = gv()
		if g == null or not ("engine" in g):
			break
		if g.engine.game_over:
			await wait(10)
			await shot("fine")
			break
		if not g.modal.get_children().is_empty() and g.pending.is_empty():
			# pausa (valutazione generale): foto e avanti
			if not taken.has("pausa"):
				taken["pausa"] = true
				await shot("pausa_valutazione")
			g.engine.provide_decision(true)
			g._clear_modal()
			continue
		var req: Dictionary = g.pending
		if req.is_empty():
			continue
		var tp: String = req["type"]
		var key := tp + ":" + str(req.get("ctx", ""))
		if not taken.has(key):
			taken[key] = true
			await wait(4)
			if tp == "place":
				# anteprima di un piazzamento
				var t: Array = req["targets"]
				g._on_region_click(t[0], MOUSE_BUTTON_LEFT)
				await wait(2)
			if tp == "moves":
				var srcs: Array = g._move_sources()
				if not srcs.is_empty():
					g._on_region_click(srcs[0], MOUSE_BUTTON_LEFT)
					await wait(2)
			if tp == "action":
				g._card_popup(req["cards"][0], true)
				await wait(2)
			await shot(key.replace(":", "_"))
			g._card_popup(0, false)
		auto_answer()
	quit()
