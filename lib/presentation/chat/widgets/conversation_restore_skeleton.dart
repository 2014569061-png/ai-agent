import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/nexus_loading_skeleton.dart';

class ConversationRestoreSkeleton extends StatelessWidget {
  const ConversationRestoreSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const NexusChatMessageSkeleton(),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Semantics(
                liveRegion: true,
                label: '正在恢复会话',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Text('正在恢复会话…'),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}
