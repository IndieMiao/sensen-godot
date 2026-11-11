extends GdUnitTestSuite
## The account pages' copy as the table has it (SGODOT-491; 李白's q(312)–q(317), #999).

const AGREE := "I agree to the Terms of Service and Privacy Policy"
const LINKS := ["Terms of Service", "Privacy Policy"]

## AGE's consent row (spec v1.1 A): its two names are links, found in the line by their own words — in English as they
## are, under 中文 as the table writes them alone. A line or a name changed on its own loses a link: this fails first.
func test_the_consent_line_holds_its_two_links_in_both_languages() -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/localization/p0_zh_CN.json"))
	assert_bool(table.has(AGREE)).is_true()
	for name in LINKS:
		assert_str(AGREE).contains(name)
		assert_bool(table.has(name)).override_failure_message(name).is_true()
		assert_str(str(table[AGREE])).override_failure_message("%s: %s not in %s" % [name, table[name], table[AGREE]]) \
			.contains(str(table[name]))
