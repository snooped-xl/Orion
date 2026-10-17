import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/remote_script.dart';
import '../state/orion_controller.dart';
import '../theme/orion_theme.dart';
import '../widgets/common.dart';
import '../widgets/orion_overlay.dart';
import '../widgets/script_thumbnail.dart';

class LibraryScreen extends StatefulWidget {
  final OrionController controller;
  final VoidCallback onOpenWorkspace;
  const LibraryScreen({
    super.key,
    required this.controller,
    required this.onOpenWorkspace,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final TextEditingController _search;
  bool _favoritesOnly = false;
  String _favoriteQuery = '';
  ScriptProvider? _favoriteProvider;
  final Set<String> _opening = {};
  final Set<String> _executing = {};
  final Map<String, String> _executeErrors = {};

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.controller.searchQuery);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setFavorites(bool selected) {
    setState(() {
      _favoritesOnly = selected;
      if (selected) _favoriteProvider = widget.controller.selectedProvider;
    });
    _search.text = selected ? _favoriteQuery : widget.controller.searchQuery;
  }

  void _searchChanged(String value) {
    if (_favoritesOnly) {
      setState(() => _favoriteQuery = value);
    } else {
      widget.controller.setRemoteSearchQuery(value);
    }
  }

  void _submitSearch() {
    if (!_favoritesOnly) widget.controller.searchRemoteScripts(_search.text);
  }

  void _selectProvider(ScriptProvider? provider) {
    if (_favoritesOnly) {
      setState(() => _favoriteProvider = provider);
    } else {
      widget.controller.setScriptProvider(provider);
    }
  }

  void _clearSearch() {
    _search.clear();
    _searchChanged('');
  }

  Future<void> _open(RemoteScript item) async {
    if (_opening.contains(item.key) || _executing.contains(item.key)) return;
    setState(() => _opening.add(item.key));
    try {
      final document = await widget.controller.openRemoteScript(item);
      if (!mounted) return;
      if (document != null) {
        widget.onOpenWorkspace();
      } else {
        toast(context, 'This source did not return script code.');
      }
    } catch (error) {
      if (mounted) toast(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _opening.remove(item.key));
    }
  }

  Future<void> _execute(RemoteScript item) async {
    if (_opening.contains(item.key) || _executing.contains(item.key)) return;
    setState(() {
      _executing.add(item.key);
      _executeErrors.remove(item.key);
    });
    try {
      await widget.controller.executeRemoteScript(item);
      if (mounted) toast(context, widget.controller.activities.first.title);
    } catch (error) {
      if (mounted) {
        final message = _errorText(error);
        setState(() => _executeErrors[item.key] = message);
        toast(context, message);
      }
    } finally {
      if (mounted) setState(() => _executing.remove(item.key));
    }
  }

  Future<void> _onSource(RemoteScript item) async {
    try {
      await widget.controller.openScriptPage(item);
    } catch (error) {
      if (mounted) toast(context, _errorText(error));
    }
  }

  Future<void> _onProvider(ScriptProvider provider) async {
    try {
      await widget.controller.openScriptProvider(provider);
    } catch (error) {
      if (mounted) toast(context, _errorText(error));
    }
  }

  void _viewCode(RemoteScript item) {
    showDialog<void>(
      context: context,
      builder: (context) => OrionOverlayTheme(
        controller: widget.controller,
        builder: (context) => _RemoteCodeDialog(
          item: item,
          controller: widget.controller,
          onOpenWorkspace: widget.onOpenWorkspace,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final selectedProvider = _favoritesOnly
            ? _favoriteProvider
            : controller.selectedProvider;
        final query = (_favoritesOnly ? _favoriteQuery : controller.searchQuery)
            .trim()
            .toLowerCase();
        final items = _favoritesOnly
            ? controller.remoteFavorites.where((item) {
                return (selectedProvider == null ||
                        item.provider == selectedProvider) &&
                    (query.isEmpty ||
                        '${item.title} ${item.game} ${item.description} ${item.provider.label}'
                            .toLowerCase()
                            .contains(query));
              }).toList()
            : controller.remoteScripts;
        final errors = _favoritesOnly
            ? <MapEntry<ScriptProvider, String>>[]
            : controller.providerErrors.entries
                  .where(
                    (entry) =>
                        selectedProvider == null ||
                        entry.key == selectedProvider,
                  )
                  .toList();
        final loading = !_favoritesOnly && controller.remoteLoading;
        final activeProviders = _favoritesOnly
            ? items.map((item) => item.provider).toSet().toList()
            : selectedProvider == null
            ? ScriptProvider.values
            : <ScriptProvider>[selectedProvider];
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1380
                ? 3
                : constraints.maxWidth >= 680
                ? 2
                : 1;
            final cardWidth =
                (constraints.maxWidth - 16 * (columns - 1)) / columns;
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Scripts', style: OrionType.pageTitle),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Refresh scripts',
                        onPressed: _favoritesOnly || loading
                            ? null
                            : () => controller.searchRemoteScripts(),
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: _searchChanged,
                          onSubmitted: (_) => _submitSearch(),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: _favoritesOnly
                                ? 'Search favorites'
                                : 'Search scripts',
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: colors.muted,
                              size: 20,
                            ),
                            suffixIcon: query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: _clearSearch,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      if (!_favoritesOnly) ...[
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _submitSearch,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text('Search'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _sourceChip(
                        context,
                        null,
                        'All sources',
                        selectedProvider == null,
                      ),
                      for (final provider in ScriptProvider.values)
                        _sourceChip(
                          context,
                          provider,
                          provider.label,
                          selectedProvider == provider,
                        ),
                      FilterChip(
                        label: const Text('Favorites'),
                        selected: _favoritesOnly,
                        showCheckmark: false,
                        avatar: Icon(
                          _favoritesOnly
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 15,
                          color: _favoritesOnly
                              ? colors.transparentSurfaces
                                    ? colors.readableAccent
                                    : colors.onAccent
                              : colors.muted,
                        ),
                        onSelected: _setFavorites,
                        backgroundColor: colors.chrome(
                          colors.panel,
                          role: 'panel',
                        ),
                        selectedColor: colors.transparentSurfaces
                            ? colors.ink.withValues(alpha: .08)
                            : colors.accent,
                        side: colors.transparentSurfaces
                            ? BorderSide(color: colors.outline(.35), width: .6)
                            : BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 5,
                        ),
                        labelStyle: OrionType.label.copyWith(
                          color: _favoritesOnly && !colors.transparentSurfaces
                              ? colors.onAccent
                              : colors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (loading) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: colors.readableAccent,
                        backgroundColor: colors.chrome(
                          colors.elevated,
                          role: 'elevated',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (errors.isNotEmpty) ...[
                    SurfaceCard(
                      radius: 20,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < errors.length;
                            index++
                          ) ...[
                            if (index > 0) Divider(color: colors.outline(.6)),
                            _ProviderFailure(
                              provider: errors[index].key,
                              message: errors[index].value,
                              busy: loading,
                              onRetry: () => controller.retryRemoteSource(
                                errors[index].key,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Text(
                        '${items.length} ${items.length == 1 ? 'result' : 'results'}',
                        style: OrionType.label.copyWith(color: colors.muted),
                      ),
                      const Spacer(),
                      Text(
                        _favoritesOnly
                            ? 'Saved on this device'
                            : selectedProvider?.label ?? 'All sources',
                        style: OrionType.label.copyWith(color: colors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: controller.reducedMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    reverseDuration: controller.reducedMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 140),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, .015),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: items.isEmpty
                        ? _EmptyScripts(
                            key: ValueKey(
                              'empty/$_favoritesOnly/$loading/${errors.isNotEmpty}',
                            ),
                            loading: loading,
                            favorites: _favoritesOnly,
                            query: query,
                            unavailable: errors.isNotEmpty,
                            provider: selectedProvider,
                          )
                        : Wrap(
                            key: ValueKey(
                              '${selectedProvider?.name}/$_favoritesOnly/${items.map((item) => item.key).join(',')}',
                            ),
                            spacing: 16,
                            runSpacing: 16,
                            children: items
                                .map(
                                  (item) => SizedBox(
                                    width: cardWidth,
                                    child: _RemoteScriptCard(
                                      key: ValueKey(item.key),
                                      controller: controller,
                                      item: item,
                                      reducedMotion: controller.reducedMotion,
                                      favorite: controller.isRemoteFavorite(
                                        item.key,
                                      ),
                                      opening: _opening.contains(item.key),
                                      executing: _executing.contains(item.key),
                                      executeError: _executeErrors[item.key],
                                      onFavorite: () =>
                                          controller.toggleRemoteFavorite(item),
                                      onViewCode: () => _viewCode(item),
                                      onOpen: () => _open(item),
                                      onExecute: () => _execute(item),
                                      onSource: () => _onSource(item),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                  if (!_favoritesOnly &&
                      controller.remoteHasMore &&
                      items.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: controller.remoteLoadingMore || loading
                            ? null
                            : () => controller.loadMoreRemoteScripts(),
                        icon: controller.remoteLoadingMore
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.expand_more_rounded, size: 18),
                        label: Text(
                          controller.remoteLoadingMore
                              ? 'Loading…'
                              : 'Load more',
                        ),
                      ),
                    ),
                  ],
                  if (activeProviders.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: activeProviders
                          .map(
                            (provider) => TextButton(
                              onPressed: () => _onProvider(provider),
                              style: TextButton.styleFrom(
                                foregroundColor: colors.muted,
                                minimumSize: const Size(0, 28),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 6,
                                ),
                                textStyle: OrionType.metadata.copyWith(
                                  fontFamily: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.fontFamily,
                                ),
                              ),
                              child: Text(switch (provider) {
                                ScriptProvider.scriptBlox =>
                                  'Powered by ScriptBlox.com',
                                ScriptProvider.robloxScripts =>
                                  'Data from robloxscripts.com',
                                _ => 'Source: ${provider.domain}',
                              }),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sourceChip(
    BuildContext context,
    ScriptProvider? provider,
    String label,
    bool selected,
  ) {
    final colors = OrionColors.of(context);
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => _selectProvider(provider),
      backgroundColor: colors.chrome(colors.panel, role: 'panel'),
      selectedColor: colors.transparentSurfaces
          ? colors.ink.withValues(alpha: .08)
          : colors.accent,
      side: colors.transparentSurfaces
          ? BorderSide(color: colors.outline(.35), width: .6)
          : BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      labelStyle: OrionType.label.copyWith(
        color: selected && !colors.transparentSurfaces
            ? colors.onAccent
            : colors.ink,
      ),
    );
  }
}

class _ProviderFailure extends StatelessWidget {
  final ScriptProvider provider;
  final String message;
  final bool busy;
  final VoidCallback onRetry;
  const _ProviderFailure({
    required this.provider,
    required this.message,
    required this.busy,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 17, color: colors.readablePeach),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${provider.label} unavailable', style: OrionType.label),
                const SizedBox(height: 3),
                Tooltip(
                  message: message,
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OrionType.body.copyWith(color: colors.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: busy ? null : onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _RemoteScriptCard extends StatefulWidget {
  final OrionController controller;
  final RemoteScript item;
  final bool favorite, opening, executing, reducedMotion;
  final String? executeError;
  final VoidCallback onFavorite, onViewCode, onOpen, onExecute, onSource;
  const _RemoteScriptCard({
    super.key,
    required this.controller,
    required this.item,
    required this.favorite,
    required this.opening,
    required this.executing,
    required this.executeError,
    required this.reducedMotion,
    required this.onFavorite,
    required this.onViewCode,
    required this.onOpen,
    required this.onExecute,
    required this.onSource,
  });

  @override
  State<_RemoteScriptCard> createState() => _RemoteScriptCardState();
}

class _RemoteScriptCardState extends State<_RemoteScriptCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final item = widget.item;
    final busy = widget.opening || widget.executing;
    final metadata = '${item.provider.label} · ${_viewCount(item.views)}';
    final detail = [
      metadata,
      if (item.updatedAt != null) _updatedLabel(item.updatedAt!),
      item.isPaid ? 'Paid' : 'Free',
      if (item.hasKey) 'Key required',
      if (item.isVerified) 'Verified',
    ].join(' · ');
    return Material(
      animationDuration: widget.reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      color: _hovered
          ? colors.transparentSurfaces
                ? colors.ink.withValues(alpha: .035)
                : Color.lerp(colors.panel, colors.elevated, .5)
          : colors.chrome(colors.panel, role: 'panel'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: _hovered
              ? colors.readableAccent.withValues(alpha: .25)
              : colors.transparentSurfaces
              ? colors.outline(.35)
              : Colors.transparent,
          width: colors.transparentSurfaces ? .6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : widget.onViewCode,
        onHover: (value) => setState(() => _hovered = value),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ScriptThumbnail(
                  key: ValueKey('image/${item.key}'),
                  imageUrl: item.imageUrl,
                  title: item.title,
                  controller: widget.controller,
                  reducedMotion: widget.reducedMotion,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: Tooltip(
                        message: item.description.isEmpty
                            ? item.title
                            : '${item.title}\n\n${item.description}',
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: OrionType.sectionTitle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      tooltip: widget.favorite
                          ? 'Remove from favorites'
                          : 'Add to favorites',
                      onPressed: widget.onFavorite,
                      padding: const EdgeInsets.all(8),
                      icon: Icon(
                        widget.favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 20,
                        color: widget.favorite
                            ? colors.readableAccent
                            : colors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 20,
                child: Row(
                  children: [
                    Icon(
                      Icons.sports_esports_outlined,
                      size: 16,
                      color: colors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.game.isEmpty ? 'Universal' : item.game,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OrionType.body.copyWith(color: colors.muted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 24,
                child: Tooltip(
                  message: detail,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OrionType.metadata.copyWith(
                            color: colors.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        item.isPaid ? 'Paid' : 'Free',
                        style: OrionType.metadata.copyWith(color: colors.muted),
                      ),
                      if (item.hasKey) ...[
                        const SizedBox(width: 10),
                        Tooltip(
                          message: 'Key required',
                          child: Icon(
                            Icons.key_outlined,
                            size: 16,
                            color: colors.muted,
                          ),
                        ),
                      ],
                      if (item.isVerified) ...[
                        const SizedBox(width: 10),
                        Tooltip(
                          message: 'Verified',
                          child: Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: colors.readableAccent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 390) {
                    return Row(
                      children: [
                        _sourceAction(context),
                        const SizedBox(width: 4),
                        _codeAction(context, busy),
                        const Spacer(),
                        _openAction(context, busy),
                        const SizedBox(width: 8),
                        _executeAction(context, busy),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(
                        children: [
                          _sourceAction(context),
                          const Spacer(),
                          _codeAction(context, busy),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _openAction(context, busy)),
                          const SizedBox(width: 12),
                          Expanded(child: _executeAction(context, busy)),
                        ],
                      ),
                    ],
                  );
                },
              ),
              if (widget.executeError != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 18,
                      color: colors.readablePeach,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.executeError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: OrionType.body.copyWith(color: colors.muted),
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : widget.onExecute,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _secondaryStyle(BuildContext context) => TextButton.styleFrom(
    minimumSize: const Size(0, 40),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    foregroundColor: OrionColors.of(context).muted,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: OrionType.label.copyWith(
      fontFamily: Theme.of(context).textTheme.labelLarge?.fontFamily,
    ),
  );

  Widget _sourceAction(BuildContext context) => TextButton.icon(
    onPressed: widget.onSource,
    style: _secondaryStyle(context),
    icon: const Icon(Icons.open_in_new_rounded, size: 15),
    label: const Text('On source'),
  );

  Widget _codeAction(BuildContext context, bool busy) => TextButton(
    onPressed: busy ? null : widget.onViewCode,
    style: _secondaryStyle(context),
    child: const Text('View code'),
  );

  Widget _openAction(BuildContext context, bool busy) {
    final colors = OrionColors.of(context);
    return FilledButton.tonal(
      onPressed: busy ? null : widget.onOpen,
      style: FilledButton.styleFrom(
        backgroundColor: colors.chrome(colors.accent.withValues(alpha: .13)),
        foregroundColor: colors.readableAccent,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: OrionType.label.copyWith(
          fontFamily: Theme.of(context).textTheme.labelLarge?.fontFamily,
        ),
      ),
      child: widget.opening
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Open'),
    );
  }

  Widget _executeAction(BuildContext context, bool busy) {
    final colors = OrionColors.of(context);
    return FilledButton.icon(
      key: ValueKey('execute/${widget.item.key}'),
      onPressed: busy ? null : widget.onExecute,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: OrionType.label.copyWith(
          fontFamily: Theme.of(context).textTheme.labelLarge?.fontFamily,
        ),
      ),
      icon: widget.executing
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.transparentSurfaces
                    ? colors.ink
                    : colors.onAccent,
              ),
            )
          : const Icon(Icons.play_arrow_rounded, size: 16),
      label: const Text('Execute'),
    );
  }
}

class _EmptyScripts extends StatelessWidget {
  final bool loading, favorites, unavailable;
  final String query;
  final ScriptProvider? provider;
  const _EmptyScripts({
    super.key,
    required this.loading,
    required this.favorites,
    required this.unavailable,
    required this.query,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final title = loading
        ? 'Searching ${provider?.label ?? 'all sources'}…'
        : favorites
        ? (query.isEmpty ? 'No favorites yet' : 'No matching favorites')
        : unavailable
        ? 'No scripts available'
        : query.isEmpty
        ? 'Search scripts'
        : 'No scripts found';
    final detail = loading
        ? 'Fetching live results.'
        : favorites
        ? 'Use the heart icon on a result to save it.'
        : unavailable
        ? 'Retry a source above, or select another source.'
        : 'Search across RobloxScripts, ScriptBlox, HaxHell, and rscripts.net.';
    return SurfaceCard(
      radius: 20,
      padding: const EdgeInsets.all(32),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            if (loading)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.readableAccent,
                ),
              )
            else
              Icon(
                favorites
                    ? Icons.favorite_border_rounded
                    : unavailable
                    ? Icons.cloud_off_rounded
                    : Icons.search_rounded,
                color: colors.muted,
                size: 25,
              ),
            const SizedBox(height: 12),
            Text(title, style: OrionType.sectionTitle),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: OrionType.body.copyWith(color: colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteCodeDialog extends StatefulWidget {
  final RemoteScript item;
  final OrionController controller;
  final VoidCallback onOpenWorkspace;
  const _RemoteCodeDialog({
    required this.item,
    required this.controller,
    required this.onOpenWorkspace,
  });

  @override
  State<_RemoteCodeDialog> createState() => _RemoteCodeDialogState();
}

class _RemoteCodeDialogState extends State<_RemoteCodeDialog> {
  final ScrollController _scroll = ScrollController();
  String? _code;
  String? _error;
  bool _loading = false;
  bool _opening = false;
  bool _executing = false;
  String? _executionError;

  @override
  void initState() {
    super.initState();
    final body = widget.item.body;
    if (body != null && body.trim().isNotEmpty) {
      _code = body;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || _opening || _executing) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await widget.controller.loadRemoteScript(widget.item);
      if (code.trim().isEmpty) {
        throw StateError('This source returned empty script code.');
      }
      if (mounted) setState(() => _code = code);
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open() async {
    if (_loading || _opening || _executing) return;
    setState(() => _opening = true);
    try {
      final document = await widget.controller.openRemoteScript(widget.item);
      if (document == null) {
        throw StateError('This source did not return script code.');
      }
      if (mounted) {
        Navigator.of(context).pop();
        widget.onOpenWorkspace();
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _execute() async {
    if (_loading || _opening || _executing || _code == null) return;
    setState(() {
      _executing = true;
      _executionError = null;
    });
    try {
      await widget.controller.executeRemoteScript(widget.item);
      if (mounted) toast(context, widget.controller.activities.first.title);
    } catch (error) {
      if (mounted) {
        final message = _errorText(error);
        setState(() => _executionError = message);
        toast(context, message);
      }
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  Future<void> _copy() async {
    final code = _code;
    if (code == null || _loading || _opening || _executing) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) toast(context, 'Script code copied');
  }

  Future<void> _onSource() async {
    try {
      await widget.controller.openScriptPage(widget.item);
    } catch (error) {
      if (mounted) toast(context, _errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = OrionColors.of(context);
    final item = widget.item;
    final busy = _loading || _opening || _executing;
    return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: OrionOverlaySurface(
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 850,
            maxHeight: MediaQuery.sizeOf(context).height - 72,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${item.provider.label} · Lua',
                      style: OrionType.label.copyWith(color: colors.muted),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close code',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: OrionType.sectionTitle,
                ),
                const SizedBox(height: 7),
                Text(
                  item.game.isEmpty
                      ? item.provider.domain
                      : '${item.game} · ${item.provider.domain}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OrionType.label.copyWith(color: colors.muted),
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.background,
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _loading
                        ? _codeStatus(context, loading: true)
                        : _error != null
                        ? _codeStatus(context, loading: false)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  12,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.elevated,
                                  border: Border(
                                    bottom: BorderSide(color: colors.border),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.code_rounded,
                                      size: 16,
                                      color: colors.readableAccent,
                                    ),
                                    const SizedBox(width: 9),
                                    const Text('Lua', style: OrionType.label),
                                    const Spacer(),
                                    Text(
                                      '${_code?.split('\n').length ?? 0} lines',
                                      style: OrionType.metadata.copyWith(
                                        color: colors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Flexible(
                                child: Scrollbar(
                                  controller: _scroll,
                                  child: SingleChildScrollView(
                                    controller: _scroll,
                                    padding: const EdgeInsets.all(16),
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: SelectableText.rich(
                                        _highlightLua(_code ?? '', colors),
                                        style: TextStyle(
                                          fontFamily: 'JetBrainsMono',
                                          fontSize: 13,
                                          height: 1.6,
                                          color: colors.ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                if (_executionError != null) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 18,
                        color: colors.readablePeach,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _executionError!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: OrionType.body.copyWith(color: colors.muted),
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : _execute,
                        child: const Text('Retry execution'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _onSource,
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('On source'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _code == null || busy ? null : _copy,
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: const Text('Copy code'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _code == null || busy || _error != null
                          ? null
                          : _open,
                      icon: _opening
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text('Open in workspace'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('execute/dialog'),
                      onPressed: _code == null || busy || _error != null
                          ? null
                          : _execute,
                      icon: _executing
                          ? SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.transparentSurfaces
                                    ? colors.ink
                                    : colors.onAccent,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Execute'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _codeStatus(BuildContext context, {required bool loading}) {
    final colors = OrionColors.of(context);
    return SizedBox(
      height: 250,
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.readableAccent,
              )
            else
              Icon(
                Icons.cloud_off_rounded,
                color: colors.readablePeach,
                size: 26,
              ),
            const SizedBox(height: 16),
            Text(
              loading ? 'Loading script code…' : 'Could not load code',
              style: OrionType.sectionTitle,
            ),
            const SizedBox(height: 8),
            Text(
              loading
                  ? widget.item.provider.label
                  : _error ?? 'No code returned.',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: OrionType.body.copyWith(color: colors.muted),
            ),
            if (!loading) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('Retry loading'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _errorText(Object error) => error.toString().replaceFirst(
  RegExp(r'^(Exception|StateError|Bad state|FormatException):\s*'),
  '',
);

String _viewCount(int views) {
  if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M views';
  if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}k views';
  return '$views ${views == 1 ? 'view' : 'views'}';
}

String _updatedLabel(DateTime timestamp) {
  final date = timestamp.toLocal();
  return 'Updated ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

TextSpan _highlightLua(String source, OrionColors colors) {
  final pattern = RegExp(
    r'''--[^\n]*|"[^"\n]*"|'[^'\n]*'|\b(?:local|function|end|if|then|else|elseif|for|do|while|return|true|false|nil|in|and|or|not)\b|\b\d+(?:\.\d+)?\b''',
  );
  final spans = <TextSpan>[];
  var position = 0;
  for (final match in pattern.allMatches(source)) {
    if (match.start > position) {
      spans.add(TextSpan(text: source.substring(position, match.start)));
    }
    final token = match.group(0)!;
    final Color color;
    if (token.startsWith('--')) {
      color = colors.muted;
    } else if (token.startsWith('"') || token.startsWith("'")) {
      color = colors.readableAccent;
    } else if (RegExp(r'^\d').hasMatch(token)) {
      color = colors.readablePeach;
    } else {
      color = colors.readableLavender;
    }
    spans.add(
      TextSpan(
        text: token,
        style: TextStyle(color: color),
      ),
    );
    position = match.end;
  }
  if (position < source.length) {
    spans.add(TextSpan(text: source.substring(position)));
  }
  return TextSpan(children: spans);
}
