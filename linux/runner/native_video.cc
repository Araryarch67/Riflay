#include "native_video.h"

#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <mpv/client.h>
#include <mpv/render_gl.h>
#ifdef GDK_WINDOWING_X11
#include <epoxy/glx.h>
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace {

struct Surface {
  GtkWidget* area;
  GtkWidget* fixed;
  mpv_handle* player = nullptr;
  mpv_render_context* renderer = nullptr;
  gint pending = 0;
  bool destroyed = false;
  int clip[4] = {};
  int full[4] = {};
  GLuint framebuffer = 0;
  GLuint texture = 0;
  int width = 0;
  int height = 0;
  int64_t frames = 0;
};

Surface* surface(GtkWidget* area) {
  return static_cast<Surface*>(
      g_object_get_data(G_OBJECT(area), "riflay-video"));
}

void* get_proc(void* data, const char* name) {
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(data)) {
    return reinterpret_cast<void*>(
        glXGetProcAddressARB(reinterpret_cast<const GLubyte*>(name)));
  }
#endif
  return reinterpret_cast<void*>(eglGetProcAddress(name));
}

void detach(Surface* s) {
  if (s->renderer == nullptr) return;
  mpv_render_context_set_update_callback(s->renderer, nullptr, nullptr);
  gtk_gl_area_make_current(GTK_GL_AREA(s->area));
  mpv_render_context_free(s->renderer);
  s->renderer = nullptr;
  s->player = nullptr;
  if (s->framebuffer != 0) glDeleteFramebuffers(1, &s->framebuffer);
  if (s->texture != 0) glDeleteTextures(1, &s->texture);
  s->framebuffer = s->texture = 0;
  s->width = s->height = 0;
  s->frames = 0;
  gtk_widget_hide(s->area);
}

void render_frame(Surface* s, int target, int w, int h) {
  mpv_opengl_fbo fbo = {target, w, h, 0};
  int flip = 1;
  // GTK owns presentation. Do not block its main thread on mpv's clock.
  int block = 0;
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
      {MPV_RENDER_PARAM_FLIP_Y, &flip},
      {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &block},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  mpv_render_context_render(s->renderer, params);
}

gboolean render(GtkGLArea* area, GdkGLContext*, gpointer data) {
  auto* s = static_cast<Surface*>(data);
  if (s->renderer == nullptr) return TRUE;
  mpv_render_context_update(s->renderer);
  GLint target = 0;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &target);
  const int w = std::max(1, s->full[2] - s->full[0]);
  const int h = std::max(1, s->full[3] - s->full[1]);
  const int scale = gtk_widget_get_scale_factor(GTK_WIDGET(area));
  const int dw = gtk_widget_get_allocated_width(GTK_WIDGET(area)) * scale;
  const int dh = gtk_widget_get_allocated_height(GTK_WIDGET(area)) * scale;
  if (std::equal(s->clip, s->clip + 4, s->full) && dw == w && dh == h) {
    // The usual case needs no intermediate texture or GPU copy.
    render_frame(s, target, w, h);
    glBindFramebuffer(GL_FRAMEBUFFER, target);
    ++s->frames;
    return TRUE;
  }
  if (w != s->width || h != s->height) {
    if (s->framebuffer == 0) glGenFramebuffers(1, &s->framebuffer);
    if (s->texture == 0) glGenTextures(1, &s->texture);
    glBindTexture(GL_TEXTURE_2D, s->texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                 nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glBindFramebuffer(GL_FRAMEBUFFER, s->framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           s->texture, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    s->width = w;
    s->height = h;
  }
  // Render the full box, then copy only the visible portion. Resizing mpv to
  // the clipped box would squeeze the picture as it scrolls offscreen.
  render_frame(s, s->framebuffer, w, h);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, s->framebuffer);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, target);
  glDisable(GL_SCISSOR_TEST);
  const int x = s->clip[0] - s->full[0];
  const int y = h - (s->clip[3] - s->full[1]);
  glBlitFramebuffer(x, y, x + s->clip[2] - s->clip[0],
                    y + s->clip[3] - s->clip[1], 0, 0, dw, dh,
                    GL_COLOR_BUFFER_BIT, GL_LINEAR);
  glBindFramebuffer(GL_FRAMEBUFFER, target);
  ++s->frames;
  return TRUE;
}

