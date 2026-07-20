import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/poll_model.dart';
import '../../services/voting_service.dart';
import '../../services/analytics_service.dart';
import '../../services/fantasy_auth_service.dart';

class HomeModals {
  static void showVotingBottomSheet(
      BuildContext context, List<Poll> activePolls, String seasonId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text("PREMIAÇÕES ABERTAS",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 16),
            ...activePolls.map((poll) {
              final user =
                  Provider.of<FantasyAuthService>(context, listen: false).user;
              return FutureBuilder<bool>(
                  future: user != null
                      ? VotingService()
                          .hasUserVoted(seasonId, poll.id, user.uid)
                      : Future.value(false),
                  builder: (context, voteSnapshot) {
                    final hasVoted = voteSnapshot.data ?? false;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: hasVoted
                            ? Colors.green.withOpacity(0.1)
                            : const Color(0xFFC5A814).withOpacity(0.2),
                        child: Icon(hasVoted ? Icons.check : Icons.how_to_vote,
                            color: hasVoted
                                ? Colors.green
                                : const Color(0xFFC5A814)),
                      ),
                      title: Text(poll.title,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: hasVoted ? Colors.grey : Colors.black87)),
                      subtitle: Text(
                          poll.category.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold)),
                      trailing: hasVoted
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFC5A814),
                                  foregroundColor: Colors.black87,
                                  elevation: 0),
                              onPressed: () {
                                AnalyticsService.logCustomScreenView(
                                    'Home_Click_Voting_Banner',
                                    parameters: {'poll_id': poll.id});
                                Navigator.pushNamed(context, '/voting',
                                        arguments: poll)
                                    .then((_) {
                                  if (context.mounted) Navigator.pop(ctx);
                                });
                              },
                              child: const Text("VOTAR",
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11)),
                            ),
                      onTap: () {
                        AnalyticsService.logCustomScreenView(
                            'Home_Click_Voting_Banner',
                            parameters: {'poll_id': poll.id});
                        Navigator.pushNamed(context, '/voting', arguments: poll)
                            .then((_) {
                          if (context.mounted) Navigator.pop(ctx);
                        });
                      },
                    );
                  });
            }).toList(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
