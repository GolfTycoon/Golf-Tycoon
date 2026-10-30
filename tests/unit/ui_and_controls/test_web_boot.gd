extends GameTest
## The game's end of the web build's loader handshake (WebBoot): the JavaScript
## it sends to the exported shell's `window.GolfTycoonBoot`, and its quiet no-op
## behaviour away from the browser.
##
## The shell's end - the bridge object, the stage line it feeds and the fade it
## runs when the title screen reports in - lives in web/custom_shell.html.

func test_a_stage_report_names_the_shell_object_and_the_step() -> void:
	var script := WebBoot.stage_script("Surveying the grounds")
	assert_string_contains(script, WebBoot.BRIDGE)
	assert_string_contains(script, ".setStage(")
	assert_string_contains(script, '"Surveying the grounds"')

## Stages are written in the game and sent to the page, so an apostrophe or a
## quote in the copy must arrive as a valid JavaScript string literal rather
## than as a broken snippet that leaves the loader's line frozen.
func test_stage_copy_is_escaped_as_a_javascript_string() -> void:
	var awkward := "The owner's \"first\" tee"
	var script := WebBoot.stage_script(awkward)
	assert_string_contains(script, JSON.stringify(awkward))
	assert_false(script.contains("\n"), "a stage fits on one line")

func test_the_title_screen_report_calls_the_shells_ready_hook() -> void:
	var script := WebBoot.ready_script()
	assert_string_contains(script, WebBoot.BRIDGE)
	assert_string_contains(script, ".ready(")

## The export's page is the only thing listening, and this suite is not in a
## browser: reporting must be harmless here, and still leave a record of how far
## a startup got.
func test_reporting_is_harmless_away_from_the_web() -> void:
	assert_false(WebBoot.is_web(), "the test suite runs as a native build")
	WebBoot.reset()
	WebBoot.set_stage("Opening the pro shop")
	assert_eq(WebBoot.last_stage, "Opening the pro shop")
	WebBoot.menu_ready()
	assert_true(WebBoot._menu_reported, "the title screen is only reported once")
	WebBoot.reset()
	assert_eq(WebBoot.last_stage, "")
	assert_false(WebBoot._menu_reported, "a fresh scene reports again")

## Every web build slices its startup (see Main._ready); a native build only
## does when it is asked to, which is how the sliced path is exercised without a
## browser.
func test_slicing_is_forced_by_the_command_line_or_by_tests() -> void:
	assert_false(WebBoot.split_startup(), "a plain native run builds in one frame")
	WebBoot.split_startup_forced = true
	assert_true(WebBoot.split_startup(), "a test or benchmark can ask for slices")
	WebBoot.split_startup_forced = false
	assert_false(WebBoot.split_startup())
