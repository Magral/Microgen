extends RefCounted

static func populate(hud, box: VBoxContainer, service, callbacks: Dictionary):
	var state: Dictionary = service.state
	box.add_child(hud.label("Установлена версия %s" % service.installed_version, 24))
	box.add_child(hud.label("Проверка выполняется только по вашей кнопке и обращается к GitHub Magral/Microgen. Игра не требует сети.", 20, Color("b5cfd1"), true))
	var message = "Можно проверить наличие стабильного выпуска."
	match state.get("status", "idle"):
		"checking": message = "Проверяем стабильный выпуск на GitHub…"
		"available": message = "Доступна версия %s" % state.get("newest", "")
		"current": message = "Обновлений нет. Последний стабильный выпуск: %s" % state.get("newest", "")
		"error": message = state.get("error", "Ошибка проверки.")
	box.add_child(hud.label(message, 23, Color("d4e7e7"), true))
	if state.get("status") == "checking":
		box.add_child(hud.button("Отменить проверку", callbacks.get("cancel", service.cancel)))
	else:
		box.add_child(hud.button("Проверить снова" if state.get("status") == "error" else "Проверить обновления", callbacks.get("check", service.check_updates), true))
	if state.get("status") == "available":
		box.add_child(hud.label("Кнопка откроет загрузку APK в браузере. Затем откройте скачанный файл и подтвердите установку в Android. При необходимости разрешите установку из этого браузера. Игра сама не скачивает и не устанавливает APK.", 20, Color("b5cfd1"), true))
		box.add_child(hud.button("Скачать APK через браузер", callbacks.get("open_download", service.open_download), true))
	if not str(state.get("release_url", "")).is_empty():
		box.add_child(hud.button("Открыть выпуск на GitHub", callbacks.get("open_release", service.open_release)))
	if callbacks.has("back"): box.add_child(hud.button("Назад", callbacks.back))
