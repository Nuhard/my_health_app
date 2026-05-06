// ==================== lib/widgets/sync_status_widget.dart ====================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';

class SyncStatusWidget extends StatelessWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, syncProvider, child) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () {
              if (!syncProvider.isSyncing) {
                syncProvider.forceSyncNow();
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Status Icon with animation
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: syncProvider.getSyncStatusColor().withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: syncProvider.isSyncing
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                syncProvider.getSyncStatusColor(),
                              ),
                            ),
                          )
                        : Icon(
                            syncProvider.getSyncStatusIcon(),
                            color: syncProvider.getSyncStatusColor(),
                            size: 24,
                          ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Status Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          syncProvider.getSyncStatusMessage(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (syncProvider.unsyncedItems > 0)
                          Text(
                            'Tap to sync now',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Action Button
                  if (!syncProvider.isSyncing && syncProvider.isOnline)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => syncProvider.forceSyncNow(),
                      tooltip: 'Sync now',
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

