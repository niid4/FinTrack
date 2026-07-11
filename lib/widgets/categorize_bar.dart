import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_transaction.dart';
import '../models/merchant_rule.dart';
import '../providers/providers.dart';
import '../services/transaction_capture_service.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';

class CategorizeBar extends ConsumerStatefulWidget {
  final AppTransaction transaction;
  final VoidCallback onCategorized;

  const CategorizeBar({
    Key? key,
    required this.transaction,
    required this.onCategorized,
  }) : super(key: key);

  @override
  ConsumerState<CategorizeBar> createState() => _CategorizeBarState();
}

class _CategorizeBarState extends ConsumerState<CategorizeBar> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _showCustomField = false;
  final TextEditingController _customController = TextEditingController();

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (!_isExpanded) _showCustomField = false;
    });
  }

  void _selectCategory(String name) async {
    // Quick visual confirmation then collapse
    widget.transaction.isUncategorized = false;
    widget.transaction.isSkipped = false;
    widget.transaction.customCategory = name;
    
    final hive = ref.read(hiveServiceProvider);
    await hive.saveTransaction(widget.transaction);

    // Learn: save merchant rule so next time this merchant is auto-categorized
    final merchant = widget.transaction.merchant;
    if (merchant.isNotEmpty && merchant != 'Unknown') {
      final merchantKey = merchant.toLowerCase().trim();
      final existing = hive.getMerchantRule(merchantKey);
      if (existing == null) {
        final rule = MerchantRule()
          ..merchantName = merchantKey
          ..category = name
          ..resolvedBy = 'user';
        await hive.saveMerchantRule(rule);
      }
    }

    // If the system categorize notification for this tx is still showing,
    // it's now stale — dismiss it.
    final key = widget.transaction.key;
    if (key is int) {
      TransactionCaptureService.cancelCategorizeNotification(key);
    }

    HapticFeedback.lightImpact();
    
    setState(() {
      _isExpanded = false;
      _showCustomField = false;
    });
    
    // Slight delay for animation before removing it
    Future.delayed(const Duration(milliseconds: 300), () {
      widget.onCategorized();
    });
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(selectedCategoriesProvider);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              onTap: _toggleExpand,
              leading: CircleAvatar(
                backgroundColor: AppTheme.accentPurple.withOpacity(0.2),
                child: const Icon(Icons.question_mark, color: Colors.white),
              ),
              title: Text(widget.transaction.merchant, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Uncategorized'),
              trailing: Text(
                '₹${widget.transaction.amount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            if (_isExpanded)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Quick Picks', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Personal', 'Friend', 'Rent', 'Gift'].map((c) => ActionChip(
                        label: Text(c),
                        backgroundColor: Colors.white.withValues(alpha: 0.5),
                        onPressed: () => _selectCategory(c),
                      )).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Categories', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: categoriesAsync.when(
                        data: (cats) {
                          return ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              ...cats.map((c) => Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ActionChip(
                                  label: Text(c.name),
                                  backgroundColor: AppTheme.primaryCyan.withOpacity(0.15),
                                  onPressed: () => _selectCategory(c.name),
                                ),
                              )),
                              ActionChip(
                                label: const Text('Other'),
                                backgroundColor: Colors.white.withValues(alpha: 0.5),
                                onPressed: () {
                                  setState(() => _showCustomField = true);
                                },
                              ),
                            ],
                          );
                        },
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (_, __) => const SizedBox(),
                      ),
                    ),
                    if (_showCustomField) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customController,
                              decoration: const InputDecoration(
                                hintText: 'Custom label...',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check, color: AppTheme.primaryCyan),
                            onPressed: () {
                              if (_customController.text.isNotEmpty) {
                                _selectCategory(_customController.text);
                              }
                            },
                          )
                        ],
                      )
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
