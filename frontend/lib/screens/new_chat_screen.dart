import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _requestSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _startChat() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _loading = true;
      _requestSent = false;
    });
    context.read<ChatProvider>().clearError();
    context.read<ChatProvider>().sendFriendRequest(email);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    // Listen for pending open conversation to navigate (mutual auto-accept)
    final pendingId = chat.consumePendingOpen();
    if (pendingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop(pendingId);
        }
      });
    }

    // Listen for server confirmation that friend request was sent
    if (chat.consumeFriendRequestSent() && _loading && !_requestSent) {
      _requestSent = true;
      _loading = false;
      final email = _emailController.text.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Friend request sent to $email'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      });
    }

    // Reset loading on error
    if (chat.errorMessage != null && _loading) {
      _loading = false;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add Friend',
          style: RpgTheme.bodyFont(
            fontSize: 18,
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the email of the person you want to add:',
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: RpgTheme.rpgInputDecoration(
                  hintText: 'user@example.com',
                  prefixIcon: Icons.email_outlined,
                  context: context,
                ),
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                onSubmitted: (_) => _startChat(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _startChat,
                child: _loading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    : const Text('Send Friend Request'),
              ),
              if (chat.errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  chat.errorMessage!,
                  style: RpgTheme.bodyFont(fontSize: 13, color: RpgTheme.errorColor),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
