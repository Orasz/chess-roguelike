extends GutHookScript
## Runs before the suite: the tests read English, whatever the language of the machine they run on.
## The tests of the Italian catalog set their own locale and put this one back.


func run() -> void:
	TranslationServer.set_locale("en")
