import QtQuick
import QtTest
import "../../../../config/quickshell/services/NotificationMarkup.js" as Markup

TestCase {
    name: "NotificationMarkup"

    function test_plain_text_is_escaped() {
        compare(Markup.toStyledText("a < b & c"), "a &lt; b &amp; c")
        compare(Markup.toStyledText("2 > 1"), "2 &gt; 1")
    }

    function test_basic_formatting_is_kept() {
        compare(Markup.toStyledText("<b>bold</b> <i>it</i> <u>un</u>"),
            "<b>bold</b> <i>it</i> <u>un</u>")
        compare(Markup.toStyledText("<B CLASS=\"x\">bold</B> <I>it</I>"),
            "<b>bold</b> <i>it</i>")
    }

    function test_disallowed_tags_are_dropped_but_text_is_kept() {
        compare(Markup.toStyledText("<a href=\"https://e.test\">site</a>"), "site")
        compare(Markup.toStyledText("before<img src=\"x.png\">after"), "beforeafter")
        compare(Markup.toStyledText("<span style=\"color:red\">word</span>"), "word")
    }

    function test_entities_are_decoded_once() {
        compare(Markup.toStyledText("&lt;img src=x&gt;"), "&lt;img src=x&gt;")
        compare(Markup.toStyledText("&amp;amp;"), "&amp;amp;")
        compare(Markup.toStyledText("&#169;"), "©")
        compare(Markup.toStyledText("&#x263A;"), "☺")
        compare(Markup.toStyledText("it&apos;s"), "it's")
        compare(Markup.toStyledText("a&nbsp;b"), "a&amp;nbsp;b")
        compare(Markup.toStyledText("&quot;q&quot;"), "\"q\"")
    }

    function test_line_breaks() {
        compare(Markup.toStyledText("one\ntwo"), "one<br>two")
        compare(Markup.toStyledText("one<br/>two"), "one<br>two")
        compare(Markup.toStyledText("one<br />two"), "one<br>two")
        compare(Markup.toStyledText("one\r\ntwo"), "one<br>two")
    }

    function test_nesting_is_repaired() {
        compare(Markup.toStyledText("<b>open"), "<b>open</b>")
        compare(Markup.toStyledText("x</b>y"), "xy")
        compare(Markup.toStyledText("<b><i>x</b>y</i>"), "<b><i>x</i></b><i>y</i>")
    }

    function test_empty_input() {
        compare(Markup.toStyledText(null), "")
        compare(Markup.toStyledText(""), "")
        compare(Markup.toStyledText(undefined), "")
    }

    Text {
        id: body
        width: 120
        textFormat: Text.StyledText
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
    }

    function test_styled_text_still_elides() {
        body.text = Markup.toStyledText(
            "<b>A notification body</b> with enough words to wrap well past two lines of text")
        verify(body.text.indexOf("<b>") === 0)
        verify(body.truncated === true)
    }
}
