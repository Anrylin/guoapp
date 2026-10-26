import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'core_bridge.dart';
import 'models.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.repository});
  final AppRepository repository;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedItem {
  _FeedItem(this.drama);
  final Drama drama;
  DramaDetail? detail;
  int episodeIndex = 0;
  PlaybackPlan? plan;
  bool loading = false;
  String? error;
}

String _errorText(Object error) =>
    error is AppFailure ? error.message : error.toString();

class _FeedScreenState extends State<FeedScreen> {
  static const _genres = [
    CatalogCategory('short_play', '真人'),
    CatalogCategory('comic_series', '漫剧'),
    CatalogCategory('ai_series', 'AI 剧'),
  ];

  final _page = PageController();
  final List<_FeedItem> _items = [];
  final List<StreamSubscription<dynamic>> _subs = [];

  Player? _player;
  VideoController? _controller;
  String? _playerError;

  String _genre = 'short_play';
  int _index = 0;
  int _generation = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _playing = false;
  bool _busy = false;
  bool _advancing = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initPlayer();
    unawaited(_load());
  }

  void _initPlayer() {
    try {
      final player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
          logLevel: MPVLogLevel.error,
        ),
      );
      _player = player;
      _controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: !Platform.isIOS,
        ),
      );
      _subs.add(
        player.stream.playing.listen((value) {
          if (mounted && value != _playing) setState(() => _playing = value);
        }),
      );
      _subs.add(
        player.stream.duration.listen((value) {
          if (mounted) setState(() => _duration = value);
        }),
      );
      _subs.add(
        player.stream.position.listen((value) {
          if (!mounted) return;
          if ((value - _position).abs() < const Duration(milliseconds: 400)) {
            return;
          }
          setState(() => _position = value);
        }),
      );
      _subs.add(
        player.stream.completed.listen((done) {
          if (done && mounted) unawaited(_nextEpisode());
        }),
      );
    } catch (error) {
      _playerError = '播放器初始化失败：${_errorText(error)}';
    }
  }

  @override
  void dispose() {
    _generation++;
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    unawaited(widget.repository.cancelRecommendations());
    unawaited(widget.repository.cancelPlayback());
    final session = _currentPlan?.session ?? '';
    if (session.isNotEmpty) unawaited(widget.repository.release(session));
    final player = _player;
    if (player != null) unawaited(player.dispose());
    _page.dispose();
    super.dispose();
  }

  PlaybackPlan? get _currentPlan =>
      _index >= 0 && _index < _items.length ? _items[_index].plan : null;

  _FeedItem? get _current =>
      _index >= 0 && _index < _items.length ? _items[_index] : null;

  Future<void> _load({bool more = false, bool force = false}) async {
    if (more && (_loadingMore || !_hasMore)) return;
    final generation = ++_generation;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final page = await widget.repository.recommendations(
        _genre,
        more: more,
        force: force,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (more) {
          final known = _items.map((item) => item.drama.id).toSet();
          for (final drama in page.items) {
            if (known.add(drama.id)) _items.add(_FeedItem(drama));
          }
        } else {
          _items
            ..clear()
            ..addAll(page.items.map(_FeedItem.new));
        }
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
      if (!more && _items.isNotEmpty) await _openIndex(0);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = _errorText(error);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _openIndex(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    _index = index;
    _advancing = false;
    if (index >= _items.length - 2 && _hasMore && !_loadingMore) {
      unawaited(_load(more: true));
    }
    if (item.plan != null && _planAlive(item.plan!)) {
      await _play(item);
      return;
    }
    await _prepare(item);
    await _play(item);
  }

  bool _planAlive(PlaybackPlan plan) {
    if (plan.url.isEmpty) return false;
    if (plan.expiresAt <= 0) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return plan.expiresAt - now > 30;
  }

  Future<void> _prepare(_FeedItem item) async {
    if (item.loading) return;
    item.loading = true;
    item.error = null;
    if (mounted && identical(item, _current)) setState(() {});
    try {
      final detail = item.detail ?? await widget.repository.detail(item.drama);
      item.detail = detail;
      if (detail.episodes.isEmpty) {
        throw AppFailure('这部剧暂时没有可播放的剧集');
      }
      if (item.episodeIndex < 0 || item.episodeIndex >= detail.episodes.length) {
        item.episodeIndex = 0;
      }
      final episode = detail.episodes[item.episodeIndex];
      item.plan = await widget.repository.resolve(item.drama, episode);
    } catch (error) {
      item.error = _errorText(error);
      item.plan = null;
    } finally {
      item.loading = false;
      if (mounted && identical(item, _current)) setState(() {});
    }
  }

  Future<void> _play(_FeedItem item) async {
    final player = _player;
    final plan = item.plan;
    if (player == null || plan == null) return;
    if (mounted) setState(() => _busy = true);
    try {
      await player.open(
        Media(plan.url, httpHeaders: plan.headers),
        play: true,
      );
      _position = Duration.zero;
      _duration = Duration.zero;
    } catch (error) {
      item.error = _errorText(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _nextEpisode() async {
    final item = _current;
    if (item == null || _advancing) return;
    _advancing = true;
    try {
      final detail = item.detail;
      if (detail != null && item.episodeIndex + 1 < detail.episodes.length) {
        final old = item.plan?.session ?? '';
        item.episodeIndex++;
        item.plan = null;
        if (old.isNotEmpty) unawaited(widget.repository.release(old));
        await _prepare(item);
        await _play(item);
        return;
      }
      if (_hasMore) await _load(more: true);
      if (_index + 1 < _items.length && _page.hasClients) {
        await _page.nextPage(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      _advancing = false;
    }
  }

  void _togglePlay() {
    final player = _player;
    if (player == null) return;
    if (player.state.playing) {
      unawaited(player.pause());
    } else {
      unawaited(player.play());
    }
  }

  Future<void> _changeGenre(String genre) async {
    if (genre == _genre) return;
    _genre = genre;
    _hasMore = true;
    _items.clear();
    _index = 0;
    await _load(force: true);
  }

  Future<void> _retry() async {
    final item = _current;
    if (item == null) return;
    item.detail = null;
    item.plan = null;
    await _prepare(item);
    await _play(item);
  }

  double get _progress {
    if (_duration.inMilliseconds <= 0) return 0;
    final value = _position.inMilliseconds / _duration.inMilliseconds;
    return value.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final blocked = _playerError != null || _player == null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _GenreBar(
              genres: _genres,
              current: _genre,
              onChanged: _changeGenre,
              onClose: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: blocked
                  ? _EmptyFeed(
                      error: _playerError ?? '播放器不可用',
                      onRetry: _initPlayer,
                    )
                  : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                  ? _EmptyFeed(error: _error, onRetry: () => _load(force: true))
                  : PageView.builder(
                      controller: _page,
                      scrollDirection: Axis.vertical,
                      itemCount: _items.length + (_hasMore ? 1 : 0),
                      onPageChanged: (index) {
                        if (index >= _items.length) {
                          unawaited(_load(more: true));
                          return;
                        }
                        unawaited(_openIndex(index));
                      },
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final item = _items[index];
                        final active = index == _index;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: active ? _togglePlay : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (active && controller != null)
                                Video(
                                  controller: controller,
                                  controls: NoVideoControls,
                                )
                              else
                                const ColoredBox(color: Colors.black),
                              const _BottomScrim(),
                              if (active && !_playing && !_busy)
                                const Center(
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    size: 76,
                                    color: Colors.white70,
                                  ),
                                ),
                              if (active && _busy)
                                const Center(
                                  child: SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              _FeedMeta(
                                item: item,
                                active: active,
                                onRetry: _retry,
                              ),
                              _FeedActions(
                                item: item,
                                onNext: () {
                                  if (!_page.hasClients) return;
                                  unawaited(
                                    _page.nextPage(
                                      duration: const Duration(
                                        milliseconds: 320,
                                      ),
                                      curve: Curves.easeOutCubic,
                                    ),
                                  );
                                },
                              ),
                              if (active)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: LinearProgressIndicator(
                                    value: _progress,
                                    minHeight: 2.5,
                                    backgroundColor: Colors.white24,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreBar extends StatelessWidget {
  const _GenreBar({
    required this.genres,
    required this.current,
    required this.onChanged,
    required this.onClose,
  });
  final List<CatalogCategory> genres;
  final String current;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('feed-close'),
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          for (final genre in genres)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: TextButton(
                onPressed: () => onChanged(genre.id),
                style: TextButton.styleFrom(
                  foregroundColor: genre.id == current
                      ? theme.colorScheme.primary
                      : Colors.white70,
                  textStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: genre.id == current
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
                child: Text(genre.name),
              ),
            ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: Icon(Icons.swipe_vertical_rounded, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.center,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xCC000000)],
        ),
      ),
    ),
  );
}

class _FeedMeta extends StatelessWidget {
  const _FeedMeta({
    required this.item,
    required this.active,
    required this.onRetry,
  });
  final _FeedItem item;
  final bool active;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = item.detail;
    Episode? episode;
    if (detail != null &&
        detail.episodes.isNotEmpty &&
        item.episodeIndex >= 0 &&
        item.episodeIndex < detail.episodes.length) {
      episode = detail.episodes[item.episodeIndex];
    }
    return Positioned(
      left: 16,
      right: 84,
      bottom: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.drama.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (episode != null) _Chip(text: '第 ${episode.number} 集'),
              if (detail != null) _Chip(text: '共 ${detail.episodes.length} 集'),
              if (item.drama.category.isNotEmpty)
                _Chip(text: item.drama.category),
            ],
          ),
          if (active && item.error != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(
                  child: Text(
                    item.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFFB4A8),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('重试'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0x33FFFFFF),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 11.5),
    ),
  );
}

class _FeedActions extends StatelessWidget {
  const _FeedActions({required this.item, required this.onNext});
  final _FeedItem item;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final detail = item.detail;
    return Positioned(
      right: 10,
      bottom: 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (detail != null && detail.episodes.length > 1)
            _ActionButton(
              icon: Icons.list_rounded,
              label: '选集',
              onTap: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: const Color(0xFF141417),
                builder: (_) => _EpisodeSheet(item: item),
              ),
            ),
          _ActionButton(
            icon: Icons.keyboard_double_arrow_down_rounded,
            label: '下一条',
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0x40000000),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _EpisodeSheet extends StatelessWidget {
  const _EpisodeSheet({required this.item});
  final _FeedItem item;

  @override
  Widget build(BuildContext context) {
    final detail = item.detail;
    if (detail == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SafeArea(
      child: GridView.builder(
        padding: const EdgeInsets.all(14),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.6,
        ),
        itemCount: detail.episodes.length,
        itemBuilder: (context, index) {
          final selected = index == item.episodeIndex;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              item.episodeIndex = index;
              item.plan = null;
              Navigator.of(context).maybePop();
            },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.18)
                    : const Color(0xFF1B1B20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : const Color(0x1AFFFFFF),
                ),
              ),
              child: Text(
                '${detail.episodes[index].number}',
                style: TextStyle(
                  color: selected ? theme.colorScheme.primary : Colors.white,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.error, required this.onRetry});
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.movie_filter_outlined,
            color: Colors.white38,
            size: 42,
          ),
          const SizedBox(height: 12),
          Text(
            error ?? '推荐流暂时没有内容',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    ),
  );
}
