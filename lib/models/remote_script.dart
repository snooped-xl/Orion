enum ScriptProvider { robloxScripts, scriptBlox, haxHell, rscripts }

extension ScriptProviderDetails on ScriptProvider {
  String get label => switch (this) {
    ScriptProvider.robloxScripts => 'RobloxScripts',
    ScriptProvider.scriptBlox => 'ScriptBlox',
    ScriptProvider.haxHell => 'HaxHell',
    ScriptProvider.rscripts => 'Rscripts',
  };

  String get domain => switch (this) {
    ScriptProvider.robloxScripts => 'robloxscripts.com',
    ScriptProvider.scriptBlox => 'scriptblox.com',
    ScriptProvider.haxHell => 'haxhell.com',
    ScriptProvider.rscripts => 'rscripts.net',
  };
}

class RemoteScript {
  const RemoteScript({
    required this.id,
    required this.provider,
    required this.title,
    required this.game,
    required this.description,
    this.body,
    this.rawUrl,
    this.imageUrl,
    required this.externalUrl,
    this.views = 0,
    this.updatedAt,
    this.isPaid = false,
    this.hasKey = false,
    this.isVerified = false,
  });

  final String id;
  final ScriptProvider provider;
  final String title;
  final String game;
  final String description;
  final String? body;
  final String? rawUrl;
  final String? imageUrl;
  final String externalUrl;
  final int views;
  final DateTime? updatedAt;
  final bool isPaid;
  final bool hasKey;
  final bool isVerified;

  String get key => '${provider.name}:$id';

  Map<String, Object?> toJson() => {
    'id': id,
    'provider': provider.name,
    'title': title,
    'game': game,
    'description': description,
    'body': body,
    'rawUrl': rawUrl,
    'imageUrl': imageUrl,
    'externalUrl': externalUrl,
    'views': views,
    'updatedAt': updatedAt?.toIso8601String(),
    'isPaid': isPaid,
    'hasKey': hasKey,
    'isVerified': isVerified,
  };

  static RemoteScript? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final providerName = value['provider'];
    final providers = ScriptProvider.values.where(
      (provider) => provider.name == providerName,
    );
    final id = value['id'];
    final title = value['title'];
    if (providers.isEmpty || id is! String || id.isEmpty || title is! String) {
      return null;
    }
    return RemoteScript(
      id: id,
      provider: providers.first,
      title: title,
      game: value['game'] is String
          ? value['game'] as String
          : 'Universal Script',
      description: value['description'] is String
          ? value['description'] as String
          : '',
      body: value['body'] is String ? value['body'] as String : null,
      rawUrl: value['rawUrl'] is String ? value['rawUrl'] as String : null,
      imageUrl: _restoreImageUrl(value['imageUrl'], providers.first),
      externalUrl: value['externalUrl'] is String
          ? value['externalUrl'] as String
          : '',
      views: value['views'] is num
          ? (value['views'] as num).toInt().clamp(0, 0x7FFFFFFFFFFFFFFF)
          : 0,
      updatedAt: value['updatedAt'] is String
          ? DateTime.tryParse(value['updatedAt'] as String)
          : null,
      isPaid: value['isPaid'] == true,
      hasKey: value['hasKey'] == true,
      isVerified: value['isVerified'] == true,
    );
  }

  static String? _restoreImageUrl(Object? value, ScriptProvider provider) {
    if (value is! String ||
        value.trim().isEmpty ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      return null;
    }
    try {
      final uri = Uri.https(provider.domain).resolve(value.trim());
      if (!['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        return null;
      }
      return uri.toString();
    } on FormatException {
      return null;
    }
  }
}

class ScriptPage {
  const ScriptPage({required this.items, required this.hasMore});

  final List<RemoteScript> items;
  final bool hasMore;
}
