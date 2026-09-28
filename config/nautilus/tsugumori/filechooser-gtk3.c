/* Add an appearance-only class to GTK 3 file dialogs. No file operations,
 * input handlers, polling, or changes to the application's theme settings. */
#include <gtk/gtk.h>
#include <fontconfig/fontconfig.h>

static GtkCssProvider *provider;
static cairo_user_data_key_t neutral_surface_key;

/* GTK 3 pre-renders chooser MIME icons into Cairo surfaces, outside CSS's
 * symbolic-icon rules. Desaturate only those cell surfaces, retaining each
 * file type's shape and leaving every other application icon unchanged. */
static void
neutral_icon(GObject *renderer, GParamSpec *property, gpointer data)
{
    (void) property; (void) data;
    if (g_object_get_data(renderer, "tsugumori-icon-busy"))
        return;
    cairo_surface_t *surface = NULL;
    g_object_get(renderer, "surface", &surface, NULL);
    if (!surface || cairo_surface_get_type(surface) != CAIRO_SURFACE_TYPE_IMAGE ||
        cairo_surface_get_user_data(surface, &neutral_surface_key)) {
        if (surface) cairo_surface_destroy(surface);
        return;
    }
    int width = cairo_image_surface_get_width(surface);
    int height = cairo_image_surface_get_height(surface);
    GdkPixbuf *pixels = gdk_pixbuf_get_from_surface(surface, 0, 0, width, height);
    if (pixels) {
        double sx, sy;
        cairo_surface_get_device_scale(surface, &sx, &sy);
        gdk_pixbuf_saturate_and_pixelate(pixels, pixels, 0.0f, FALSE);
        cairo_surface_t *neutral = gdk_cairo_surface_create_from_pixbuf(pixels, 1, NULL);
        cairo_surface_set_device_scale(neutral, sx, sy);
        cairo_surface_set_user_data(neutral, &neutral_surface_key, GINT_TO_POINTER(1), NULL);
        g_object_set_data(renderer, "tsugumori-icon-busy", GINT_TO_POINTER(1));
        g_object_set(renderer, "surface", neutral, NULL);
        g_object_set_data(renderer, "tsugumori-icon-busy", NULL);
        cairo_surface_destroy(neutral);
        g_object_unref(pixels);
    }
    cairo_surface_destroy(surface);
}

static void
style_icons(GtkWidget *widget, gpointer data)
{
    (void) data;
    if (GTK_IS_TREE_VIEW(widget)) {
        GList *columns = gtk_tree_view_get_columns(GTK_TREE_VIEW(widget));
        for (GList *column = columns; column; column = column->next) {
            GList *cells = gtk_cell_layout_get_cells(GTK_CELL_LAYOUT(column->data));
            for (GList *cell = cells; cell; cell = cell->next) {
                if (GTK_IS_CELL_RENDERER_PIXBUF(cell->data) &&
                    !g_object_get_data(G_OBJECT(cell->data), "tsugumori-icon-hook")) {
                    g_object_set_data(G_OBJECT(cell->data), "tsugumori-icon-hook", GINT_TO_POINTER(1));
                    g_signal_connect(cell->data, "notify::surface", G_CALLBACK(neutral_icon), NULL);
                    neutral_icon(G_OBJECT(cell->data), NULL, NULL);
                }
            }
            g_list_free(cells);
        }
        g_list_free(columns);
    }
    if (GTK_IS_CONTAINER(widget))
        gtk_container_forall(GTK_CONTAINER(widget), style_icons, NULL);
}

static void
style_chooser(GtkWidget *widget)
{
    if (!GTK_IS_FILE_CHOOSER_DIALOG(widget))
        return;

    GdkScreen *screen = gtk_widget_get_screen(widget);
    if (!g_object_get_data(G_OBJECT(screen), "tsugumori-chooser-provider")) {
        if (!provider) {
            gchar *base = g_build_filename(g_get_user_config_dir(), "nautilus", "tsugumori", NULL);
            gchar *css = g_build_filename(base, "filechooser-gtk3.css", NULL);
            gchar *font = g_build_filename(base, "IBMPlexSans.ttf", NULL);
            GError *error = NULL;
            provider = gtk_css_provider_new();
            if (!gtk_css_provider_load_from_path(provider, css, &error)) {
                g_warning("Tsugumori file chooser: %s", error->message);
                g_clear_error(&error);
            }
            FcConfigAppFontAddFile(FcConfigGetCurrent(), (const FcChar8 *) font);
            g_free(font);
            g_free(css);
            g_free(base);
        }
        gtk_style_context_add_provider_for_screen(screen, GTK_STYLE_PROVIDER(provider),
                                                  GTK_STYLE_PROVIDER_PRIORITY_USER);
        g_object_set_data(G_OBJECT(screen), "tsugumori-chooser-provider", provider);
    }
    gtk_style_context_add_class(gtk_widget_get_style_context(widget), "tsugumori-filechooser");
    style_icons(widget, NULL);
}

static gboolean
on_realize(GSignalInvocationHint *hint, guint count, const GValue *values, gpointer data)
{
    (void) hint; (void) data;
    if (count)
        style_chooser(g_value_get_object(&values[0]));
    return TRUE;
}

G_MODULE_EXPORT void
gtk_module_init(gint *argc, gchar ***argv)
{
    (void) argc; (void) argv;
    static gboolean initialized;
    if (initialized)
        return;
    initialized = TRUE;
    gpointer widget_class = g_type_class_ref(GTK_TYPE_WIDGET);
    g_signal_add_emission_hook(g_signal_lookup("realize", GTK_TYPE_WIDGET), 0,
                              on_realize, NULL, NULL);
    g_type_class_unref(widget_class);
    GList *windows = gtk_window_list_toplevels();
    for (GList *item = windows; item; item = item->next)
        style_chooser(GTK_WIDGET(item->data));
    g_list_free(windows);
}
