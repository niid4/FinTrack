import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/app_transaction.dart';
import '../models/merchant_rule.dart';
import '../services/transaction_capture_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  String _getConfidenceScore(WidgetRef ref, AppTransaction tx) {
    if (tx.isUncategorized || tx.customCategory == null) {
      return '0% Confidence';
    }
    
    // Check if there is a manual override or matching merchant rule
    final hive = ref.read(hiveServiceProvider);
    final rule = hive.getMerchantRule(tx.merchant.toLowerCase().trim());
    if (rule != null) {
      switch (rule.resolvedBy) {
        case 'manual':
          return '100% (Manual)';
        case 'dictionary':
          return '100% (Auto)';
        case 'places':
          return '90% (Places)';
        case 'keyword':
          return '85% (Pattern)';
        case 'llm':
          return '80% (Ollama)';
        default:
          return '95% (System)';
      }
    }
    return '100% (User)';
  }

  void _showEditBottomSheet(BuildContext context, WidgetRef ref, AppTransaction tx) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final categoriesAsync = ref.watch(allCategoriesProvider);
            final TextEditingController customController = TextEditingController();
            bool showCustomField = false;

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.95),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
              ),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Re-categorize "${tx.merchant}"',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Transaction amount: ₹${tx.amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppTheme.textLight),
                  ),
                  const SizedBox(height: 24),
                  
                  categoriesAsync.when(
                    data: (categories) {
                      // Filter active/all categories
                      final list = categories.map((c) => c.name).toSet().toList();
                      if (!list.contains('Other')) list.add('Other');

                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: list.map((catName) {
                          final isSelected = tx.customCategory == catName;
                          return ChoiceChip(
                            label: Text(catName, style: const TextStyle(color: Colors.white)),
                            selected: isSelected,
                            selectedColor: AppTheme.primaryCyan,
                            backgroundColor: Colors.white.withOpacity(0.08),
                            onSelected: (selected) async {
                              if (catName == 'Other') {
                                setModalState(() {
                                  showCustomField = true;
                                });
                              } else {
                                await _updateCategory(ref, tx, catName);
                                Navigator.pop(context);
                              }
                            },
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, __) => const SizedBox(),
                  ),

                  if (showCustomField) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: TextField(
                        controller: customController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Enter custom category',
                          hintStyle: TextStyle(color: Colors.white24),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        if (customController.text.trim().isNotEmpty) {
                          await _updateCategory(ref, tx, customController.text.trim());
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryCyan,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save Category', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateCategory(WidgetRef ref, AppTransaction tx, String categoryName) async {
    final hive = ref.read(hiveServiceProvider);
    
    // 1. Update Transaction
    tx.customCategory = categoryName;
    tx.isUncategorized = false;
    tx.isSkipped = false; // categorizing un-skips it
    await hive.saveTransaction(tx);

    // Dismiss the system categorize notification if it's still showing.
    final k = tx.key;
    if (k is int) {
      TransactionCaptureService.cancelCategorizeNotification(k);
    }

    // 2. Save / Update Merchant Rule for future learning
    final rule = MerchantRule()
      ..merchantName = tx.merchant.toLowerCase().trim()
      ..category = categoryName
      ..resolvedBy = 'manual';
    await hive.saveMerchantRule(rule);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txsAsync = ref.watch(transactionsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: AppTheme.backgroundGradient,
        child: SafeArea(
          child: txsAsync.when(
            data: (transactions) {
              if (transactions.isEmpty) {
                return const Center(
                  child: Text(
                    'No transactions logged yet.',
                    style: TextStyle(color: AppTheme.textLight, fontSize: 16),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                physics: const BouncingScrollPhysics(),
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final tx = transactions[index];
                  final formattedDate = '${tx.date.day} ${_getMonthName(tx.date.month)}, ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}';
                  final confidence = _getConfidenceScore(ref, tx);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Left Side info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        tx.merchant,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '₹${tx.amount.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryCyanGlow,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: (tx.isUncategorized
                                              ? AppTheme.accentPurple
                                              : AppTheme.primaryCyan).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: (tx.isUncategorized
                                                ? AppTheme.accentPurple
                                                : AppTheme.primaryCyan).withOpacity(0.3),
                                          ),
                                        ),
                                        child: Text(
                                          tx.customCategory ??
                                              (tx.isSkipped ? 'Skipped' : 'Uncategorized'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: tx.isUncategorized
                                                ? AppTheme.accentPurple
                                                : AppTheme.primaryCyanGlow,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        confidence,
                                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    formattedDate,
                                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Edit Button
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryCyan),
                              onPressed: () => _showEditBottomSheet(context, ref, tx),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
          ),
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }
}
