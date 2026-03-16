import 'dart:async';
import 'package:flutter/material.dart';
import '../services/gif_service.dart';
import '../l10n/app_localizations.dart';

class GifPickerSheet extends StatefulWidget {
  final void Function(String gifFullUrl) onGifSelected;

  const GifPickerSheet({super.key, required this.onGifSelected});

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();

  static Future<void> show(BuildContext context, {required void Function(String) onGifSelected}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: GifPickerSheet(onGifSelected: onGifSelected),
      ),
    );
  }
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  final _gifService = GifService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  List<GifModel> _gifs = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  Timer? _debounce;
  int _offset = 0;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTrending();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _gifService.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    setState(() { _loading = true; _error = null; _offset = 0; _lastQuery = ''; });
    final results = await _gifService.fetchTrending();
    if (!mounted) return;
    setState(() {
      _gifs = results;
      _loading = false;
      _error = results.isEmpty ? 'no_results' : null;
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _loadTrending();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _doSearch(query.trim()));
  }

  Future<void> _doSearch(String query) async {
    setState(() { _loading = true; _error = null; _offset = 0; _lastQuery = query; });
    final results = await _gifService.search(query);
    if (!mounted) return;
    setState(() {
      _gifs = results;
      _loading = false;
      _error = results.isEmpty ? 'no_results' : null;
    });
  }

  void _onScroll() {
    if (_loadingMore) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    _offset += 25;
    final results = _lastQuery.isEmpty
        ? await _gifService.fetchTrending(offset: _offset)
        : await _gifService.search(_lastQuery, offset: _offset);
    if (!mounted) return;
    setState(() {
      _gifs.addAll(results);
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: theme.dividerColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: l10n.gifSearchHint,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error == 'no_results'
                  ? Center(child: Text(l10n.gifNoResults, style: theme.textTheme.bodyMedium))
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: _gifs.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _gifs.length) {
                          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                        }
                        final gif = _gifs[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            widget.onGifSelected(gif.fullUrl);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              gif.previewUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, e, st) => Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.broken_image, size: 32),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Powered by GIPHY', style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}
