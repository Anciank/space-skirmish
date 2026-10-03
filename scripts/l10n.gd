extends Node
## Shared translations and bundled fonts for both native controls and the HUD.

signal language_changed

const LANGUAGES := {
	"en": "English",
	"zh_CN": "简体中文",
	"es": "Español",
	"hi": "हिन्दी",
	"ar": "العربية",
	"pt_BR": "Português (Brasil)",
	"fr": "Français",
	"de": "Deutsch",
	"ja": "日本語",
	"ko": "한국어",
	"ru": "Русский",
	"id": "Bahasa Indonesia",
}
const FONT_NOTICES := [
	"res://assets/fonts/notosans-OFL.txt",
	"res://assets/fonts/notosanscjk-OFL.txt",
	"res://assets/fonts/notosansarabic-OFL.txt",
	"res://assets/fonts/notosansdevanagari-OFL.txt",
]

var locale := "en"
var font: Font
var _catalogues: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Load after the editor's asset-import phase so a clean checkout can import
	# the raw font files before this resource references their imported data.
	font = load("res://assets/fonts/interface_font.tres")
	for source: Font in font.fallbacks + [(font as FontVariation).base_font]:
		(source as FontFile).allow_system_fallback = false
	for code: String in LANGUAGES:
		var path := "res://translations/%s.json" % code
		var contents: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not contents is Dictionary:
			push_error("Invalid translation catalogue: " + path)
			continue
		_catalogues[code] = contents
		var translation := Translation.new()
		translation.locale = code
		for source: String in contents:
			translation.add_message(source, String(contents[source]))
		TranslationServer.add_translation(translation)
	TranslationServer.set_locale(locale)


func language_codes() -> Array[String]:
	var codes: Array[String] = []
	for code: String in LANGUAGES:
		codes.append(code)
	return codes


func language_name(code: String) -> String:
	return LANGUAGES.get(code, LANGUAGES.en)


func set_language(code: String) -> void:
	var next := code if LANGUAGES.has(code) else "en"
	if locale == next:
		return
	locale = next
	TranslationServer.set_locale(locale)
	language_changed.emit()


func text(source: String) -> String:
	return String(TranslationServer.translate(source))


func is_rtl() -> bool:
	return locale == "ar"


func pilot_name(source: String) -> String:
	var caption := text("YOU") if source == "YOU" else source
	# Callsigns stay stable in the ledger. Isolate their direction when placed
	# inside an Arabic sentence so codes and punctuation keep their order.
	return "\u2068" + caption + "\u2069" if is_rtl() else caption


func catalogue(code: String) -> Dictionary:
	return _catalogues.get(code, {})


func font_notices() -> String:
	var notices := "Noto fonts / SIL Open Font License 1.1\n"
	for path: String in FONT_NOTICES:
		notices += "\n" + FileAccess.get_file_as_string(path) + "\n"
	return notices
