# RelapseGtk session bridge

`session.luau` is redistributed unmodified from [vpu00000/relapsegtk](https://github.com/vpu00000/relapsegtk), commit `6e926d9022e0e3e5632eaf1465cf42f31e1a4c01`, under GPL-3.0-only. The source is included here and its license is in `LICENSE`.

RelapseGtk runs this script in the game session and then connects its `relapsegtk.session.v2` channel. Orion's Flutter client follows the same protocol (`lib/services/relapse_gtk_service.dart` mirrors `src/socket/client.c`, `bridge.c` and `transport.c`), but it is an independent implementation: it does not link against or bundle the RelapseGtk application or its GTK UI.
