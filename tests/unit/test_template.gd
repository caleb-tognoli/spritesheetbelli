extends "res://tests/test_case.gd"


func render(text: String, values: Variant = {}) -> String:
	var template := Template.parse(text)
	var result := template.render(values)
	assert_eq(template.error, "", "no error in %s" % text.c_escape())
	return result


## The error of [param text], parsed and filled with [param values]
func error_of(text: String, values: Variant = {}) -> String:
	var template := Template.parse(text)
	template.render(values)
	return template.error


func test_variables() -> void:
	var values := {"name": "hero", "size": {"w": 4, "h": 8}, "count": 3, "on": true, "off": null}
	assert_eq(render("{{name}}: {{ size.w }}x{{size.h}}", values), "hero: 4x8")
	assert_eq(render("[{{missing}}][{{off}}][{{size.missing.deeper}}]", values), "[][][]")
	assert_eq(render("{{count}} {{on}} {{&name}}", values), "3 true hero")
	assert_eq(render("{{list.1}}", {"list": ["a", "b"]}), "b", "items of a list by position")
	assert_eq(render("<{{name}}>", {"name": "a&b"}), "<a&b>", "not escaped")
	assert_eq(render("{{number}}", {"number": 12.0}), "12.0", "floats as Godot writes them")


func test_sections() -> void:
	var values := {"frames": [{"n": 1}, {"n": 2}], "none": [], "on": true, "off": false}
	assert_eq(render("{{#frames}}<{{n}}>{{/frames}}", values), "<1><2>")
	assert_eq(render("{{#none}}x{{/none}}{{#off}}x{{/off}}{{#missing}}x{{/missing}}", values), "")
	assert_eq(
		render("{{#on}}yes{{/on}}{{^off}}no{{/off}}{{^none}}empty{{/none}}", values), "yesnoempty"
	)
	assert_eq(render("{{^frames}}x{{/frames}}{{^on}}x{{/on}}", values), "")
	assert_eq(render("{{#size}}{{w}}x{{h}}{{/size}}", {"size": {"w": 2, "h": 3}}), "2x3")
	assert_eq(render("{{#zero}}{{zero}}{{/zero}}", {"zero": 0}), "0", "numbers are set, 0 too")
	assert_eq(render("{{#text}}[{{.}}]{{/text}}", {"text": ""}), "", "empty text isn't")
	assert_eq(
		render("{{#names}}{{.}};{{/names}}", {"names": PackedStringArray(["a", "b"])}), "a;b;"
	)


func test_names_are_looked_up_outwards() -> void:
	var values := {"image": "a.png", "pages": [{"frames": [{"name": "x"}], "index": 4}]}
	var text := "{{#pages}}{{#frames}}{{name}}@{{index}}/{{image}}{{/frames}}{{/pages}}"
	assert_eq(render(text, values), "x@4/a.png")
	# A value that's there but not set hides the one around it
	var hidden := {"duration": 5, "frames": [{"duration": null}]}
	assert_eq(render("{{#frames}}[{{duration}}]{{/frames}}", hidden), "[]")


func test_first_last_and_index() -> void:
	var values := {"items": ["a", "b", "c"]}
	assert_eq(render("[{{#items}}{{.}}{{^@last}}, {{/@last}}{{/items}}]", values), "[a, b, c]")
	assert_eq(render("{{#items}}{{#@first}}>{{/@first}}{{@index}}{{/items}}", values), ">012")
	var nested := {"rows": [{"cells": [1, 2]}, {"cells": [3]}]}
	var text := "{{#rows}}{{#cells}}{{.}}{{#@last}};{{/@last}}{{/cells}}{{/rows}}"
	assert_eq(render(text, nested), "12;3;", "the innermost list's")


func test_comments_and_standalone_lines() -> void:
	assert_eq(render("a{{! a comment }}b"), "ab")
	var text := "{{! header\nkey: value\n}}\nstart\n{{#items}}\n  - {{.}}\n{{/items}}\nend\n"
	assert_eq(render(text, {"items": [1, 2]}), "start\n  - 1\n  - 2\nend")
	# Lines of several sections and comments go too, but not lines that also have text
	var several := "{{#a}}{{#b}}  \n\tin\n{{/b}} {{/a}}\n{{#a}}x{{/a}}\n"
	assert_eq(render(several, {"a": true, "b": true}), "\tin\nx")
	assert_eq(render("a\r\n{{#on}}\r\nb\r\n{{/on}}\r\n", {"on": true}), "a\r\nb\r\n")


