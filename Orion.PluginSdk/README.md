# Orion Plugin SDK

Reference `Orion.PluginSdk.dll`, target `net8.0-windows`, and implement
`Orion.Extensibility.IOrionPlugin` on a public class with a parameterless
constructor.

Plugins run in-process with full trust. The supplied context exposes Orion's
live Avalonia application, desktop lifetime, main window, shared service
registry, package directory, and private writable data directory.

Package the compiled plugin and its dependencies in a `.orionplugin` or `.zip`
file with a `plugin.json` at its root:

```json
{
  "id": "author.plugin-name",
  "name": "Plugin Name",
  "version": "1.0.0",
  "description": "What the plugin does.",
  "author": "Author",
  "entryAssembly": "PluginName.dll",
  "entryType": "PluginName.EntryPoint"
}
```

Loose DLLs are also supported. Orion discovers the entry type and generates
the package manifest automatically.
