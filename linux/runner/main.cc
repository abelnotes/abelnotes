#include <stdlib.h>

#include "my_application.h"

int main(int argc, char** argv) {
  // Mesa's threaded GL dispatch (glthread) races when the GL context is
  // torn down and rebuilt on a monitor change (window dragged to a
  // different output), crashing inside libgallium's worker thread. Disable
  // it before GTK/the Flutter engine bring up any GL context; setenv only
  // takes effect if unset, so a user's own MESA_GLTHREAD still wins.
  setenv("MESA_GLTHREAD", "0", /*overwrite=*/0);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