func test_the_last_line_break_is_left_out() -> void:
	assert_eq(render("{}\n"), "{}")
	assert_eq(render("line\n\n"), "line\n", "an empty line keeps one")
	assert_eq(render("no break"), "no break")


func test_runs_of_braces() -> void:
	var values := {"frames": [{"name": "a"}], "x": 1}
	assert_eq(render('{{{#frames}}"{{name}}"{{/frames}}}', values), '{"a"}')
	assert_eq(render("{{{{x}}}}", values), "{{1}}")


func test_filters() -> void:
	var values := {
		"text": 'say "hi"\n<&>',
		"name": "Walk",
		"index": 7,
		"w": 20,
		"half": 0.5,
		"e": 2.71828,
		"third": 1.0 / 3.0,
		"whole": 32.0,
		"flag": true,
	}
	assert_eq(render("{{text | json-escape}}", values), 'say \\"hi\\"\\n<&>')
	assert_eq(render("{{text | xml-escape}}", values), "say &quot;hi&quot;\n&lt;&amp;&gt;")
	assert_eq(render("{{name | lower}} {{name | upper}}", values), "walk WALK")
	assert_eq(render("{{index | pad 3}} {{index | negate | pad 3}}", values), "007 -007")
	assert_eq(
		render("{{index | plus 1}} {{index | plus w}} {{index | plus -10}}", values), "8 27 -3"
	)
	assert_eq(render("{{index | plus w | pad 4}}", values), "0027", "one after the other")
	assert_eq(
		render("{{third | round 3}} {{whole | round 3}} {{e | round 2}}", values), "0.333 32 2.72"
	)
	assert_eq(
		render("{{name | json}} {{half | json}} {{whole | json}} {{flag | json}}", values),
		'"Walk" 0.5 32.0 true'
	)
	assert_eq(render("[{{missing | plus 1}}]", values), "[]", "not set stays not set")


func test_errors_say_where() -> void:
	assert_eq(error_of("a\n{{#frames}}\nb"), "line 2: {{#frames}} is never closed")
	assert_eq(error_of("{{#a}}\n{{^b}}\n{{/a}}"), "line 3: {{/a}} doesn't close {{^b}} from line 2")
	assert_eq(error_of("\n\n{{/a}}"), "line 3: {{/a}} closes no section")
	assert_eq(error_of("{{! two\nlines }}\n{{x | shout}}"), 'line 3: unknown filter "shout"')
	assert_eq(error_of("{{x | pad}}"), "line 1: pad takes 1 argument(s), not 0")
	assert_eq(error_of("{{x | pad two words}}"), "line 1: pad takes 1 argument(s), not 2")
	assert_eq(error_of("{{x | plus 1.5}}"), 'line 1: plus: "1.5" is neither a number nor a name')
	assert_eq(error_of("a {{x"), "line 1: {{ without }}")
	assert_eq(error_of("{{}}"), "line 1: {{}} has no name")
	assert_eq(error_of("{{a b}}"), 'line 1: "a b" isn\'t a name')
	assert_eq(error_of("{{> partial}}"), "line 1: {{> partial}} isn't supported")
	assert_eq(
		error_of("{{#a | lower}}{{/a}}"),
		"line 1: {{#a | lower}}: only values take filters, not sections"
	)
	assert_eq(
		error_of("\n{{name | plus 1}}", {"name": "hero"}), 'line 2: plus needs numbers, not "hero"'
	)
	assert_eq(
		error_of("{{x | plus name}}", {"x": 1, "name": "a"}), 'line 1: plus needs numbers, not "a"'
	)
	# Filling it again starts over
	var template := Template.parse("{{x | negate}}")
	template.render({"x": "a"})
	assert_ne(template.error, "")
	assert_eq(template.render({"x": 2}), "-2")
	assert_eq(template.error, "")
	# A template that doesn't parse writes nothing
	var broken := Template.parse("text {{#a}}")
	assert_eq(broken.render({}), "")
	assert_ne(broken.error, "")
	assert_true("not found" in Template.load_file("res://templates/missing.template").error)


func test_header() -> void:
	var text := "{{! spritesheetbelli template\nname: My format\nper_page: true\n"
	text += "rotation: none\n\nNotes: not a setting\n}}\nbody\n"
	var template := Template.parse(text)
	assert_eq(template.header, {"name": "My format", "per_page": true, "rotation": "none"})
	assert_eq(template.render({}), "body")
	assert_eq(Template.parse("text {{! name: x }}").header, {}, "only a comment at the start")
