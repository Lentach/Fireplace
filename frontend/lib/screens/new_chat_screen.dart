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

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _startChat() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _loading = true);
    final chat = context.read<ChatProvider>();
    chat.clearError();
    chat.startConversation(email);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    // Listen for pending open conversation to navigate
    final pendingId = chat.consumePendingOpen();
    if (pendingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop(pendingId);
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
          'New Chat',
          style: RpgTheme.bodyFont(
            fontSize: 18,
            color: Colors.white,
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
                'Enter the email of the person you want to chat with:',
                style: RpgTheme.bodyFont(fontSize: 14, color: RpgTheme.labelText),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                style: RpgTheme.bodyFont(fontSize: 14, color: Colors.white),
                decoration: RpgTheme.rpgInputDecoration(
                  hintText: 'user@example.com',
                  prefixIcon: Icons.email_outlined,
                ),
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                onSubmitted: (_) => _startChat(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _startChat,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: RpgTheme.gold,
                        ),
                      )
                    : const Text('Start Chat'),
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