gboolean update_on_gtk(gpointer data) {
  auto* area = GTK_WIDGET(data);
  auto* s = surface(area);
  g_atomic_int_set(&s->pending, 0);
  if (s->destroyed || s->renderer == nullptr) return G_SOURCE_REMOVE;
  if (gtk_widget_get_mapped(area)) {
    gtk_gl_area_queue_render(GTK_GL_AREA(area));
  } else {
    // The cover stays visible until the first decoded frame is ready. Even
    // while hidden, service mpv so opening paused cannot deadlock on rendering.
    gtk_gl_area_make_current(GTK_GL_AREA(area));
    mpv_render_context_update(s->renderer);
    int skip = 1;
    mpv_render_param params[] = {{MPV_RENDER_PARAM_SKIP_RENDERING, &skip},
                                 {MPV_RENDER_PARAM_INVALID, nullptr}};
    mpv_render_context_render(s->renderer, params);
  }
  return G_SOURCE_REMOVE;
}

void update(void* data) {
  auto* s = static_cast<Surface*>(data);
  // Called by mpv's thread. Queue one GTK callback and keep the widget alive
  // until it runs; all GTK/GL work remains on the GTK thread.
  if (g_atomic_int_compare_and_exchange(&s->pending, 0, 1)) {
    g_idle_add_full(G_PRIORITY_DEFAULT, update_on_gtk, g_object_ref(s->area),
                    g_object_unref);
  }
}

const char* attach(Surface* s, mpv_handle* player) {
  if (s->renderer != nullptr) return "A video renderer is already attached";
  gtk_widget_realize(s->area);
  gtk_gl_area_make_current(GTK_GL_AREA(s->area));
  if (gtk_gl_area_get_error(GTK_GL_AREA(s->area)) != nullptr) {
    return gtk_gl_area_get_error(GTK_GL_AREA(s->area))->message;
  }
  GdkDisplay* display = gtk_widget_get_display(s->area);
  mpv_opengl_init_params gl = {get_proc, display};
  std::vector<mpv_render_param> params = {
      {MPV_RENDER_PARAM_API_TYPE,
       const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL)},
      {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl},
  };
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) {
    params.push_back(
        {MPV_RENDER_PARAM_X11_DISPLAY, gdk_x11_display_get_xdisplay(display)});
  }
#endif
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
    params.push_back({MPV_RENDER_PARAM_WL_DISPLAY,
                      gdk_wayland_display_get_wl_display(display)});
  }
#endif
  params.push_back({MPV_RENDER_PARAM_INVALID, nullptr});
  const int result =
      mpv_render_context_create(&s->renderer, player, params.data());
  if (result < 0) return mpv_error_string(result);
  s->player = player;
  mpv_render_context_set_update_callback(s->renderer, update, s);
  return nullptr;
}

