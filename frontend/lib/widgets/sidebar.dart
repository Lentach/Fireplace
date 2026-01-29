import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/rpg_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import 'conversation_item.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _startChat() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    context.read<ChatProvider>().clearError();
    context.read<ChatProvider>().startConversation(email);
    _emailController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser!.id;

    return SizedBox(
      width: 200,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: RpgTheme.tabBorder, width: 2),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '\u{1F4DC} PARTY',
              style: RpgTheme.pressStart2P(fontSize: 8, color: RpgTheme.gold),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _emailController,
                    style: RpgTheme.pressStart2P(fontSize: 7, color: Colors.white),
                    decoration: RpgTheme.rpgInputDecoration(hintText: 'email...').copyWith(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    ),
                    onSubmitted: (_) => _startChat(),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _startChat,
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: RpgTheme.buttonBg,
                    border: Border.all(color: RpgTheme.gold, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '+',
                    style: RpgTheme.pressStart2P(fontSize: 8, color: RpgTheme.gold),
                  ),
                ),
              ),
            ],
          ),
          if (chatProvider.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                chatProvider.errorMessage!,
                style: RpgTheme.pressStart2P(fontSize: 6, color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: chatProvider.conversations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final conv = chatProvider.conversations[index];
                final otherUser = conv.userOne.id == currentUserId
                    ? conv.userTwo
                    : conv.userOne;
                final isActive = conv.id == chatProvider.activeConversationId;

                return ConversationItem(
                  email: otherUser.email,
                  isActive: isActive,
                  onTap: () => chatProvider.openConversation(conv.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
