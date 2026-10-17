#include "my_application.h"
#include "egl_lifetime.h"

int main(int argc, char** argv) {
  orion_install_egl_lifetime();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