void method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* s = surface(GTK_WIDGET(data));
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  const char* error = nullptr;
  if (s->destroyed) {
    error = "The video surface was destroyed";
  } else if (g_str_equal(method, "status")) {
    // Diagnostics for real-engine tests and renderer troubleshooting.
    g_autoptr(FlValue) status = fl_value_new_map();
    fl_value_set_string_take(status, "attached",
                             fl_value_new_bool(s->renderer != nullptr));
    fl_value_set_string_take(status, "visible",
                             fl_value_new_bool(gtk_widget_get_mapped(s->area)));
    fl_value_set_string_take(status, "frames", fl_value_new_int(s->frames));
    fl_value_set_string_take(status, "width",
                             fl_value_new_int(s->full[2] - s->full[0]));
    fl_value_set_string_take(status, "height",
                             fl_value_new_int(s->full[3] - s->full[1]));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(status));
  } else if (g_str_equal(method, "ensure")) {
    g_autoptr(FlValue) token = fl_value_new_int(1);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(token));
  } else if (g_str_equal(method, "attach") || g_str_equal(method, "detach")) {
    if (fl_value_get_type(args) != FL_VALUE_TYPE_INT ||
        fl_value_get_int(args) <= 0) {
      error = "Expected an mpv handle";
    } else {
      auto* player = reinterpret_cast<mpv_handle*>(fl_value_get_int(args));
      if (g_str_equal(method, "attach")) {
        error = attach(s, player);
      } else if (s->player == player) {
        detach(s);
      }
    }
  } else if (g_str_equal(method, "place")) {
    if (fl_value_get_type(args) != FL_VALUE_TYPE_LIST ||
        fl_value_get_length(args) != 8) {
      error = "Expected clip and full rectangles";
    } else {
      for (int i = 0; i < 8; ++i) {
        if (fl_value_get_type(fl_value_get_list_value(args, i)) !=
            FL_VALUE_TYPE_INT) {
          error = "Expected integer coordinates";
          break;
        }
      }
      if (error == nullptr) {
        for (int i = 0; i < 4; ++i) {
          s->clip[i] = fl_value_get_int(fl_value_get_list_value(args, i));
          s->full[i] = fl_value_get_int(fl_value_get_list_value(args, i + 4));
        }
        if (s->clip[2] <= s->clip[0] || s->clip[3] <= s->clip[1] ||
            s->renderer == nullptr) {
          gtk_widget_hide(s->area);
        } else {
          const double scale = gtk_widget_get_scale_factor(s->area);
          gtk_fixed_move(GTK_FIXED(s->fixed), s->area,
                         std::lround(s->clip[0] / scale),
                         std::lround(s->clip[1] / scale));
          gtk_widget_set_size_request(
              s->area,
              std::max(1L, std::lround((s->clip[2] - s->clip[0]) / scale)),
              std::max(1L, std::lround((s->clip[3] - s->clip[1]) / scale)));
          gtk_widget_show(s->area);
          gtk_gl_area_queue_render(GTK_GL_AREA(s->area));
        }
      }
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  if (error != nullptr) {
    response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("native-video", error, nullptr));
  } else if (response == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

GtkWidget* native_video_wrap(FlView* view) {
  GtkWidget* overlay = gtk_overlay_new();
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  GtkWidget* fixed = gtk_fixed_new();
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay), fixed);
  gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(overlay), fixed, TRUE);
  gtk_widget_show(fixed);

  GtkWidget* area = gtk_gl_area_new();
  gtk_gl_area_set_required_version(GTK_GL_AREA(area), 3, 2);
  gtk_gl_area_set_auto_render(GTK_GL_AREA(area), FALSE);
  gtk_widget_set_can_focus(area, FALSE);
  gtk_widget_set_no_show_all(area, TRUE);
  gtk_fixed_put(GTK_FIXED(fixed), area, 0, 0);
  auto* s = new Surface{area, fixed};
  g_object_set_data_full(G_OBJECT(area), "riflay-video", s, [](gpointer value) {
    delete static_cast<Surface*>(value);
  });
  g_signal_connect(area, "render", G_CALLBACK(render), s);
  g_signal_connect(area, "unrealize",
                   G_CALLBACK(+[](GtkWidget*, gpointer data) {
                     detach(static_cast<Surface*>(data));
                   }),
                   s);
  g_signal_connect(area, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer data) {
                     auto* state = static_cast<Surface*>(data);
                     detach(state);
                     state->destroyed = true;
                   }),
                   s);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "riflay/video_window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call,
                                            g_object_ref(area), g_object_unref);
  // Keep the channel registered for the lifetime of this view.
  g_object_set_data_full(G_OBJECT(view), "riflay-video-channel",
                         g_object_ref(channel), g_object_unref);
  gtk_widget_show(overlay);
  return overlay;
}
