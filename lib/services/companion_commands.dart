import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/interface_preset.dart';
import '../models/orion_models.dart';
import '../models/orion_theme_preferences.dart';
import '../models/remote_script.dart';
import '../state/orion_controller.dart';

/// All companion mutations pass through the controller that owns recovery.
/// Keeping this independent of the desktop channel also makes the protocol
/// testable without starting another Flutter engine.
class CompanionCommands {
  CompanionCommands(this.controller);
  final OrionController controller;

  Future<Object?> apply(String operation, Map<String, Object?> p) async {
    // StandardMethodCodec decodes nested maps without String key type metadata.
    p = jsonDecode(jsonEncode(p)) as Map<String, dynamic>;
    final c = controller;
    switch (operation) {
      case 'applyThemeStudioState':
        c.applyThemeStudioState(
          InterfacePreset.values.byName(p['preset'] as String),
          document: p['document'],
          draft: p['draft'],
          orionTheme: p['orionTheme'] is Map
              ? OrionThemePreferences.fromJson(p['orionTheme'])
              : null,
        );
      case 'flushPersistence':
        await c.flushPersistence();
        return c.persistenceError;
      case 'setInterfacePreference':
        c.setInterfacePreference(
          InterfacePreset.values.byName(p['preset'] as String),
          p['key'] as String,
          p['value'],
        );
      case 'resetInterfacePreferences':
        c.resetInterfacePreferences(
          InterfacePreset.values.byName(p['preset'] as String),
        );
      case 'setDocumentContent':
        c.updateDocumentContent(p['id'] as String, p['content'] as String);
      case 'selectDocument':
        c.selectDocument(p['id'] as String);
      case 'insertDocument':
        final document = EditorDocument.fromJson(p['document']);
        if (document == null) throw const FormatException('Invalid document.');
        c.insertSharedDocument(document);
      case 'renameDocument':
        c.renameDocument(p['id'] as String, p['name'] as String);
      case 'closeDocument':
        final replacement = EditorDocument.fromJson(p['replacement']);
        if (replacement != null) c.insertSharedDocument(replacement);
        c.closeDocument(p['id'] as String);
      case 'reorderDocuments':
        final requested = (p['ids'] as List).cast<String>();
        final existing = c.documents.map((d) => d.id).toSet();
        c.reorderDocuments([
          ...requested.where(existing.contains).toSet(),
          ...existing.where((id) => !requested.contains(id)),
        ]);
      case 'importDocument':
        return (await c.importDocumentFromPath(
          p['path'] as String,
          replaceId: p['replaceId'] as String?,
        ))?.toJson();
      case 'saveDocument':
        return p['path'] is String
            ? c.saveDocumentToPath(p['id'] as String, p['path'] as String)
            : c.saveDocument(p['id'] as String);
      case 'execute':
        c.execute(source: p['source'] as String?, name: p['name'] as String?);
      case 'attach':
        c.attach();
      case 'initializeBridge':
        return c.initializeBridge();
      case 'setBridgeTargetAll':
        c.setBridgeTargetAll(p['value'] as bool);
      case 'setBridgeClientSelected':
        if (c.bridgeClients.any(
          (client) =>
              client.identifier == p['identifier'] &&
              client.sessionId == p['sessionId'],
        )) {
          c.setBridgeClientSelected(
            p['identifier'] as String,
            p['value'] as bool,
          );
        }
      case 'disconnectBridgeClient':
        if (c.bridgeClients.any(
          (client) =>
              client.identifier == p['identifier'] &&
              client.sessionId == p['sessionId'],
        )) {
          c.disconnectBridgeClient(p['identifier'] as String);
        }
      case 'disconnectAllBridgeClients':
        c.disconnectAllBridgeClients();
      case 'clearActivities':
        c.clearActivities();
      case 'updateSynapsePreferences':
        final patch = Map<String, Object?>.from(p['patch'] as Map);
        final previous = c.synapsePreferences.toJson();
        final colors = patch['themeColors'];
        if (colors is Map) {
          patch['themeColors'] = {
            ...c.synapsePreferences.themeColors,
            ...Map<String, Object?>.from(colors),
          };
        }
        c.applyWindowState({
          ...c.exportWindowState(),
          'synapsePreferences': {...previous, ...patch},
        });
        // applyWindowState is also used by read-only mirrors. The owner must
        // schedule recovery after accepting this settings patch.
        await c.flushPersistence();
      case 'resetSynapsePreferences':
        c.resetSynapsePreferences();
      case 'resetSynapseTheme':
        c.resetSynapseTheme(
          preset: p['preset'] as String? ?? 'framework',
          colors: Map<String, int>.from(p['colors'] as Map? ?? {}),
        );
      case 'setPreference':
        final value = p['value'];
        switch (p['key']) {
          case 'uiScale':
            c.setUiScale((value as num).toDouble());
          case 'editorFontSize':
            c.setEditorFontSize((value as num).toDouble());
          case 'wordWrap':
            c.setWordWrap(value as bool);
          case 'showLineNumbers':
            c.setShowLineNumbers(value as bool);
          case 'autosave':
            c.setAutosave(value as bool);
          case 'relapseSupport':
            c.setRelapseSupportEnabled(value as bool);
          case 'reducedMotion':
            c.setReducedMotion(value as bool);
          case 'themeMode':
            c.setThemeMode(ThemeMode.values.byName(value as String));
          case 'accent':
            c.setAccent(OrionAccent.values.byName(value as String));
          default:
            throw FormatException('Unknown preference: ${p['key']}');
        }
      case 'setRemoteSearchQuery':
        c.setRemoteSearchQuery(p['query'] as String);
      case 'setScriptProvider':
        final name = p['provider'];
        c.setScriptProvider(
          name is String ? ScriptProvider.values.byName(name) : null,
        );
      case 'searchRemoteScripts':
        unawaited(c.searchRemoteScripts(p['query'] as String?));
      case 'loadMoreRemoteScripts':
        unawaited(c.loadMoreRemoteScripts());
      case 'retryRemoteSource':
        unawaited(
          c.retryRemoteSource(
            ScriptProvider.values.byName(p['provider'] as String),
          ),
        );
      case 'toggleRemoteFavorite':
        final script = RemoteScript.fromJson(p['script']);
        if (script == null) throw const FormatException('Invalid script.');
        c.toggleRemoteFavorite(script);
      case 'loadRemoteScript':
        final script = RemoteScript.fromJson(p['script']);
        if (script == null) throw const FormatException('Invalid script.');
        return c.loadRemoteScript(script);
      default:
        throw FormatException('Unknown companion operation: $operation');
    }
    return null;
  }
}
