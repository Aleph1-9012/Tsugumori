"""Tsugumori appearance, isolated to Nautilus's existing process.

Native file operations and controls remain intact. GTK events drive the
cosmetic adjustments; there is no polling or animation timer.
"""

import ctypes
import ctypes.util
from pathlib import Path

import gi

gi.require_version("Adw", "1")
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Nautilus", "4.1")
from gi.repository import Adw, Gdk, Gio, GLib, GObject, Gtk, Nautilus

THEME = Path(GLib.get_user_config_dir()) / "nautilus" / "tsugumori"


def descendants(widget):
    yield widget
    child = widget.get_first_child()
    while child:
        yield from descendants(child)
        child = child.get_next_sibling()


class TsugumoriTheme(GObject.GObject, Nautilus.MenuProvider):
    def __init__(self):
        super().__init__()
        self.pending = set()
        self._load_font()
        # Keep text bounds and rasterized glyphs aligned at both monitor scales.
        # These settings affect only Nautilus, not other GTK applications.
        settings = Gtk.Settings.get_default()
        settings.set_property("gtk-font-rendering", Gtk.FontRendering.MANUAL)
        settings.set_property("gtk-hint-font-metrics", True)
        settings.set_property("gtk-xft-antialias", 1)
        settings.set_property("gtk-xft-hinting", 1)
        settings.set_property("gtk-xft-hintstyle", "hintslight")
        settings.set_property("gtk-xft-rgba", "none")
        icons = Gtk.IconTheme.get_for_display(Gdk.Display.get_default())
        icons.add_search_path(str(THEME / "icons"))
        # Process-local GtkSettings, never the desktop's global GSettings.
        Gtk.Settings.get_default().set_property("gtk-icon-theme-name", "TsugumoriNautilus")
        self.provider = Gtk.CssProvider()
        self.provider.connect("parsing-error", self._css_error)
        self._load_css()
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), self.provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
        )
        self.css_monitor = Gio.File.new_for_path(str(THEME / "style.css")).monitor_file(
            Gio.FileMonitorFlags.NONE, None
        )
        self.css_monitor.connect("changed", self._css_changed)
        self.windows = Gtk.Window.get_toplevels()
        self.windows.connect("items-changed", self._windows_changed)
        GLib.idle_add(self._windows_changed)

    def _load_font(self):
        font = THEME / "IBMPlexSans.ttf"
        if not font.is_file():
            return
        try:
            library = ctypes.CDLL(ctypes.util.find_library("fontconfig"))
            library.FcConfigGetCurrent.restype = ctypes.c_void_p
            library.FcConfigAppFontAddFile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
            library.FcConfigAppFontAddFile(library.FcConfigGetCurrent(), bytes(font))
        except (OSError, TypeError):
            pass  # The stylesheet retains Inter as a fallback.

    def _load_css(self):
        self.provider.load_from_path(str(THEME / "style.css"))

    def _css_changed(self, _monitor, _file, _other, event):
        if event in (Gio.FileMonitorEvent.CHANGES_DONE_HINT, Gio.FileMonitorEvent.CREATED):
            self._load_css()

    def _css_error(self, _provider, section, error):
        print("Tsugumori CSS:", section.to_string(), error.message, flush=True)

    def _windows_changed(self, *_args):
        for index in range(self.windows.get_n_items()):
            window = self.windows.get_item(index)
            if window.has_css_class("nautilus-window") and not window.has_css_class("tsugumori"):
                window.add_css_class("tsugumori")
                window.connect("map", self._queue)
                window.connect("notify::active-slot", self._queue)
                self._queue(window)
        return GLib.SOURCE_REMOVE

    def _queue(self, widget, *_args):
        window = widget if isinstance(widget, Gtk.Window) else widget.get_root()
        if not isinstance(window, Gtk.Window) or window in self.pending:
            return
        self.pending.add(window)
        GLib.idle_add(self._style_window, window)

    def _style_window(self, window):
        self.pending.discard(window)
        if not window.get_child():
            return GLib.SOURCE_REMOVE
        widgets = list(descendants(window))
        split = next((w for w in widgets if isinstance(w, Adw.OverlaySplitView)), None)
        if split:
            split.set_min_sidebar_width(176)
            split.set_max_sidebar_width(176)
        for widget in widgets:
            kind = GObject.type_name(widget.__gtype__)
            if isinstance(widget, Adw.HeaderBar):
                widget.set_show_start_title_buttons(False)
                widget.set_show_end_title_buttons(False)
                widget.set_centering_policy(Adw.CenteringPolicy.STRICT)
            if isinstance(widget, Adw.WindowTitle):
                widget.set_visible(False)
            if kind == "NautilusGridCell":
                self._style_cell(widget)
            if isinstance(widget, Gtk.GridView) and not widget.has_css_class("ts-grid"):
                widget.add_css_class("ts-grid")
                factory = widget.get_factory()
                if isinstance(factory, Gtk.SignalListItemFactory):
                    factory.connect_after("bind", self._bind_cell)
            if kind == "NautilusWindowSlot" and not widget.has_css_class("ts-slot"):
                widget.add_css_class("ts-slot")
                widget.connect("notify::loading", self._queue)
                widget.connect("notify::location", self._queue)
            if isinstance(widget, Gtk.Stack) and not widget.has_css_class("ts-stack"):
                widget.add_css_class("ts-stack")
                widget.connect("notify::visible-child", self._queue)
            if widget.has_css_class("nautilus-pathbar"):
                widget.set_hexpand(False)
                scrolled = widget.get_first_child()
                if isinstance(scrolled, Gtk.ScrolledWindow):
                    scrolled.set_propagate_natural_width(True)
                    scrolled.set_max_content_width(560)
                for node in descendants(widget):
                    if isinstance(node, Gtk.Label) and node.get_label() == "/":
                        node.add_css_class("ts-slash")
                    if isinstance(node, Gtk.Image):
                        button = node.get_ancestor(Gtk.Button)
                        if button and button.has_css_class("nautilus-path-button"):
                            node.set_visible(False)
            if isinstance(widget, Gtk.ListBox) and widget.has_css_class("navigation-sidebar"):
                if not widget.has_css_class("ts-places"):
                    widget.add_css_class("ts-places")
                    widget.set_sort_func(self._sort_places)
                    widget.set_header_func(self._place_header)
            if kind == "NautilusToolbar":
                self._style_toolbar(widget)
        return GLib.SOURCE_REMOVE

    def _style_toolbar(self, toolbar):
        if toolbar.has_css_class("ts-toolbar"):
            return
        toolbar.add_css_class("ts-toolbar")
        header = next((w for w in descendants(toolbar) if isinstance(w, Adw.HeaderBar)), None)
        if not header:
            return
        title = header.get_title_widget()
        if isinstance(title, Gtk.Box):
            title.set_halign(Gtk.Align.CENTER)
            title.set_hexpand(False)
            switcher = title.get_first_child()
            if isinstance(switcher, Gtk.Stack):
                switcher.set_hhomogeneous(False)
                switcher.set_vhomogeneous(False)
            # Reposition the existing search stack, retaining its native bindings.
            search_stack = title.get_last_child()
            if isinstance(search_stack, Gtk.Stack) and search_stack != title.get_first_child():
                title.remove(search_stack)
                header.pack_end(search_stack)

    def _bind_cell(self, _factory, list_item):
        cell = list_item.get_child()
        if cell:
            self._style_cell(cell)

    def _style_cell(self, cell):
        for node in descendants(cell):
            if node.has_css_class("icon-ui-labels-box"):
                label = node.get_first_child()
                if isinstance(label, Gtk.Label):
                    label.set_lines(2)
                    label.set_valign(Gtk.Align.START)
                    label.set_yalign(0.0)

    @staticmethod
    def _place_rank(row):
        if not row.find_property("uri"):
            return (200, 0)
        uri = row.get_property("uri") or ""
        home = Gio.File.new_for_path(GLib.get_home_dir()).get_uri()
        special = {"recent:///": 0, "starred:///": 1, home: 2,
                   home + "/Documents": 3, home + "/Downloads": 4,
                   home + "/Pictures": 5, home + "/Projects": 6,
                   "trash:///": 90, "network:///": 91, "network://": 91}
        order = row.get_property("order-index")
        if uri in special:
            return (special[uri], order)
        if uri.startswith(home + "/"):
            return (7, order)
        return (100, order)

    def _sort_places(self, first, second, *_args):
        a, b = self._place_rank(first), self._place_rank(second)
        return (a > b) - (a < b)

    def _place_header(self, row, previous, *_args):
        rank = self._place_rank(row)[0]
        before = self._place_rank(previous)[0] if previous else -1
        divided = previous is not None and ((rank >= 2 and before < 2) or (rank >= 90 and before < 90) or (rank >= 100 and before < 100))
        if divided and row.get_header() is None:
            row.set_header(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))
        elif not divided:
            row.set_header(None)

    def get_file_items(self, *_args):
        return []

    def get_background_items(self, *_args):
        return []
